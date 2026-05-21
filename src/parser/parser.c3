module c3_parser::parser;

import lexer;
import string_pool;
import line_map;

import c3_parser::ast;
import c3_parser::common;
import c3_parser::registry;
import c3_parser::workspace @norecurse;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::maybe;

faultdef
	UNKNOWN,
	UNEXPECTED_EOS, 
	MODULE_HEADER_FAILED, 
	CONTRACT_NOT_ALLOWED, 
	INVALID_PATH,
	NOT_A_PATH,
	PATH_TOO_LONG, 
	EXPECTED_EXPRESSION, 
	UNEXPECTED_TOKEN,
;

// length in parts, eg: foo::bar = 2 parts
const uint PATH_MAX_LENGTH = 16;

// Scratch Buffer
tlocal List{uint} scratch;

fn uint[] scratch_view(uint index, uint len)
{
	return scratch.entries[index:len];
}

// defer so it always runs even if the function returns fault
macro @with_scratch(; @body(index))
{
	uint watermark = (uint)scratch.len();
	defer scratch.size = (Size)watermark;
	@body(watermark);
}

// defer so it always runs even if the function returns fault
macro @scratch(; @body())
{
	Size watermark = scratch.len();
	defer scratch.size = watermark;
	@body();
}


bitstruct ParseFlags : ulong
{
	bool is_interface; // Skip function bodies, disallow fields
	bool is_global; // Top-level declarations
	bool is_local; // Inside a function/block
	bool is_var; // has a 'var'
	bool is_tlocal; // has a 'tlocal'
	bool is_inline;
	bool is_static;
	bool is_extern; // C-linkage handling
	bool is_thread_local;
	bool is_attribute; // Special parsing for @attr(...)
	bool is_type_only; // Used for casts or sizeof where names aren't expected
	bool is_const; // Context requires constant expressions
	bool is_constdef;
	bool is_call;
	bool is_expr;
	bool is_stmt;
	bool is_lamda;
	bool is_macro;
	bool is_comptime;
	bool type_as_expression;
	bool no_generics; // dont allow type parsing to check for generics
	bool skip_eos;
}

struct Parser
{
	LineMap* line_map;
	StringPool* pool;
	Ast* ast;
	Module* mod;
	SourceFile* sf;
	Token[] tokens;
	String file_path; // current file being parsed
	String src;
	Allocator allocator;

	uint pos;
	Node contract;
	// for when using debbugers so i can keep track of what its at
	Token current_token @if(env::DEBUG_SYMBOLS);
	String current_token_string @if(env::DEBUG_SYMBOLS);
	// bool allow_submodules;
}

fn void? Parser.skip_until(Parser* p, TokenKind[] targets)
{
    while (!p.eof())
    {
        TokenKind current = p.current().kind;
        
        foreach (t : targets)
        {
            if (current == t) return;
        }

        if (current == EOS || current == RBRACE) return;

        advance(p)!;
    }
}

fn Node Parser.push_invalid_node(Parser* p, uint start_pos)
{
    uint end_pos = p.current_pos();
    return p.ast.add_node(INVALID, start_pos, end_pos, 0);
}

<*
 synchronize the top level/recover top level
 @param [&inout] p
*>
fn void? synchronize(Parser* p)
{
	int brace_depth = 0;

	while (!p.eof())
	{
		Token t = p.current();
		Location loc = p.line_map.resolve((Size)t.pos);

		// Track depth to ensure we aren't inside a body
		if (t.kind == LBRACE) brace_depth++;
		if (t.kind == RBRACE)
		{
			brace_depth = (brace_depth > 0) ? brace_depth - 1 : 0;
		}

		if (brace_depth <= 0 && loc.column == 1)
		{
			switch (t.kind)
			{
				case CONTRACT:
				case MODULE:
				case IMPORT:
				case ALIAS:
				case TYPEDEF:
				case FN:
				case MACRO:
				case STRUCT:
				case CONST:
				case ENUM:
				case EXTERN:
					return;
				default:
					break;
			}
		}

		if (brace_depth <= 0 && t.kind == EOS)
		{
			advance(p)!;
			return;
		}

		advance(p)!;
	}
}

fn bool Parser.eof(&self) @inline
{
	return self.pos >= self.tokens.len || self.is(EOF);
}

fn bool Parser.is(&self, TokenKind kind)
{
	return self.tokens[self.pos].kind == kind;
}

fn Token Parser.current(&self) @inline
{
	return self.peek(0);
}

fn Token Parser.peek(&self, uint pos = 1) @inline
{
	assert ((Size)self.pos + pos < self.tokens.len);
	return self.tokens[(Size)self.pos + pos];
}

fn uint Parser.current_pos(Parser* self) @inline
{
	return self.current().pos;
}

fn uint Parser.previous_pos(Parser* self) @inline
{
	return self.tokens[(Size)self.pos - 1].pos;
}

fn void Parser.print_current(&self)
{
	log::debug("%s", self.token_text(self.current()));
}

fn void? reverse(Parser* parser, uint position)
{
	parser.pos = position;
	advance(parser, 0)!;
}

fn void? Parser.advance(Parser* parser, uint len = 1)
{
	return advance(parser, len)!;
}

<*
 @param [&inout] parser
*>
fn void? advance(Parser* parser, uint len = 1)
{
	if (parser.eof())
	{
		log::debug("parser::advance() : eof");
		return io::EOF~;
	}

	parser.pos += len;

	$if env::DEBUG_SYMBOLS:
    if (!parser.eof()) 
    {
        parser.current_token = parser.current();
        parser.current_token_string = parser.token_text(parser.current());
    }
    else 
    {
        parser.current_token_string = "EOF";
    }
    $endif
}

<*
 a macro just so that it logs where it happened
 @param [&inout] parser
*>
macro void? expect(Parser* parser, TokenKind kind)
{
	if (!parser.is(kind))
	{
		parser.error("Expected '%s' got '%s'", kind.description, parser.current().kind.description);
		log::error("Error happened here");
	}
	else
	{
		advance(parser)!;
	}
}

<*
 @param [&inout] parser
 @param kind : "type to consume"
*>
fn bool? consume(Parser* parser, TokenKind kind)
{
	if (parser.eof()) return io::EOF~;
	if (parser.is(kind))
	{
		advance(parser)!;
		return true;
	}

	return false;
}

fn String Parser.token_text(Parser* self, Token t) @inline
{
	return self.src[t.pos:t.len];
}

fn String Parser.current_text(Parser* self) @inline
{
	return self.token_text(self.current());
}

fn String peek_module_name(Parser* p)
{
	if (p.tokens[0].kind == MODULE)
	{
		// Start collecting the name after the 'module' keyword
		String full_name = "";

		Size i = 1;
		while (i < p.tokens.len)
		{
			Token t = p.tokens[i];

			if (t.kind == IDENT)
			{
				String part = p.token_text(t);
				full_name = full_name.tconcat(part);
			}
			else if (t.kind == SCOPE)
			{
				full_name = full_name.tconcat("::");
			}
			else if (t.kind == EOS)
			{
				break; // End of module declaration
			}

			i++;
		}
		return full_name;
	}

	return "";
}

<*
 Parse a specific file.
  Appends the nodes to the provided Modules Ast
 @param [&inout] ws
*>
fn void? parse_file(Workspace* ws, String path)
{
	Parser parser = { .mod = null, .pool = &ws.strings, .file_path = path, .allocator = ws.allocator };

	if (!scratch.is_initialized())
	{
		scratch.tinit(1000);
	}

	scratch.clear();

	String src = (String)file::load(tmem, path)!;
	Lexer lexer = { .buffer = src, .index = 0, };

	parser.src = src;

	List{Token} tokens;
	tokens.init(parser.allocator, 1000);
	defer tokens.free();
	while (try token = lexer.next())
	{
		tokens.push(token);
		log::debug("Added token: <%s> - %s", token.kind, parser.token_text(token));
	}

	tokens.push({ .kind = EOF, .pos = (tokens.last().pos + tokens.last().len) ?? 0, .len = 0 });
	parser.tokens = tokens.array_view();

	SourceFile* sf = ws.reset_source_file(path);
	sf.source = src;
	parser.sf = sf;
	parser.ast = &sf.ast;
	parser.line_map = &sf.line_map;
	parser.line_map.build(src);

	// Module* mod = ws.get_or_create_module(mod_name);
	// parser.mod = mod;

	log::info("parsing file: %s", path);

	// ModuleSection* section = workspace::get_or_create_section(mod, path);
	// assert(section != null);
	// section.source = src;
	// section.start_node_idx = (uint)mod.ast.len();

	String mod_name = peek_module_name(&parser);
	if (mod_name == "")
	{
		// parser.allow_submodules = false;
		mod_name = path_to_module_name(path)!;

		Module* mod = ws.get_or_create_module(mod_name);
		ModuleSection* sec = ws.get_or_create_section(mod, parser.sf);
		parser.mod = mod;
		sec.start_node_idx = 0;
		log::info("Inferred module: %s", mod_name);
	}

	while (!parser.eof())
	{
		if (catch err = parse_top_level(&parser, ws))
		{
			if (err == io::EOF)
			{
				break;
			}

			synchronize(&parser)!;
			continue;
		}
	}

	if (try last_sec = parser.sf.sections.last())
	{
		last_sec.end_node_idx = parser.sf.ast.len();
	}

	log::info("Succesfully parsed: %s", path);
}

fn String? path_to_module_name(String path)
{
	String base_name = path.file_tbasename()!;
	return base_name.strip_suffix(".c3");
}

fn void? parse_top_level(Parser* p, Workspace* ws)
{
	log::debug("parse_top_level: %s", p.token_text(p.current()));

	Node node;
	ParseFlags flags = { .is_global = true };

	// the individual parse functions will check that the modifiers are used appropiately
	while (true)
	{
		Token t = p.current();

		if (t.kind == EXTERN)
		{
			if (flags.is_extern) p.error("Duplicate 'extern' modifier");
			flags.is_extern = true;
		}
		else if (t.kind == TLOCAL)
		{
			if (flags.is_thread_local) p.error("Duplicate 'tlocal' modifier");
			flags.is_thread_local = true;
		}
		else if (t.kind == INLINE)
		{
			if (flags.is_inline) p.error("Duplicate 'inline' modifier");
			flags.is_inline = true;
		}
		else
		{
			break;
		}

		advance(p)!;
	}

	if (is_type(p))
	{
		node = parse_var_decl(p, flags)!;
		if (node.is_valid())
		{
			p.ast.top_level_nodes.push((uint)node);
			return;
		}
	}

	if (p.current().kind == IMPORT)
	{
		advance(p)!;
		while (true)
		{
			uint start = p.current_pos();

			Node? path_node = parse_path(p);
			if (catch err = path_node)
			{
				p.error("failed to parse path for module: %s", err);
				return err~;
			}

			Node attr = parse_attributes(p)!;

			uint[*] data = views::@data{ImportViewFields}
			(
				PATH, path_node,
				ATTRIBUTES, attr,
			);

			uint ex = p.ast.push_extra_block(&data);
			Node imp_node = p.ast.add_node(IMPORT_DECL, start, p.current_pos(), ex);
			p.ast.top_level_nodes.push((uint)imp_node);
			if (!consume(p, COMMA)!) break;
		}
		expect(p, EOS)!;
		return;
	}

	switch (p.current().kind)
	{
		case CONTRACT:
			node = parse_contract(p)!;
			p.contract = node;
		case INTERFACE:
			node = parse_interface(p)!;
		case MODULE:
			node = parse_module(p, ws)!;
		case FAULTDEF:
			node = parse_faultdef_decl(p)!;
		case FN:
			node = parse_fn_decl(p, flags)!;
		case MACRO:
			node = parse_macro_decl(p)!;
		case ALIAS:
			node = parse_alias(p)!;
		case TYPEDEF:
			node = parse_typedef(p)!;
		case ATTRDEF:
			node = parse_attrdef(p)!;
		case UNION:
		case STRUCT:
			node = parse_struct(p)!;
		case BITSTRUCT:
			node = parse_bitstruct_decl(p)!;
		case CONSTDEF:
			flags.is_constdef = true;
			node = parse_enum(p, flags)!;
		case ENUM:
			node = parse_enum(p, flags)!;
		case CONST:
			flags.is_const = true;
			advance(p)!;
			node = parse_var_decl(p, flags)!;
		case CT_ASSERT:
			uint start_pos = p.current_pos();
			Node stmt = parse_ct_assert(p)!;
			node = p.ast.add_node(CT_ASSERT_DECL, start_pos, p.current_pos(), (uint)stmt);
		case EOS:
			p.error("<EOS> appeared in parse_top_level");
			advance(p)!;
			return UNEXPECTED_EOS~;
		default:
			p.error("Couldn't find any matching top level declaration: %s", string::from_struct(tmem, p.current()));
			return UNEXPECTED_TOKEN~;
	}

	// if (node.is_valid())
	// {
	p.ast.top_level_nodes.push((uint)node);

	if (p.contract.is_valid())
	{
		attach_contract(p, node, p.contract);
	}

	p.contract = {};
	// }
}
