module parser::parser;

import lexer;
import line_map;

import parser::ast;
import parser::common;
import parser::workspace @norecurse;

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


// Scratch Buffer
tlocal List{Node*} scratch;

fn Node*[] scratch_view(int index, int len)
{
	return scratch.entries[index:len];
}

// defer so it always runs even if the function returns fault
macro @with_scratch(; @body(index))
{
	int watermark = (int)scratch.len();
	defer scratch.size = (sz)watermark;
	@body(watermark);
}

// defer so it always runs even if the function returns fault
macro @scratch(; @body())
{
	sz watermark = scratch.len();
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

struct ParseContext
{
	LineMap* line_map;
	Ast* ast;
	Module* mod;
	SourceFile* sf;
	Token[] tokens;
	String file_path; // current file being parsed
	String src;
	Allocator allocator;
	Allocator arena;

	int pos;
	Node contract;
  	List{ParserError} errors @if($feature(PARSER_LIB));

	// for when using debbugers so i can keep track of what its at
	Token current_token @if(env::DEBUG_SYMBOLS);
	String current_token_string @if(env::DEBUG_SYMBOLS);
	// bool allow_submodules;

}

<*
  Allocates and initializes a strongly typed AST node inside the AST arena.
  @param [&in] ctx : "Pointer to the ParseContext"
  @param kind  : "The NodeKind enum tag (e.g., IMPORT_DECL, VAR_DECL)"
  @param start : "The starting token index/position"
  @require ctx.ast != null
  @require ctx.ast.allocator != null
*>
fn Node* new_node(ParseContext* ctx, NodeKind kind, int start)
{
    Node* node = alloc::new(ctx.ast.allocator, Node);
    
    node.kind = kind;
    node.start_token = start;
    node.end_token = ctx.peek().pos;

	return node;
}

fn void? ParseContext.skip_until(ParseContext* ctx, TokenKind[] targets)
{
    while (!ctx.eof())
    {
        TokenKind current = ctx.peek(0).kind;
        
        foreach (t : targets)
        {
            if (current == t) return;
        }

        if (current == EOS || current == RBRACE) return;

        advance(ctx)!;
    }
}

<*
 synchronize the top level/recover top level
 @param [&inout] ctx
*>
fn void? synchronize(ParseContext* ctx)
{
	int brace_depth = 0;

	while (!ctx.eof())
	{
		Token t = ctx.peek();
		Location loc = ctx.line_map.resolve((sz)t.pos);

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
			advance(ctx)!;
			return;
		}

		advance(ctx)!;
	}
}

fn bool ParseContext.eof(&self) @inline
{
	return self.pos >= self.tokens.len || self.is(EOF);
}

fn bool ParseContext.is(&self, TokenKind kind)
{
	return self.tokens[self.pos].kind == kind;
}

fn Token ParseContext.peek(&self, int pos = 0) @inline
{
	assert ((sz)self.pos + pos < self.tokens.len);
	return self.tokens[(sz)self.pos + pos];
}

fn void ParseContext.print_current(&self)
{
	log::debug("%s", self.token_text(self.peek(0)));
}

fn void? reverse(ParseContext* ctx, int position)
{
	ctx.pos = position;
	advance(ctx, 0)!;
}

fn void? ParseContext.advance(ParseContext* ctx, int len = 1)
{
	return advance(ctx, len)!;
}

<*
 @param [&inout] ctx
*>
fn void? advance(ParseContext* ctx, int len = 1)
{
	if (ctx.eof())
	{
		log::debug("parser::advance() : eof");
		return io::EOF~;
	}

	ctx.pos += len;

	$if env::DEBUG_SYMBOLS:
    if (!ctx.eof()) 
    {
        ctx.current_token = ctx.peek();
        ctx.current_token_string = ctx.token_text(ctx.peek());
    }
    else 
    {
        ctx.current_token_string = "EOF";
    }
    $endif
}

<*
 a macro just so that it logs where it happened
 @param [&inout] ctx
*>
macro void? expect(ParseContext* ctx, TokenKind kind)
{
	if (!ctx.is(kind))
	{
		ctx.error("Expected '%s' got '%s'", kind.description, ctx.current().kind.description);
		log::error("Error happened here");
	}
	else
	{
		advance(ctx)!;
	}
}

<*
 @param [&inout] ctx
 @param kind : "type to consume"
*>
fn bool? consume(ParseContext* ctx, TokenKind kind)
{
	if (ctx.eof()) return io::EOF~;
	if (ctx.is(kind))
	{
		advance(ctx)!;
		return true;
	}

	return false;
}

fn String ParseContext.token_text(ParseContext* self, Token t) @inline
{
	return self.src[t.pos:t.len];
}

fn String ParseContext.current_text(ParseContext* self) @inline
{
	return self.token_text(self.peek(0));
}

fn String peek_module_name(ParseContext* ctx) => @pool()
{
	if (ctx.tokens[0].kind == MODULE)
	{
		// Start collecting the name after the 'module' keyword
		String full_name = "";

		sz i = 1;
		while (i < ctx.tokens.len)
		{
			Token t = ctx.tokens[i];

			if (t.kind == IDENT)
			{
				String part = ctx.token_text(t);
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
		return full_name.copy(ctx.allocator);
	}

	return "";
}

<*
 Parse source code at uri

 Appends the nodes to the provided Modules Ast
 @param [&inout] ws
*>
fn ParseResult? parse(Workspace* ws, String uri, String src)
{
	ParseContext ctx = { .mod = null, .file_path = uri, .allocator = ws.allocator };

	$if $feature(PARSER_LIB):
		ctx.errors.init(ws.allocator);
	$endif

	if (!scratch.is_initialized())
	{
		scratch.init(ws.allocator, 1000);
	}

	scratch.clear();
	defer scratch.free();

	Lexer lexer = { .buffer = src, .index = 0, };
	ctx.src = src;

	List{Token} tokens;
	tokens.init(ctx.allocator, 1000);
	defer tokens.free();
	while (try token = lexer.next())
	{
		tokens.push(token);
		log::debug("Added token: <%s> - %s", token.kind, ctx.token_text(token));
	}

	tokens.push({ .kind = EOF, .pos = (tokens.last().pos + tokens.last().len) ?? 0, .len = 0 });
	ctx.tokens = tokens.array_view();

	SourceFile* sf = ws.reset_source_file(uri);
	sf.source = src;
	ctx.sf = sf;
	ctx.ast = sf.ast;
	ctx.line_map = &sf.line_map;
	ctx.line_map.build(src);

	log::info("parsing uri: %s", uri);

	String mod_name = peek_module_name(&ctx);
	if (mod_name == "")
	{
		mod_name = path_to_module_name(uri)!;

		Module* mod = ws.get_or_create_module(mod_name);
		ModuleSection* sec = ws.get_or_create_section(mod, ctx.sf);
		ctx.mod = mod;
		sec.start_node_idx = 0;
		log::info("Inferred module: %s", mod_name);
	}
	else
	{
		mod_name.free(ctx.allocator);
	}

	bool success = true;
	while (!ctx.eof())
	{
		if (catch err = parse_top_level(&ctx, ws))
		{
			success = false;
			if (err == io::EOF)
			{
				break;
			}

			synchronize(&ctx)!;
			continue;
		}
	}

	log::info("Succesfully parsed: %s", uri);

	$if $feature(PARSER_LIB):
	log::info("Result: %s", ctx.errors.len());
	return {
        .success = success,
		.path = uri,
        .errors = ctx.errors
    };
	$else
	return {
		.path = uri,
        .success = success,
    };
	$endif
}

<*
 Parse a specific file.
 Appends the nodes to the provided Modules Ast
 @param [&inout] ws
*>
fn ParseResult? parse_file(Workspace* ws, String path) => parse(ws, path, (String)file::load(tmem, path)!);

fn String? path_to_module_name(String path)
{
	String base_name = path.file_tbasename()!;
	return base_name.strip_suffix(".c3");
}

fn void? parse_top_level(ParseContext* ctx, Workspace* ws)
{
	log::debug("parse_top_level: %s", ctx.token_text(ctx.peek()));

	Node node;
	ParseFlags flags = { .is_global = true };

	/*

	// the individual parse functions will check that the modifiers are used appropiately
	while (true)
	{
		Token t = ctx.current();

		if (t.kind == EXTERN)
		{
			if (flags.is_extern) ctx.error("Duplicate 'extern' modifier");
			flags.is_extern = true;
		}
		else if (t.kind == TLOCAL)
		{
			if (flags.is_thread_local) ctx.error("Duplicate 'tlocal' modifier");
			flags.is_thread_local = true;
		}
		else if (t.kind == INLINE)
		{
			if (flags.is_inline) ctx.error("Duplicate 'inline' modifier");
			flags.is_inline = true;
		}
		else
		{
			break;
		}

		advance(ctx)!;
	}

	if (is_type(ctx))
	{
		node = parse_var_decl(ctx, flags)!;
		if (node.is_valid())
		{
			ctx.ast.top_level_nodes.push((uint)node);
			return;
		}
	}

	if (ctx.current().kind == IMPORT)
	{
		advance(ctx)!;
		while (true)
		{
			uint start = ctx.current_pos();

			Node? path_node = parse_path(ctx);
			if (catch err = path_node)
			{
				ctx.error("failed to parse path for module: %s", err);
				return err~;
			}

			Node attr = parse_attributes(ctx)!;

			uint[*] data = views::@data{ImportViewFields}
			(
				PATH, path_node,
				ATTRIBUTES, attr,
			);

			uint ex = ctx.ast.push_extra_block(&data);
			Node imp_node = ctx.ast.add_node(IMPORT_DECL, start, ctx.current_pos(), ex);
			ctx.ast.top_level_nodes.push((uint)imp_node);
			if (!consume(ctx, COMMA)!) break;
		}
		expect(ctx, EOS)!;
		return;
	}

	switch (ctx.current().kind)
	{
		case CONTRACT:
			node = parse_contract(ctx)!;
			ctx.contract = node;
		case INTERFACE:
			node = parse_interface(ctx)!;
		case MODULE:
			node = parse_module(ctx, ws)!;
		case FAULTDEF:
			node = parse_faultdef_decl(ctx)!;
		case FN:
			node = parse_fn_decl(ctx, flags)!;
		case MACRO:
			node = parse_macro_decl(ctx)!;
		case ALIAS:
			node = parse_alias(ctx)!;
		case TYPEDEF:
			node = parse_typedef(ctx)!;
		case ATTRDEF:
			node = parse_attrdef(ctx)!;
		case UNION:
		case STRUCT:
			node = parse_struct(ctx)!;
		case BITSTRUCT:
			node = parse_bitstruct_decl(ctx)!;
		case CONSTDEF:
			flags.is_constdef = true;
			node = parse_enum(ctx, flags)!;
		case ENUM:
			node = parse_enum(ctx, flags)!;
		case CONST:
			flags.is_const = true;
			advance(ctx)!;
			node = parse_var_decl(ctx, flags)!;
		case CT_EXPAND:
			node = parse_expand_decl(ctx)!;
		case CT_ASSERT:
			uint start_pos = ctx.current_pos();
			Node stmt = parse_ct_assert(ctx)!;
			node = ctx.ast.add_node(CT_ASSERT_DECL, start_pos, ctx.current_pos(), (uint)stmt);
		case EOS:
			ctx.error("<EOS> appeared in parse_top_level");
			advance(ctx)!;
			return UNEXPECTED_EOS~;
		default:
			ctx.error("Couldn't find any matching top level declaration: %s", string::from_struct(tmem, ctx.current()));
			return UNEXPECTED_TOKEN~;
	}

	// if (node.is_valid())
	// {
	ctx.ast.top_level_nodes.push((uint)node);

	if (ctx.contract.is_valid())
	{
		attach_contract(ctx, node, ctx.contract);
	}

	ctx.contract = {};
	// }

	*/
}
