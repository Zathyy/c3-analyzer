module analyzer::parser;

import analyzer::workspace @norecurse;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::maybe;
import analyzer::core;

faultdef
	UNKNOWN, UNEXPECTED_EOS, MODULE_HEADER_FAILED, CONTRACT_NOT_ALLOWED, INVALID_PATH, NOT_A_PATH, PATH_TOO_LONG, EXPECTED_EXPRESSION, UNEXPECTED_TOKEN, EOT
;

struct ParseContext
{
	LineMap* line_map;
	Ast* ast;
	Module* mod;
	SourceFile* sf;
	ModuleSection* section;
	Token[] tokens;
	String file_path; // current file being parsed
	String uri;
	String src;
	Allocator allocator;
	Allocator arena;

	int pos;
	Node* contract;

	// for when using debbugers so i can keep track of what its at
	Token current_token @if(env::DEBUG_SYMBOLS);
	String current_token_string @if(env::DEBUG_SYMBOLS);
	// bool allow_submodules;
}

fn void? ParseContext.skip_until(ParseContext* ctx, TokenKind[] targets)
{
	while (!ctx.eof())
	{
		TokenKind current = ctx.current().kind;

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
		Token t      = ctx.current();
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

fn bool ParseContext.eof(&self) @inline => self.pos >= self.tokens.len || self.current().is_eof();

fn bool ParseContext.is(&self, TokenKind kind)
{
	return self.tokens[self.pos].kind == kind;
}

fn Token? ParseContext.peek(&self, int pos) @inline
{
	if (!self.can_peek(pos)) return io::EOF~;
	return self.tokens[(sz)self.pos + pos];
}

<*
 Checks if there are enough tokens left to look ahead by 'offset' steps.
*>
fn bool ParseContext.can_peek(&self, int offset = 0) @inline
{
	return (sz)self.pos + offset < self.tokens.len;
}

fn void ParseContext.print_current(&self)
{
	plog::debug("%s", self.token_text(self.current()));
}

fn Token ParseContext.current(&self) @inline => self.peek(0)!!;

fn void? reverse(ParseContext* ctx, int position)
{
	ctx.pos = position;
	advance(ctx, 0)!;
}

fn int ParseContext.current_pos(&self)
{
	return self.current().pos;
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
		plog::debug("analyzer::advance() : eof");
		return EOT~;
	}

	ctx.pos += len;

	if (ctx.eof())
	{
		$if env::DEBUG_SYMBOLS:
			ctx.current_token_string = "EOF";
		$endif
		return;
	}

	$if env::DEBUG_SYMBOLS:
		ctx.current_token = ctx.current();
		ctx.current_token_string = ctx.token_text(ctx.current());
	$endif
}

<*
 a macro just so that it logs where it happened
 @param [&inout] ctx
*>
macro @expect_else(ParseContext* ctx, TokenKind kind; @body(err))
{
	if (!ctx.is(kind))
	{
		ctx.error("Expected '%s' got '%s'", kind.description, ctx.current().kind.description);
		$if $feature(PARSER_LIB):
			plog::error("Error happened here");
		$endif
		@body(ctx.ast.missing(ctx.current().pos));

		return ctx.current();
	}
	else
	{
		advance(ctx)!;
		return ctx.peek(-1);
	}
}

<*
 @param [&inout] ctx
*>
macro @expect_some_else(ParseContext* ctx, TokenKind[] kind; @body(err))
{
	foreach (k : kind)
	{
		if (ctx.is(k))
		{
			advance(ctx)!;
			return ctx.peek(-1);
		}
	}

	ctx.error("Expected any of '%s' got '%s'", kind, ctx.current().kind.description);
	$if $feature(PARSER_LIB):
		plog::error("Error happened here");
	$endif
	@body(ctx.ast.missing(ctx.current().pos));
	return ctx.current();
}

<*
 a helper function that expect else skips
 @param [&inout] ctx
*>
macro @expect_else_skip(ParseContext* ctx, TokenKind kind, TokenKind[] targets; @body(err))
{
	return @expect_else(ctx, kind ; err)
	{
		ctx.skip_until(targets)!;
		err.kind = ERROR;
		err.end_token = ctx.current().pos;
		@body(err);
	};
}

<*
 a macro just so that it logs where it happened
 @param [&inout] ctx
*>
macro Token? expect(ParseContext* ctx, TokenKind kind) @maydiscard
{
	if (!ctx.is(kind))
	{
		ctx.error("Expected '%s' got '%s'", kind.description, ctx.current().kind.description);
		$if $feature(PARSER_CLI):
			plog::error("Error happened here");
		$endif
		ctx.ast.missing(ctx.current().pos);
		return ctx.current();
	}
	else
	{
		advance(ctx)!;
		return ctx.peek(-1);
	}
}

<*

*>
macro Node*? unexpected(ParseContext* ctx, String fmt, ...) @maydiscard
{
	ctx.error(fmt, ...$vaarg);
	$if $feature(PARSER_CLI):
		plog::error("Error happened here");
	$endif
	return ctx.ast.missing(ctx.current().pos);
}

macro Node*? unexpected_at(ParseContext* ctx, Token t, String fmt, ...) @maydiscard
{
	ctx.error_at(t, fmt, ...$vaarg);
	$if $feature(PARSER_CLI):
		plog::error("Error happened here");
	$endif
	return ctx.ast.missing(ctx.current().pos);
}

<*
 @param [&inout] ctx
 @param kind : "type to consume"
*>
fn bool? consume(ParseContext* ctx, TokenKind kind)
{
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
	return self.token_text(self.current());
}

fn String peek_module_name(ParseContext* ctx) => @pool()
{
	if (ctx.tokens[0].kind == MODULE || ctx.tokens[0].kind == CONTRACT)
	{
		// Start collecting the name after the 'module' keyword
		String full_name = "";

		sz i = ctx.tokens[0].kind == CONTRACT ? 2 : 1;
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
 DO NOT CALL THIS, only interact via Workspace
 Parse source code at uri

 Appends the nodes to the provided Modules Ast
 @param [&inout] ws
 @require ctx.arena != null
 @require ctx.allocator != null
*>
fn void? parse(Workspace* ws, ParseContext* ctx) => @pool()
{
	Lexer lexer = { .buffer = ctx.src, .index = 0, };
	List{Token} tokens;
	tokens.init(tmem, 1000);
	while (try token = lexer.next())
	{
		tokens.push(token);
		plog::debug("Added token: <%s> - %s", token.kind, ctx.token_text(token));
	}

	tokens.push({ .kind = EOF, .pos = (tokens.last().pos + tokens.last().len) ?? 0, .len = 0 });
	ctx.tokens = tokens.array_view();

	plog::info("parsing uri: %s", ctx.uri);

	String mod_name = peek_module_name(ctx);
	if (mod_name == "")
	{
		mod_name = path_to_module_name(ctx.uri)!;

		Module* mod        = ws.get_or_create_module(mod_name);
		ModuleSection* sec = ws.get_or_create_section(mod, ctx.sf);
		ctx.section = sec;
		ctx.mod = mod;
		plog::info("Inferred module: %s", mod_name);
	}
	else
	{
		mod_name.free(ctx.allocator);
	}

	while (!ctx.eof())
	{
		// sz err_len = lengthof(ctx.ast.error_nodes);
		if (catch err = parse_top_level(ctx, ws))
		{
			if (err == EOT)
			{
				plog::error("End of Token!");
				break;
			}

			int before = ctx.pos;
			synchronize(ctx)!;
			// If synchronize made no progress (stuck on an unhandled keyword),
			// force-advance one token to guarantee the loop terminates.
			if (ctx.pos == before && !ctx.eof())
			{
				advance(ctx)!!;
			}
		}
		// else if (err_len != lengthof(ctx.ast.error_nodes))
		// {
		// 	int before = ctx.pos;
		// 	synchronize(&ctx)!;
		// 	// If synchronize made no progress (stuck on an unhandled keyword),
		// 	// force-advance one token to guarantee the loop terminates.
		// 	if (ctx.pos == before && !ctx.eof())
		// 	{
		// 		advance(&ctx)!!;
		// 	}
		// }
	}

	if (try last_sec = ctx.sf.sections.last())
	{
		last_sec.nodes = ctx.ast.top_level_nodes.array_view();
	}
}

fn String? path_to_module_name(String path)
{
	String base_name = path.file_tbasename()!;
	return base_name.strip_suffix(".c3");
}

fn void? parse_top_level(ParseContext* ctx, Workspace* ws)
{
	plog::debug("parse_top_level: %s", ctx.token_text(ctx.current()));

	Node* node;
	ParseFlags flags = { .is_global = true };

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
		node = parse_var_decl(ctx, null, flags)!;
		ctx.ast.top_level_nodes.push(node);
		return;
	}

	switch (ctx.current().kind)
	{
		case CONTRACT:
			if (ctx.contract)
			{
				ctx.error("There are more than one doc comment in a row, that is not allowed.");
				ctx.ast.error(ctx.current().pos);
			}
			node = parse_contract_decl(ctx)!;
			ctx.contract = node;
		case INTERFACE:
			node = parse_interface_decl(ctx)!;
		case MODULE:
			node = parse_module_decl(ctx, ws)!;
		case IMPORT:
			node = parse_import_decl(ctx)!;
		case FAULTDEF:
			node = parse_faultdef_decl(ctx)!;
		case FN:
			node = parse_fn_decl(ctx, flags)!;
		case MACRO:
			node = parse_macro_decl(ctx, flags)!;
		case ALIAS:
			node = parse_alias_decl(ctx)!;
		case TYPEDEF:
			node = parse_typedef_decl(ctx, flags)!;
		case ATTRDEF:
			node = parse_attrdef_decl(ctx)!;
		case UNION:
		case STRUCT:
			node = parse_struct_union_decl(ctx)!;
		case BITSTRUCT:
			node = parse_bitstruct_decl(ctx)!;
		case CONSTDEF:
			flags.is_constdef = true;
			node = parse_enum_constdef_decl(ctx, flags)!;
		case ENUM:
			node = parse_enum_constdef_decl(ctx, flags)!;
		case CONST:
			flags.is_const = true;
			advance(ctx)!;
			node = parse_var_decl(ctx, null, flags)!;
		case CT_EXPAND:
			node = parse_expand_decl(ctx)!;
		case CT_ASSERT:
			int start_pos = ctx.current().pos;
			Node* stmt = parse_ct_assert_stmt(ctx)!;
			node = ctx.ast.alloc_node(CT_ASSERT_DECL, start_pos);
			node.end_token = ctx.current().pos;
			CtAssertDecl* ctassert = node.as(CT_ASSERT_DECL);
			ctassert.stmt = stmt;
		default:
			ctx.error("Couldn't find any matching top level declaration: %s", string::from_struct(tmem, ctx.current()));
			return UNEXPECTED_TOKEN~;
	}

	ctx.ast.top_level_nodes.push(node);
	if (ctx.contract && node.kind != CONTRACT_DECL)
	{
		attach_contract(ctx, node, ctx.contract);
		ctx.contract = null;
	}
}

<*
 @param [&in] ctx
 @param [&inout] node
 @param [&in] contract
*>
fn void attach_contract(ParseContext* ctx, Node* node, Node* contract)
{
	switch (node.kind)
	{
		case MODULE_DECL:
			ModuleDecl* mod = node.as(MODULE_DECL);
			mod.contract.set(contract);
		case FN_DECL:
			FnDecl* func = node.as(FN_DECL);
			func.contract.set(contract);
		case FAULTDEF_DECL:
			FaultdefDecl* fd = node.as(FAULTDEF_DECL);
			fd.contract.set(contract);
		default:
			break;
	}
}