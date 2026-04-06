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
	PATH_TOO_LONG,
	TOO_MANY_INTERFACE_IMPL,
	TOO_MANY_GENERICS,
	EXPECTED_EXPRESSION,
	UNEXPECTED_TOKEN,
;

// length in parts, eg: foo::bar = 2 parts
const uint PATH_MAX_LENGTH = 16;

bitstruct ParseFlags : uint
{
    bool is_interface;   // Skip function bodies, disallow fields
    bool is_global;      // Top-level declarations
    bool is_local;       // Inside a function/block
	bool is_var;         // has a 'var'
	bool is_inline;
    bool is_extern;      // C-linkage handling
	bool is_thread_local;
    bool is_attribute;   // Special parsing for @attr(...)
    bool is_type_only;   // Used for casts or sizeof where names aren't expected
    bool is_const;       // Context requires constant expressions
	bool is_call;
	bool is_lamda;
	bool is_macro;

	bool no_generics; // dont allow type parsing to check for generics
}

struct Parser
{
	LineMap line_map;
	StringPool* pool;
	Ast* ast;
	Module* mod;
	Token[] tokens;
	String file_path; // current file being parsed
	String src;
	uint pos;
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
        Location loc = p.line_map.resolve((usz)t.pos);

        // Track depth to ensure we aren't inside a body
        if (t.kind == TokenKind.LBRACE) brace_depth++;
        if (t.kind == TokenKind.RBRACE)
		{
			brace_depth = (brace_depth > 0) ? brace_depth - 1 : 0;
		} 

        if (brace_depth <= 0 && loc.col == 1)
        {
            switch (t.kind)
            {
				case TokenKind.CONTRACT:
				case TokenKind.MODULE:
				case TokenKind.IMPORT:
				case TokenKind.ALIAS:
				case TokenKind.TYPEDEF:
				case TokenKind.FN:
				case TokenKind.MACRO:
				case TokenKind.STRUCT:
				case TokenKind.CONST:
				case TokenKind.ENUM:
				case TokenKind.EXTERN:
                    return;
                default:
                    break;
            }
        }

        if (brace_depth <= 0 && t.kind == TokenKind.EOS)
        {
            advance(p)!;
            return;
        }

        advance(p)!;
    }
}

fn bool Parser.eof(&self) @inline
{
	return self.pos >= self.tokens.len || self.is(TokenKind.EOF);
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
	assert((usz)(self.pos + pos) < self.tokens.len);
	return self.tokens[self.pos + pos];
}

fn void Parser.print_current(&self)
{
	log::debug("%s", self.token_text(self.current()));
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
}

<*
	a macro just so that it logs where it happened

	@param [&inout] parser
*>
macro void? expect(Parser* parser, TokenKind kind)
{
	if (!parser.is(kind))
	{
		parser.error("Expected '%s' got '%s'", kind.nameof, parser.current().kind.nameof);
		log::error("Error happened here");
		return UNEXPECTED_TOKEN~;
	}

	advance(parser)!;
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
    for (usz i = 0; i < p.tokens.len; i++)
    {
        if (p.tokens[i].kind == TokenKind.MODULE)
        {
            // Start collecting the name after the 'module' keyword
            usz j = i + 1;
            String full_name = "";

            while (j < p.tokens.len)
            {
                Token t = p.tokens[j];
                
                if (t.kind == TokenKind.IDENT) 
				{
                    String part = p.token_text(t); 
                    full_name = full_name.tconcat(part);
                } 
                else if (t.kind == TokenKind.SCOPE) 
				{
                    full_name = full_name.tconcat("::");
                } 
                else if (t.kind == TokenKind.EOS) 
				{
                    break; // End of module declaration
                }
                
                j++;
            }
            return full_name;
        }
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
	Parser parser = (Parser){
		.mod = null,
		.pool = &ws.strings,
		.file_path = path,
	};

	String src = (String)file::load(tmem, path)!;
	Lexer lexer = (Lexer){
		.buffer = src,
		.index = 0,
	};

	parser.src = src;

	List{ Token } tokens;
	tokens.tinit(1000);
	defer tokens.free();
	while (try token = lexer.next())
	{
		tokens.push(token);
		log::debug("Added token: <%s> - %s", token.kind, parser.token_text(token));
	}
	parser.tokens = tokens.array_view();
	parser.line_map.build(src);

	String mod_name = peek_module_name(&parser);
    
    if (mod_name == "") 
	{
        mod_name = path_to_module_name(path)!;
        log::info("Inferred module: %s", mod_name);
    }
	Module* mod = workspace::get_or_create_module(ws, mod_name);
	parser.mod = mod;
	parser.ast = &mod.ast;

	log::info("parsing file: %s", path);

	ModuleSection* section = workspace::get_or_create_section(mod, path);
	assert(section != null);

	while (!parser.eof())
	{
		uint start_idx = (uint)mod.ast.len();

		if (catch err = parse_top_level(&parser, ws))
		{	
			if (err == io::EOF)
			{
				log::error("EOF");
				return err~;
			}

			synchronize(&parser)!;
			continue;
		}

		uint end_idx = (uint)mod.ast.len();
		if (end_idx > start_idx) 
		{
			Node latest_node = (Node)mod.ast.kinds[start_idx];

			if (!section.header_node.is_valid())
			{
				section.header_node = latest_node;
			}
			section.node_count += (end_idx - start_idx);
		}
	}
}

fn String? path_to_module_name(String path)
{
    String base_name = path.file_tbasename()!;
	return base_name.strip_end(".c3");
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
        
        if (t.kind == TokenKind.EXTERN) 
        {
            if (flags.is_extern) p.error("Duplicate 'extern' modifier");
            flags.is_extern = true;
        }
        else if (t.kind == TokenKind.TLOCAL) 
        {
            if (flags.is_thread_local) p.error("Duplicate 'tlocal' modifier");
            flags.is_thread_local = true;
        }
        else if (t.kind == TokenKind.INLINE) 
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

	if (is_type(p.current().kind))
	{
		node = parse_var_decl(p, flags)!;
		if (node.is_valid())
		{
			p.ast.top_level_nodes.push((uint)node);
			return;
		}
	}

	if (p.current().kind == TokenKind.IMPORT)
	{
		advance(p)!;
		while (true)
		{
			uint start = p.pos;

			Node? path_node = parse_path(p);
			if (catch err = path_node)
			{
				p.error("failed to parse path for module: %s", err);
				return err~;
			}

			Node attr = parse_attributes(p)!;

			uint[*] data = { (uint)path_node, (uint)attr };
			uint ex = ast::push_extra_block(p.ast, &data);
			Node imp_node = ast::add_node(p.ast, NodeKind.IMPORT_DECL, start, ex);
			p.ast.top_level_nodes.push((uint)imp_node);
			if (!consume(p, TokenKind.COMMA)!) break;
		}
		expect(p, TokenKind.EOS)!;
		return;
	}

    switch (p.current().kind)
    {
		case TokenKind.CONTRACT:
			node = parse_contract(p)!;
			break;
		case TokenKind.INTERFACE:
			node = parse_interface(p)!;
			break;
		case TokenKind.MODULE:
			node = parse_module(p, ws)!;
			break;
		case TokenKind.FN:
			node = parse_fn_decl(p, flags)!;
			break;
		case TokenKind.MACRO:
			node = parse_macro_decl(p)!;
			break;
		case TokenKind.ALIAS:
			node = parse_alias(p)!;
			break;
		case TokenKind.TYPEDEF:
			node = parse_typedef(p)!;
			break;
		case TokenKind.STRUCT:
			node = parse_struct(p)!;
			break;
		case TokenKind.ENUM:
			node = parse_enum(p)!;
			break;
		case TokenKind.CONST:
			flags.is_const = true;
			advance(p)!;
			node = parse_var_decl(p, flags)!;
			break;
		case TokenKind.EOS:
            p.error("<EOS> appeared in parse_top_level");
            advance(p)!;
            return UNEXPECTED_EOS~;
        default:
			p.error("Couldn't find any matching top level declaration: %s", p.current());
    		return UNEXPECTED_TOKEN~;
    }

	if (node.is_valid())
	{
		p.ast.top_level_nodes.push((uint)node);
	}
}