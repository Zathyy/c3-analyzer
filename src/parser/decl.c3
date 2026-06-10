module parser::parser;
import parser::ast;
import lexer;
import parser::plog;

import parser::constants;
import std::collections::list;
import parser::workspace @norecurse;
import std::io;

<*
 module_decl ::= module path_expr ';' attributes?
*>
fn Node*? parse_module_decl(ParseContext* ctx, Workspace* ws)
{
	int start_pos = ctx.peek(0).pos;
	expect(ctx, MODULE)!;
	plog::debug("parse_mod");
	Node* node           = ctx.ast.alloc_node(MODULE_DECL, start_pos);
	ModuleDecl* mod_decl = node.as(MODULE_DECL);
	defer node.end_token = ctx.peek(0).pos;

	mod_decl.path = parse_path_expr(ctx)!;
	mod_decl.generics = parse_generic_decl(ctx)!;

	if (ctx.is(AT_IDENT))
	{
		mod_decl.attributes = parse_attributes(ctx, node)!;
	}

	expect(ctx, EOS)!;

	PathExpr* path  = mod_decl.path.as(PATH_EXPR);
	String mod_name = path.full_path(&ctx.ast.string_pool, ctx.allocator)!;
	defer mod_name.free(ctx.allocator);
	Module* mod        = ws.get_or_create_module(mod_name);
	ModuleSection* sec = ws.get_or_create_section(mod, ctx.sf);
	ctx.mod = mod;

	return node;
}

<*

*>
fn Node*? parse_contract_decl(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	if (!ctx.is(CONTRACT))
	{
		ctx.error("Expected contract here");
		return ctx.ast.error(start_pos);
	}
	Token contract_token = ctx.current();
	if (contract_token.len <= 4)
	{
		advance(ctx)!;
		return ctx.ast.missing(contract_token.pos);
	}
	int global_offset = contract_token.pos;
	String slice      = ctx.token_text(contract_token);
	advance(ctx)!; // skip over contract

	// store the "normal" tokens and index temporarly since
	// we need to swap them
	Token[] main_tokens = ctx.tokens;
	int main_index      = ctx.pos;
	defer
	{
		ctx.tokens = main_tokens;
		ctx.pos = main_index;
	}

	List{Token} contract_tokens;
	contract_tokens.tinit();
	ContractLexer cl;
	cl.init(slice);

	// calculate the offset for 'ContractLexer' contract[2:^4];
	int open_marker_len = 2;
	int total_inner_len = slice.len - 4;
	int first_at_index  = total_inner_len - cl.lexer.buffer.len;
	int offset          = contract_token.pos + open_marker_len + first_at_index;

	while (try next = cl.next())
	{
		// make return a identifier so the it can be parsed as expr
		if (next.kind == RETURN)
		{
			next.kind = IDENT;
		}

		next.pos += offset;
		contract_tokens.push(next);

		plog::debug("ContractLexer - added: %s", next.kind);
	}
	contract_tokens.push({ .kind = EOF, .pos = (contract_tokens.last()
		.pos + contract_tokens.last().len) ?? 0, .len = 0 });

	ctx.tokens = contract_tokens.array_view();
	ctx.pos = 0;

	Node* node             = ctx.ast.alloc_node(CONTRACT_DECL, ctx.current().pos);
	ContractDecl* contract = node.as(CONTRACT_DECL);
	plog::debug("comment : %s", cl.description);
	contract.comment = ctx.ast.string_pool.internalize(cl.description);

	List{Node*} ensures;
	ensures.tinit();
	List{Node*} requires;
	requires.tinit();
	List{Node*} params;
	params.tinit();
	List{Node*} returns;
	returns.tinit();

	while (!ctx.eof())
	{
		String attr = ctx.token_text(ctx.current());
		plog::debug("parse_contract - attribute = %s", attr);

		if (consume(ctx, AT_IDENT)!)
		{
			if (attr == constants::KW_AT_REQUIRE)
			{
				plog::debug("parse_contract_decl - @require");
				requires.push(parse_contract_expr(ctx)!);
			}
			else if (attr == constants::KW_AT_ENSURE)
			{
				plog::debug("parse_contract_decl - @ensure");
				ensures.push(parse_contract_expr(ctx)!);
			}
			else if (attr == constants::KW_AT_PARAM)
			{
				params.push(parse_contract_param(ctx))!;
			}
			else if (attr == constants::KW_AT_DEPRECATED)
			{
				plog::debug("parse_contract_decl - @deprecated");
				Node* n = ctx.ast.alloc_node(ATTRIBUTE_DECL, ctx.current().pos);
				contract.deprecated = n;
				AttributeDecl* attribute = n.as(ATTRIBUTE_DECL);
				attribute.path.set(ctx.ast.alloc_node(MISSING, ctx.current().pos));
				attribute.name = constants::KW_AT_DEPRECATED;
				attribute.kind = DEPRECATED;
				if (ctx.can_peek(1) && ctx.peek(0).kind == EOS && ctx.peek(1).kind == STRING_LITERAL)
				{
					advance(ctx)!;
				}
				int start = ctx.peek(0).pos;
				if (ctx.is(STRING_LITERAL))
				{
					List{Node*} exprs;
					exprs.tinit(1);
					exprs.push(parse_expr(ctx)!);
					plog::debug("parser @deprecated string");
					attribute.exprs = alloc::clone_slice(ctx.arena, exprs.array_view());
				}
			}
			else if (attr == constants::KW_AT_PURE)
			{
				contract.is_pure = true;
			}
			else if (attr == constants::KW_AT_RETURN)
			{
				if (ctx.is(QUESTION))
				{
					advance(ctx)!;
					while (!ctx.eof())
					{
						returns.push(parse_expr(ctx)!);
						if (!consume(ctx, COMMA)!)
						{
							break;
						}
					}
				}
				else
				{
					contract.return_desc = parse_expr(ctx)!;
				}
			}
			else
			{
				if (catch advance(ctx)) break;
			}
		}
		else
		{
			if (catch advance(ctx)) break;
		}
	}

	contract.ensures = alloc::clone_slice(ctx.arena, ensures.array_view());
	contract.requires = alloc::clone_slice(ctx.arena, requires.array_view());
	contract.params = alloc::clone_slice(ctx.arena, params.array_view());
	contract.returns = alloc::clone_slice(ctx.arena, returns.array_view());

	return node;
}

<*
 import_decl ::= import path_expr (',' path_expr)* ';' attributes?
*>
fn Node*? parse_import_decl(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	expect(ctx, IMPORT)!;
	Node* node      = ctx.ast.alloc_node(IMPORT_DECL, start_pos);
	ImportDecl* imp = node.as(IMPORT_DECL);
	defer node.end_token = ctx.peek(0).pos;

	List{Node*} temp_paths;
	temp_paths.init(tmem, 4);

	while (true)
	{
		Node* path_node = parse_path_expr(ctx)!;
		temp_paths.push(path_node);

		if (!consume(ctx, COMMA)!) break;
		if (ctx.is(EOS))
		{
			temp_paths.push(unexpected(ctx, "Expected an import path after ','")!);
			break;
		}
	}

	imp.paths = alloc::clone_slice(ctx.arena, temp_paths.array_view());

	if (ctx.is(AT_IDENT))
	{
		imp.attributes = parse_attributes(ctx, node)!;
	}

	expect(ctx, EOS)!;

	return node;
}

<*
 Parse the generic parameter list after an alias name.
 @param [&inout] ctx : "Parser context to consume tokens from."
*>
fn StringID[]? parse_alias_generic_decl(ParseContext* ctx) => @pool()
{
	List{StringID} temp_params;
	temp_params.init(tmem, 4);

	expect(ctx, LESS)!;

	while (!ctx.eof() && !ctx.is(GREATER))
	{
		Token t = ctx.peek(0);
		if (t.kind != TYPE_IDENT && t.kind != CONST_IDENT)
		{
			ctx.error("Expected generic alias parameter name");
		}
		else
		{
			temp_params.push(ctx.ast.string_pool.internalize(ctx.token_text(t)));
		}

		advance(ctx)!;
		if (ctx.is(GREATER)) break;
		if (!consume(ctx, COMMA)!)
		{
			ctx.error("Expected ',' or '>' in alias generic parameter list");
		}
	}
	expect(ctx, GREATER)!;
	return alloc::clone_slice(ctx.arena, temp_params.array_view());
}

fn void? skip_alias_attributes(ParseContext* ctx)
{
	while (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT) || ctx.is(AT_CONST_IDENT))
	{
		advance(ctx)!;
		if (ctx.is(LPAREN))
		{
			skip_balanced_group(ctx, LPAREN, RPAREN)!;
		}
	}
}

<*
 alias_type_decl ::= 'alias' TYPE_IDENT generic_decl? attributes? '=' type_expr ';'
 module_alias_decl ::= 'alias' IDENT attributes? '=' 'module' module_path ';'
 alias_decl ::= 'alias' alias_name generic_decl? attributes? '=' alias_source ';'

 Alias names are classified by lexer token kind. A TYPE_IDENT name parses a
 type-expression target, `module` after '=' parses a module path target, and
 identifier-style aliases require the target path's final token kind to match
 the alias name kind. Alias attributes are skipped here until attribute parsing
 is represented on AliasDecl.
 @param [&inout] ctx : "Parser context positioned at the alias keyword."
*>
fn Node*? parse_alias_decl(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;
	expect(ctx, ALIAS)!;
	Node* node            = ctx.ast.alloc_node(ALIAS_DECL, start_pos);
	AliasDecl* alias_decl = node.as(ALIAS_DECL);
	defer node.end_token = ctx.peek(0).pos;

	do CHECK_NAME:
	{
		Token t = @expect_some_else(ctx, { TYPE_IDENT, IDENT, CONST_IDENT, AT_IDENT } ; err)
		{
			ctx.error("Expected alias name identifier");
			alias_decl.name = ast::EMPTY_STR;
			break CHECK_NAME;
		}!;

		alias_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		alias_decl.name_kind = t.kind;
	};

	if (ctx.is(LESS))
	{
		alias_decl.generic_params = parse_alias_generic_decl(ctx)!;
	}

	skip_alias_attributes(ctx)!;

	expect(ctx, EQ)!;

	if (ctx.is(MODULE))
	{
		alias_decl.alias_kind = MODULE_ALIAS;
		advance(ctx)!;
		alias_decl.target = parse_path_expr(ctx)!;
	}
	else if (alias_decl.name_kind == TYPE_IDENT)
	{
		alias_decl.alias_kind = TYPE_ALIAS;
		alias_decl.target = parse_alias_type_target(ctx)!;
	}
	else
	{
		alias_decl.alias_kind = IDENT_ALIAS;
		alias_decl.target = parse_expr(ctx)!;
		if (ctx.is(LBRACE))
		{
			// TODO: represent generic target arguments for identifier aliases.
			skip_balanced_group(ctx, LBRACE, RBRACE)!;
		}
	}
	expect(ctx, EOS)!;
	return node;
}

<*
 typedef_decl ::= 'typedef' TYPE_IDENT interface_list? attributes? '=' 'inline'? type_expr attributes? ';'

 Typedef declarations create distinct types. Function pointer syntax is
 alias-only in C3, so a typedef base beginning with `fn` is consumed only for
 recovery and an ERROR node is returned.
 @param [&inout] ctx : "Parser context positioned at the typedef keyword."
 @param flags : "Top-level modifiers consumed before the typedef keyword."
*>
fn Node*? parse_typedef_decl(ParseContext* ctx, ParseFlags flags = { })
{
	int start_pos = ctx.peek(0).pos;
	expect(ctx, TYPEDEF)!;
	Node* node                = ctx.ast.alloc_node(TYPEDEF_DECL, start_pos);
	TypedefDecl* typedef_decl = node.as(TYPEDEF_DECL);
	defer node.end_token = ctx.peek(0).pos;

	if (flags.is_inline)
	{
		ctx.error("'inline' must appear after '=' in typedef declarations");
		node.kind = MISSING;
	}

	Token name = ctx.peek(0);
	if (name.kind != TYPE_IDENT)
	{
		ctx.error("Expected typedef type name");
		node.kind = MISSING;
		if (!ctx.is(EOS) && !ctx.eof())
		{
			advance(ctx)!;
		}
	}
	else
	{
		typedef_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(name));
		advance(ctx)!;
	}

	typedef_decl.interfaces = parse_interface_type_list(ctx)!;
	foreach (interface_type : typedef_decl.interfaces)
	{
		if (is_error_or_missing_node(interface_type))
		{
			node.kind = MISSING;
		}
	}

	List{Node*} attributes;
	attributes.init(tmem, 4);
	parse_attributes_into(ctx, node, &attributes)!;

	expect(ctx, EQ)!;

	if (consume(ctx, INLINE)!)
	{
		typedef_decl.is_inline = true;
	}

	if (ctx.is(FN))
	{
		unexpected(ctx, "Cannot define a new function type")!;
	}
	else
	{
		typedef_decl.base_type = parse_type_expr(ctx)!;
	}

	parse_attributes_into(ctx, node, &attributes)!;
	typedef_decl.attributes = alloc::clone_slice(ctx.arena, attributes.array_view());
	expect(ctx, EOS)!;
	return node;
}

<*
 fn_decl ::= fn type_expr (type_expr '.')? ident '(' parameter_list? ')' attributes?
 fn_body ::= ('=>' short_body) | compound_stmt
*>
fn Node*? parse_fn_decl(ParseContext* ctx, ParseFlags flags = { })
{
	int start_pos = ctx.peek(0).pos;

	expect(ctx, FN)!;

	plog::debug("parse_fn");

	Node* node   = ctx.ast.alloc_node(FN_DECL, start_pos);
	FnDecl* func = node.as(FN_DECL);
	defer node.end_token = ctx.peek(0).pos;

	func.ret_type = parse_type_expr(ctx)!;

	if IS_TYPE: (is_type(ctx))
	{
		if (flags.is_interface)
		{
			unexpected(ctx, "Interfaces cant be methods");
			advance(ctx)!;
			break IS_TYPE;
		}

		func.associated_type.set(parse_type_expr(ctx)!);

		expect(ctx, DOT)!;

		Token t = @expect_else_skip(ctx, IDENT, { EOS, LPAREN } ; err)
		{
			ctx.error("Expected member function name identifier");
			func.name = ast::EMPTY_STR;
			break IS_TYPE;
		}!;
		func.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}
	else
	{
		// Standalone Function: No associated type prefix
		Token t = @expect_else_skip(ctx, IDENT, { EOS, LPAREN } ; err)
		{
			ctx.error("Expected function name identifier");
			func.name = ast::EMPTY_STR;
			break IS_TYPE;
		}!;
		func.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	func.params = parse_parameter_list(ctx)!;

	if (ctx.is(AT_IDENT))
	{
		func.attributes = parse_attributes(ctx, node)!;
	}

	if (ctx.is(LBRACE))
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have a structural block body");
			return ctx.ast.error(start_pos);
		}

		if (flags.is_interface)
		{
			ctx.error("Interface methods cannot have a body");
			return ctx.ast.error(start_pos);
		}

		func.body = parse_compound_stmt(ctx)!;
	}
	else if (consume(ctx, IMPLIES)!)
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have an expression body");
			return ctx.ast.error(start_pos);
		}

		func.body = parse_expr(ctx)!;

		// Clean statement ending validation
		if (!node_ends_with_block(ctx, func.body))
		{
			expect(ctx, EOS)!;
		}
	}
	else
	{
		// No body provided
		expect(ctx, EOS)!;
	}

	return node;
}

<*
 macro_decl ::= macro type_expr? (type_expr '.')? ident '(' parameter_list? ')' attributes?
 fn_body ::= ('=>' short_body) | compound_stmt
*>
fn Node*? parse_macro_decl(ParseContext* ctx, ParseFlags flags = { })
{
	int start_pos = ctx.peek(0).pos;

	expect(ctx, MACRO)!;

	plog::debug("parse_macro");

	Node* node     = ctx.ast.alloc_node(MACRO_DECL, start_pos);
	MacroDecl* mac = node.as(MACRO_DECL);
	defer node.end_token = ctx.peek(0).pos;

	if (is_type(ctx) && ctx.peek(1).kind != DOT)
	{
		mac.ret_type.set(parse_type_expr(ctx)!);
	}

	if IS_TYPE: (is_type(ctx))
	{
		mac.associated_type.set(parse_type_expr(ctx)!);

		expect(ctx, DOT)!;

		Token t;
		if (ctx.is(AT_IDENT))
		{
			t = ctx.peek(0);
			advance(ctx)!;
		}
		else
		{
			t = @expect_else_skip(ctx, IDENT, { EOS, LPAREN } ; err)
			{
				ctx.error("Expected member function name identifier");
				mac.name = ast::EMPTY_STR;
				break IS_TYPE;
			}!;
		}

		mac.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}
	else
	{
		// Standalone Function: No associated type prefix
		Token t = @expect_some_else(ctx, { AT_IDENT, IDENT } ; err)
		{
			ctx.error("Expected member function name identifier");
			mac.name = ast::EMPTY_STR;
			break IS_TYPE;
		}!;
		mac.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	mac.params = parse_parameter_list(ctx)!;

	if (ctx.is(AT_IDENT))
	{
		mac.attributes = parse_attributes(ctx, node)!;
	}

	if (ctx.is(LBRACE))
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have a structural block body");
			return ctx.ast.error(start_pos);
		}
		mac.body = parse_compound_stmt(ctx)!;
	}
	else if (consume(ctx, IMPLIES)!)
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have an expression body");
			return ctx.ast.error(start_pos);
		}

		mac.body = parse_expr(ctx)!;

		// Clean statement ending validation
		if (!node_ends_with_block(ctx, mac.body))
		{
			expect(ctx, EOS)!;
		}
	}
	else
	{
		// No body provided
		expect(ctx, EOS)!;
	}

	return node;
}

<*
 parameter_decl ::= parameter (("=" "...") | ("=" expression))?
 parameter      ::= type_expr ("..."? IDENTIFIER attributes?
					| "..."? CT_IDENT
					| (HASH_IDENT | "&" IDENTIFIER) attributes?
					| attributes?)
					| "..."
					| HASH_IDENT attributes?
					| "&" IDENTIFIER attributes?
					| IDENTIFIER "..."? attributes?
					| CT_IDENT
					| CT_IDENT "..."
 @param [&inout] ctx
*>
fn Node*? parse_param_decl(ParseContext* ctx, ParamParseFlags flags)
{
	int start_pos = ctx.peek(0).pos;

	Node* node     = ctx.ast.alloc_node(VAR_DECL, start_pos);
	VarDecl* param = node.as(VAR_DECL);
	defer node.end_token = ctx.peek(0).pos;

	if (consume(ctx, ELLIPSIS)!)
	{
		param.kind = VAR_PARAM;
		param.flags.is_variadic = true;
		param.type = ctx.ast.alloc_node(MISSING, start_pos);
		return node;
	}

	bool is_ref                  = consume(ctx, AMP)!;
	Node* parsed_type            = null;
	bool has_ellipsis_after_type = false;

	if (!is_ref && check_if_typed_parameter(ctx))
	{
		parsed_type = parse_type_expr(ctx)!;
		if (parsed_type.kind == ERROR) return parsed_type;
		if (parsed_type.as(TYPE_EXPR).optional)
		{
			ctx.error("Parameters may not be optional");
			return ctx.ast.error(start_pos);
		}

		if (consume(ctx, ELLIPSIS)!)
		{
			has_ellipsis_after_type = true;
			param.flags.is_variadic = true;
		}
	}

	param.type = parsed_type;

	Token t = ctx.peek(0);
	switch (t.kind)
	{
		case CT_CONST_IDENT:
			ctx.error("Parameter names may not be all uppercase.");
			ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
			return ctx.ast.error(start_pos);
		case CT_IDENT:
			param.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
			param.kind = VAR_PARAM_CT;
			advance(ctx)!;
			if (consume(ctx, ELLIPSIS)!)
			{
				ctx.error("Untyped constant vaargs are not supported.");
				ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
				return ctx.ast.error(start_pos);
			}
			break;
		case IDENT:
			String token_text = ctx.current_text();
			param.name = ctx.ast.string_pool.internalize(token_text);
			param.kind = VAR_PARAM;
			param.flags.is_ref = is_ref;
			advance(ctx)!;

			if (token_text == "self")
			{
				param.flags.is_self = true;
				param.flags.is_self_by_ref = is_ref;
			}

			if (consume(ctx, ELLIPSIS)!)
			{
				if (has_ellipsis_after_type)
				{
					ctx.error("Duplicate '...' variadic marker encountered.");
					ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
					return ctx.ast.error(start_pos);
				}
				if (parsed_type)
				{
					ctx.error("For typed variadic parameters, '...' must follow the type expression, not the name.");
					ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
					return ctx.ast.error(start_pos);
				}
				param.flags.is_variadic = true;
				param.type = alloc_any_type_expr(ctx);
			}
			break;
		case HASH_IDENT:
			if (is_ref || has_ellipsis_after_type)
			{
				ctx.error("Expression and Type parameters cannot be variadic or references.");
				ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
				return ctx.ast.error(start_pos);
			}
			param.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
			param.kind = VAR_PARAM_EXPR;
			advance(ctx)!;
			break;
		case CT_TYPE_IDENT:
			if (is_ref || has_ellipsis_after_type)
			{
				ctx.error("Expression and Type parameters cannot be variadic or references.");
				ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
				return ctx.ast.error(start_pos);
			}
			param.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
			param.kind = (parsed_type && parsed_type.kind != MISSING) ? VAR_PARAM : VAR_PARAM_CT_TYPE;
			advance(ctx)!;
			break;
		case COMMA:
		case RPAREN:
			if (parsed_type == null)
			{
				ctx.error("Expected a parameter name or type specification.");
				ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
				return ctx.ast.error(start_pos);
			}
			param.name = ast::EMPTY_STR;
			param.kind = VAR_PARAM;
			break;

		default:
			ctx.error("Expected a valid parameter definition.");
			ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
			return ctx.ast.error(start_pos);
	}

	if (ctx.is(AT_IDENT))
	{
		param.attributes = parse_attributes(ctx, node)!;
	}

	if (consume(ctx, EQ)!)
	{
		if (consume(ctx, ELLIPSIS)!)
		{
			param.flags.is_macro_optional_ellipsis = true;
		}
		else
		{
			param.init_expr = parse_expr(ctx)!;
		}
	}

	return node;
}

<*
 var_decl ::= ('var' | type_expr) decl_element (',' decl_element)* ';'
*>
fn Node*? parse_var_decl(ParseContext* ctx, Node* type = null, ParseFlags flags = { })
{
	int start_pos = ctx.peek(0).pos;

	Node* contract;
	if (ctx.is(CONTRACT))
	{
		contract = parse_contract_decl(ctx)!;
	}

	if (flags.is_local)
	{
		if (flags.is_extern)
		{
			unexpected(ctx, "A local variable cannot have an 'extern' modifier");
			advance(ctx)!;
			return ctx.ast.alloc_node(ERROR, start_pos);
		}
		if (flags.is_inline)
		{
			unexpected(ctx, "A local variable cannot be 'inline'");
		}
	}

	Node* type_node = type;

	if (!type_node)
	{
		if (flags.is_var)
		{
			advance(ctx)!; // Consume 'var'
			flags.is_comptime = true;
		}
		else if (is_type_primitive(ctx.peek(0).kind) || ctx.is(IDENT) || ctx.is(TYPE_IDENT))
		{
			type_node = parse_type_expr(ctx, flags)!;
			if (type_node.kind == ERROR) return type_node;
		}
		else if (!flags.is_const)
		{
			unexpected(ctx, "Expected a valid type signature or 'var'");
		}
	}

	Node* head_node;
	Node* tail_node;

	while (true)
	{
		Token t = ctx.peek(0);

		if (flags.is_const && t.kind != CONST_IDENT)
		{
			unexpected(ctx, "Constants must use an uppercase CONST_IDENT, found '%s'", ctx.token_text(t));
		}
		if (!flags.is_const && t.kind != IDENT && !flags.is_local)
		{
			unexpected(ctx, "Global variables must use lower-case IDENT, found '%s'", ctx.token_text(t));
		}
		if (t.kind != IDENT && t.kind != CONST_IDENT && !flags.is_comptime)
		{
			unexpected(ctx, "Expected a variable name identifier, got '%s'", ctx.token_text(t));
		}
		if (t.kind != CT_IDENT && flags.is_comptime)
		{
			unexpected(ctx, "name must be a $ident")!;
		}

		StringID name_id = ctx.ast.string_pool.internalize(ctx.token_text(t));
		advance(ctx)!;

		Node* var_node    = ctx.ast.alloc_node(VAR_DECL, t.pos);
		VarDecl* var_decl = var_node.as(VAR_DECL);

		if (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
		{
			var_decl.attributes = parse_attributes(ctx, var_node, { .allow_type_ident = true })!;
		}

		Node* init_expr = null;

		if EQ_LABEL: (ctx.is(EQ))
		{
			advance(ctx)!;

			if (head_node != null)
			{
				unexpected(ctx, "Initializers are not allowed on multi decleration");
			}
			if (flags.is_extern)
			{
				unexpected(ctx, "An extern declaration cannot contain an initial value assignment expression");
			}
			if (flags.is_struct)
			{
				unexpected(ctx, "Fields cannot have an initializer");
			}

			init_expr = parse_expr(ctx)!;
			if (init_expr.kind == ERROR) return init_expr;
		}
		else if (flags.is_const && !flags.is_extern)
		{
			unexpected(ctx, "Constants must be initialized at their declaration site")!;
		}

		var_decl.name = name_id;
		var_decl.type = type_node; // Reused across the entire chain segment
		var_decl.init_expr = init_expr;
		var_decl.next = null; // Starts as terminal component

		var_decl.flags.is_extern = flags.is_extern;
		var_decl.flags.is_const = flags.is_const;
		var_decl.flags.is_inline = flags.is_inline;
		var_decl.flags.is_local = flags.is_local;
		var_decl.flags.is_thread_local = flags.is_thread_local;
		var_decl.flags.is_static = flags.is_static;

		if (flags.is_local)
		{
			var_decl.kind = VAR_LOCAL;
		}
		else if (flags.is_struct)
		{
			var_decl.kind = VAR_FIELD;
		}
		else
		{
			var_decl.kind = VAR_GLOBAL;
		}

		var_node.end_token = ctx.peek(0).pos;

		if (head_node == null)
		{
			head_node = var_node;
			if (contract)
			{
				head_node.as(VAR_DECL).contract.set(contract);
			}
		}
		else
		{
			tail_node.as(VAR_DECL).next = var_node;
		}
		tail_node = var_node;

		if (flags.is_expr) break;
		if (!consume(ctx, COMMA)!) break;
	}

	if (!flags.skip_eos)
	{
		if (!consume(ctx, EOS)!)
		{
			ctx.error("Expected ';' to terminate variable declaration sequence");
			return ctx.ast.alloc_node(ERROR, ctx.peek(0).pos);
		}
	}

	return head_node;
}

<*
 attributes ::= attribute attribute*
  attribute  ::= AT_IDENT ("(" expression_list? ")")?
 @param [&inout] ctx
*>
fn NodeArray? parse_attributes(ParseContext* ctx, Node* parent_node, AttributeParseFlags flags = { }) => @pool()
{
	List{Node*} nodes;
	nodes.init(tmem, 4);

	while (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
	{
		if (ctx.is(AT_TYPE_IDENT) && !flags.allow_type_ident)
		{
			unexpected(ctx, "Tried parsing a @TypeIdent when not allowed")!;
		}

		Token t = ctx.peek(0);
		advance(ctx)!;

		Node* attr_node = ctx.ast.alloc_node(ATTRIBUTE_DECL, t.pos);
		defer attr_node.end_token = ctx.peek(0).pos;
		AttributeDecl* attr = attr_node.as(ATTRIBUTE_DECL);
		String text         = ctx.token_text(t);
		attr.name = text.copy(&ctx.ast.arena);
		attr.kind = parser::get_attribute_from_string(text);

		if (parent_node && attr.kind == AttributeKind.PRIVATE)
		{
			parent_node.visibility = Visibility.PRIVATE;
		}

		if (consume(ctx, LPAREN)!)
		{
			List{Node*} exprs;
			exprs.init(tmem, 4);
			while (!ctx.is(RPAREN) && !ctx.eof())
			{
				exprs.push(parse_expr(ctx)!);
				if (!consume(ctx, COMMA)!) break;
			}
			expect(ctx, RPAREN)!;
			attr.exprs = alloc::clone_slice(&ctx.ast.arena, exprs.array_view());
		}

		nodes.push(attr_node);

		if (flags.use_comma)
		{
			consume(ctx, COMMA)!;
		}
	}

	if (parent_node) parent_node.flags.has_attributes = nodes.len() > 0;

	return alloc::clone_slice(&ctx.ast.arena, nodes.array_view());
}

<*
 ct_expand_decl ::= $expand '(' expr ')' attributes? ';'
*>
fn Node*? parse_expand_decl(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;
	expect(ctx, CT_EXPAND)!;
	Node* node           = ctx.ast.alloc_node(CT_EXPAND_DECL, start_pos);
	CtExpandDecl* expand = node.as(CT_EXPAND_DECL);
	defer node.end_token = ctx.peek(0).pos;
	expect(ctx, LPAREN)!;
	expand.expr = parse_constant_expr(ctx)!;
	expect(ctx, RPAREN)!;
	if (ctx.is(AT_IDENT))
	{
		expand.attributes = parse_attributes(ctx, node)!;
	}
	expect(ctx, EOS)!;
	return node;
}

<*
 struct_decl ::= "struct | union" TYPE_IDENT ("(" type ("," type)* ")")? attributes? "{" struct_body "}"
*>
fn Node*? parse_struct_union_decl(ParseContext* ctx) => @pool()
{
	int start_pos  = ctx.peek(0).pos;
	bool is_struct = ctx.is(STRUCT);
	if (is_struct)
	{
		expect(ctx, STRUCT)!;
	}
	else
	{
		expect(ctx, UNION)!;
	}
	Node* node              = ctx.ast.alloc_node(STRUCT_DECL, start_pos);
	StructDecl* struct_decl = node.as(STRUCT_DECL);
	struct_decl.is_union = !is_struct;
	defer node.end_token = ctx.peek(0).pos;

	@expect_some_else(ctx, { IDENT, TYPE_IDENT } ; err)
	{
		ctx.error("Structs must have a 'Type identifier' or a 'ident' if a sub struct");
		struct_decl.name = ast::EMPTY_STR;
	}!;

	struct_decl.interfaces = parse_interface_type_list(ctx)!;
	struct_decl.generics = parse_generic_decl(ctx)!;
	struct_decl.attributes = parse_attributes(ctx, node, { .allow_type_ident = true })!;

	@expect_else_skip(ctx, LBRACE, { RBRACE } ; brace_err)
	{
		return brace_err;
	}!;

	List{Node*} fields;
	fields.tinit();

	Node* tail_node = node;

	while (!ctx.is(RBRACE) && !ctx.is(EOF))
	{
		if (ctx.is(STRUCT) || ctx.is(UNION) || ctx.is(BITSTRUCT))
		{
			Node* sub_decl;

			if (ctx.is(BITSTRUCT))
			{
				sub_decl = parse_bitstruct_decl(ctx, true)!;
			}
			else
			{
				sub_decl = parse_struct_union_decl(ctx)!;
			}

			if (sub_decl && sub_decl.kind != ERROR)
			{
				tail_node.as(STRUCT_DECL).next = sub_decl;
				// Unroll the sub-decl chain if it has multiple items to find the true new tail
				while (tail_node.as(STRUCT_DECL).next != null)
				{
					tail_node = tail_node.as(STRUCT_DECL).next;
				}
			}
		}
		else
		{
			ParseFlags flags;
			flags.is_struct = true;
			flags.is_inline = consume(ctx, INLINE)!;
			Node* field = parse_var_decl(ctx, null, flags)!;
			fields.push(field);
		}
	}

	expect(ctx, RBRACE)!;

	struct_decl.fields = alloc::clone_slice(ctx.arena, fields.array_view());
	return node;
}

<*
 bitstruct_decl ::= "bitstruct" TYPE_IDENT ("(" type ("," type)* ")")? ":" type attributes? "{" bitstruct_body "}"
*>
fn Node*? parse_bitstruct_decl(ParseContext* ctx, bool is_nested = false) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	expect(ctx, BITSTRUCT)!;
	Node* node              = ctx.ast.alloc_node(STRUCT_DECL, start_pos);
	StructDecl* struct_decl = node.as(STRUCT_DECL);
	defer node.end_token = ctx.peek(0).pos;

	if COND: (true)
	{
		Token t = @expect_some_else(ctx, { IDENT, TYPE_IDENT } ; err)
		{
			ctx.error("Bitstructs must have a name identifier");
			struct_decl.name = ast::EMPTY_STR;
			break COND;
		}!;

		struct_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	struct_decl.interfaces = parse_interface_type_list(ctx, { .no_generics = true })!;

	if (consume(ctx, COLON)!)
	{
		struct_decl.type = parse_type_expr(ctx, { .no_generics = true })!;
		struct_decl.attributes = parse_attributes(ctx, node)!;
	}

	@expect_else_skip(ctx, LBRACE, { RBRACE } ; brace_err)
	{
		return brace_err;
	}!;

	List{Node*} fields;
	fields.tinit();

	while (!ctx.is(RBRACE) && !ctx.is(EOF))
	{
		int field_start  = ctx.peek(0).pos;
		Node* field_node = ctx.ast.alloc_node(VAR_DECL, field_start);
		VarDecl* field   = field_node.as(VAR_DECL);
		field.kind = VAR_BITFIELD;

		if (ctx.is(CONTRACT)) field.contract.set(parse_contract_decl(ctx)!);
		field.type = parse_type_expr(ctx)!;
		field.attributes = parse_attributes(ctx, field_node)!;

		if IF_IDENT: (true)
		{
			Token t = @expect_else_skip(ctx, IDENT, { COLON, EOS, RBRACE } ; name_err)
			{
				field.name = ast::EMPTY_STR;
				break IF_IDENT;
			}!;

			field.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		}

		if (consume(ctx, COLON)!)
		{
			field.init_expr = parse_constant_expr(ctx)!;
			if (consume(ctx, DOTDOT)!)
			{
				field.bit_end = parse_constant_expr(ctx)!;
			}
		}
		expect(ctx, EOS)!;
		field_node.end_token = ctx.peek(0).pos;
		fields.push(field_node);
	}

	expect(ctx, RBRACE)!;
	struct_decl.fields = alloc::clone_slice(ctx.arena, fields.array_view());
	return node;
}

<*
 faultdef_decl ::= FAULTDEF CONST_IDENT (',' CONST_IDENT)* ','? ';'
*>
fn Node*? parse_faultdef_decl(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	expect(ctx, FAULTDEF)!;
	Node* node       = ctx.ast.alloc_node(FAULTDEF_DECL, start_pos);
	FaultdefDecl* fd = node.as(FAULTDEF_DECL);
	defer node.end_token = ctx.peek(0).pos;

	List{Node*} faults;
	faults.tinit();

	while (!ctx.eof() && !ctx.is(EOS))
	{
		Node* fault_node      = ctx.ast.alloc_node(FAULT_DECL, ctx.current().pos);
		FaultDecl* fault_decl = fault_node.as(FAULT_DECL);
		if (ctx.is(AT_IDENT))
		{
			fault_decl.contract.set(parse_contract_decl(ctx)!);
		}

		if CHECK_IDENT: (true)
		{
			Token t = @expect_else(ctx, CONST_IDENT ; err)
			{
				fault_decl.name = ast::EMPTY_STR;
				break CHECK_IDENT;
			}!;

			fault_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		}

		fault_decl.attributes = parse_attributes(ctx, node)!;

		if (consume(ctx, COMMA)!) continue;
		expect(ctx, EOS)!;
		break;
	}

	fd.faults = alloc::clone_slice(ctx.arena, faults.array_view());

	return node;
}

<*
 interface_decl ::= 'interface' TYPE_IDENT ':' (TYPE_IDENT (',' TYPE_IDENT) interface_body
*>
fn Node*? parse_interface_decl(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	expect(ctx, INTERFACE)!;
	Node* node           = ctx.ast.alloc_node(INTERFACE_DECL, start_pos);
	InterfaceDecl* inter = node.as(INTERFACE_DECL);
	defer node.end_token = ctx.peek(0).pos;

	if CHECK_NAME: (true)
	{
		Token t = @expect_else_skip(ctx, TYPE_IDENT, { EOS, AT_IDENT, COLON, LBRACE } ; err)
		{
			inter.name = ast::EMPTY_STR;
			break CHECK_NAME;
		}!;

		inter.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	List{Node*} list;
	list.tinit();

	if (consume(ctx, COLON)!)
	{
		do
		{
			list.push(parse_type_expr(ctx, { .no_generics = true })!);
		} while (consume(ctx, COMMA)!);
	}

	inter.interfaces = alloc::clone_slice(ctx.arena, list.array_view());
	list.clear();
	inter.attributes = parse_attributes(ctx, node)!;

	expect(ctx, LBRACE)!;

	while (!ctx.eof() && !ctx.is(RBRACE))
	{
		Node* contract;
		if (ctx.is(CONTRACT))
		{
			contract = parse_contract_decl(ctx)!;
		}
		Node* func_node = parse_fn_decl(ctx, { .is_interface = true })!;
		FnDecl* func    = func_node.as(FN_DECL);
		if (contract)
		{
			func.contract.set(contract);
		}
	}

	inter.methods = alloc::clone_slice(ctx.arena, list.array_view());

	expect(ctx, RBRACE)!;

	return node;
}

<*
 attrdef_decl ::= "attrdef" AT_IDENT ("(" parameter_list? ")")? ("=" attribute_list)? ";"
*>
fn Node*? parse_attrdef_decl(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	expect(ctx, ATTRDEF)!;
	Node* node       = ctx.ast.alloc_node(ATTRDEF_DECL, start_pos);
	AttrdefDecl* def = node.as(ATTRDEF_DECL);
	defer node.end_token = ctx.peek(0).pos;

	if CHECK_NAME: (true)
	{
		Token t = @expect_else_skip(ctx, AT_TYPE_IDENT, { EOS, EQ, LPAREN, RPAREN } ; err)
		{
			def.name = ast::EMPTY_STR;
			break CHECK_NAME;
		}!;

		def.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	if (ctx.is(LPAREN))
	{
		def.params = parse_parameter_list(ctx, { .is_attrdef = true })!;
	}

	if (consume(ctx, EOS)!)
	{
		return node;
	}

	expect(ctx, EQ)!;

	def.attributes = parse_attributes(ctx, node, { .use_comma = true })!;

	expect(ctx, EOS)!;

	return node;
}

<*
 enum_decl ::= "enum" TYPE_IDENT ("(" type ("," type)* ")")? (":" type? enum_param_list?)? attributes? "{" enum_body "}"

    constdef_decl ::= "constdef" TYPE_IDENT ("(" type ("," type)* ")")? (":" "inline"? type)? attributes? "{" constdef_body "}"
 @param [&inout] ctx
*>
fn Node*? parse_enum_constdef_decl(ParseContext* ctx, ParseFlags flags) => @pool()
{
	int start_pos = ctx.peek(0).pos;

	expect(ctx, flags.is_constdef ? CONSTDEF : ENUM)!;

	Node* node = ctx.ast.alloc_node(ENUM_DECL, start_pos);
	defer node.end_token = ctx.peek(0).pos;
	EnumDecl* enum_decl = node.as(ENUM_DECL);

	if CHECK_IDENT: (true)
	{
		Token t = @expect_else_skip(ctx, TYPE_IDENT, { COLON, LBRACE, EOS } ; err)
		{
			enum_decl.name = ast::EMPTY_STR;
			break CHECK_IDENT;
		}!;

		enum_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	enum_decl.interfaces = parse_interface_type_list(ctx)!;

	// Optional backing type and/or associated value parameters: ":" "inline"? type? enum_param_list?
	if (consume(ctx, COLON)!)
	{
		enum_decl.is_inline_backing = consume(ctx, INLINE)!;

		if (!ctx.is(LPAREN))
		{
			enum_decl.backing_type = parse_type_expr(ctx, { .no_generics = true })!;
		}

		if (consume(ctx, LPAREN)!)
		{
			List{Node*} assoc;
			assoc.init(tmem, 4);
			while (!ctx.is(RPAREN) && !ctx.eof())
			{
				Node* param = ctx.ast.alloc_node(VAR_DECL, ctx.peek(0).pos);
				VarDecl* p  = param.as(VAR_DECL);
				p.type = parse_type_expr(ctx)!;
				if (is_non_type_ident(ctx.current().kind))
				{
					p.name = ctx.ast.string_pool.internalize(ctx.token_text(ctx.peek(0)));
					advance(ctx)!;
				}
				if (ctx.is(AT_IDENT))
				{
					parse_attributes(ctx, param)!;
				}
				param.end_token = ctx.peek(0).pos;
				assoc.push(param);
				if (!consume(ctx, COMMA)!) break;
			}
			expect(ctx, RPAREN)!;
			enum_decl.assoc_params = alloc::clone_slice(ctx.arena, assoc.array_view());
		}
	}

	if (ctx.is(AT_IDENT))
	{
		enum_decl.attributes = parse_attributes(ctx, node)!;
	}

	expect(ctx, LBRACE)!;

	List{Node*} variants;
	variants.init(tmem, 4);
	while ENUM_VARIANT: (!ctx.is(RBRACE) && !ctx.eof())
	{
		if (!ctx.is(CONST_IDENT))
		{
			variants.push(unexpected(ctx, "Expected enum variant name")!);
			ctx.skip_until({ COMMA, RBRACE, EOS })!;
			consume(ctx, COMMA)!;
			continue;
		}

		Node* variant = ctx.ast.alloc_node(VAR_DECL, ctx.peek(0).pos);
		VarDecl* v    = variant.as(VAR_DECL);
		v.kind = VAR_GLOBAL;
		v.flags.is_const = true;
		v.name = ctx.ast.string_pool.internalize(ctx.token_text(ctx.peek(0)));
		advance(ctx)!;

		// Optional per-variant attributes: @attr ...  (come before = and {})
		if (ctx.is(AT_IDENT))
		{
			v.attributes = parse_attributes(ctx, variant)!;
		}

		// Optional ordinal: "=" expr
		if (consume(ctx, EQ)!)
		{
			v.init_expr = parse_expr(ctx)!;
		}

		// Optional associated values: "{" expr ("," expr)* "}"
		if (ctx.is(LBRACE))
		{
			v.assoc_values = parse_expr(ctx)!;
		}

		variant.end_token = ctx.peek(0).pos;
		variants.push(variant);

		if (!consume(ctx, COMMA)!) break;
	}

	expect(ctx, RBRACE)!;

	enum_decl.variants = alloc::clone_slice(ctx.arena, variants.array_view());

	return node;
}

<*
 generic_decl ::= '<' (type_expr | ident_expr)* '>'
 @return "null if no generics are present"
*>
fn Node*? parse_generic_decl(ParseContext* ctx) => @pool()
{
	if (!ctx.is(LESS))
	{
		return null;
	}
	if (ctx.is(GREATER))
	{
		unexpected(ctx, "At least one parameter is required")!;
		return null;
	}

	expect(ctx, LESS)!;

	int start_pos = ctx.peek(0).pos;
	Node* node    = ctx.ast.alloc_node(GENERIC_DECL, start_pos);
	defer node.end_token = ctx.peek(0).pos;
	GenericDecl* gen = node.as(GENERIC_DECL);
	List{Node*} params;
	params.tinit();
	while (!ctx.eof())
	{
		switch (ctx.current().kind)
		{
			case TYPE_IDENT:
			case CONST_IDENT:
				break;
			default:
				params.push(unexpected(ctx, "Expected either 'Type' or 'CONST_IDENT'")!);
				advance(ctx)!;
		}

		// so it only parses the prefix
		params.push(parse_expr(ctx, HIGHEST)!);
		if (!consume(ctx, COMMA)!) break;
	}
	expect(ctx, GREATER)!;
	gen.params = alloc::clone_slice(ctx.arena, params.array_view());
	return node;
}
