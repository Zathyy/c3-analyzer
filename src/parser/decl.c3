module parser::parser;
import parser::ast;
import lexer;

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
	if (!expect(ctx, MODULE)!)
	{
		ctx.error("Expected a starting 'module'");
		return ctx.ast.error(start_pos);
	}

	log::debug("parse_mod");

	Node* node           = ctx.ast.alloc_node(MODULE_DECL, start_pos);
	ModuleDecl* mod_decl = node.as(MODULE_DECL);
	defer node.end_token = ctx.peek(0).pos;

	mod_decl.path = parse_path_expr(ctx, false)!;
	if (!expect(ctx, EOS)!)
	{
		node.kind = MISSING;
	}

	if (ctx.is(AT_IDENT))
	{
		// TODO:
		// mod.attributes = parse_attributes(ctx)!;
	}

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
	int global_offset    = contract_token.pos;

	String slice = ctx.token_text(contract_token);

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

		log::debug("ContractLexer - added: %s", next.kind);
	}
	contract_tokens.push({ .kind = EOF, .pos = (contract_tokens.last()
		.pos + contract_tokens.last().len) ?? 0, .len = 0 });

	ctx.tokens = contract_tokens.array_view();
	ctx.pos = 0;

	Node* node             = ctx.ast.alloc_node(CONTRACT_DECL, ctx.current().pos);
	ContractDecl* contract = node.as(CONTRACT_DECL);
	log::debug("comment : %s", cl.description);
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
		log::debug("parse_contract - attribute = %s", attr);

		if (consume(ctx, AT_IDENT)!)
		{
			if (attr == constants::KW_AT_REQUIRE)
			{
				log::debug("parse_contract_decl - @require");
				requires.push(parse_contract_expr(ctx)!);
			}
			else if (attr == constants::KW_AT_ENSURE)
			{
				log::debug("parse_contract_decl - @ensure");
				ensures.push(parse_contract_expr(ctx)!);
			}
			else if (attr == constants::KW_AT_PARAM)
			{
				params.push(parse_contract_param(ctx))!;
			}
			else if (attr == constants::KW_AT_DEPRECATED)
			{
				log::debug("parse_contract_decl - @deprecated");
				Node* n = ctx.ast.alloc_node(ATTRIBUTE_DECL, ctx.current().pos);
				contract.deprecated = n;
				AttributeDecl* attribute = n.as(ATTRIBUTE_DECL);
				attribute.path = ctx.ast.alloc_node(MISSING, ctx.current().pos);
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
					log::debug("parser @deprecated string");
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

	@expect_else(ctx, IMPORT ; err)
	{
		return err;
	}!;

	Node* node      = ctx.ast.alloc_node(IMPORT_DECL, start_pos);
	ImportDecl* imp = node.as(IMPORT_DECL);
	defer node.end_token = ctx.peek(0).pos;

	List{Node*} temp_paths;
	temp_paths.init(tmem, 4);

	while (true)
	{
		Node* path_node = parse_path_expr(ctx, false)!;
		temp_paths.push(path_node);

		if (!consume(ctx, COMMA)!) break;
		if (ctx.is(EOS))
		{
			ctx.error("Expected an import path after ','");
			temp_paths.push(ctx.ast.alloc_node(MISSING, ctx.peek(0).pos));
			break;
		}
	}

	imp.paths = alloc::clone_slice(ctx.arena, temp_paths.array_view());

	if (!expect(ctx, EOS)!)
	{
		node.kind = MISSING;
	}

	if (ctx.is(AT_IDENT))
	{
		// TODO:
		// mod.attributes = parse_attributes(ctx)!;
	}

	return node;
}

<*
 Parse the generic parameter list after an alias name.
 @param [&inout] ctx : "Parser context to consume tokens from."
 @param [&out] has_error : "Set true when the list is malformed, even if parsing can recover."
*>
fn StringID[]? parse_alias_generic_decl(ParseContext* ctx, bool* has_error) => @pool()
{
	List{StringID} temp_params;
	temp_params.init(tmem, 4);
	*has_error = false;

	if (!expect(ctx, LESS)!)
	{
		*has_error = true;
		return alloc::clone_slice(ctx.arena, temp_params.array_view());
	}

	while (!ctx.eof() && !ctx.is(GREATER))
	{
		Token t = ctx.peek(0);
		if (t.kind != TYPE_IDENT && t.kind != CONST_IDENT)
		{
			ctx.error("Expected generic alias parameter name");
			*has_error = true;
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
			*has_error = true;
		}
	}

	if (!expect(ctx, GREATER)!)
	{
		*has_error = true;
		return alloc::clone_slice(ctx.arena, temp_params.array_view());
	}

	return alloc::clone_slice(ctx.arena, temp_params.array_view());
}

fn void? skip_balanced_group(ParseContext* ctx, TokenKind open, TokenKind close)
{
	if (!expect(ctx, open)!) return;

	int depth = 1;
	while (!ctx.eof() && depth > 0)
	{
		if (ctx.is(open))
		{
			depth++;
		}
		else if (ctx.is(close))
		{
			depth--;
		}

		advance(ctx)!;
	}
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
 Parse the target of `alias name = module path;`.
 @param [&inout] ctx : "Parser context positioned at the first module path token."
*>
fn Node*? parse_alias_module_path(ParseContext* ctx) => @pool()
{
	TokenKind source_kind = INVALID;
	Node* node            = parse_path_expr_with_options(ctx, &source_kind)!;
	if (source_kind != IDENT)
	{
		ctx.error("Expected module path after 'module' in alias declaration");
		node.kind = MISSING;
	}
	return node;
}

<*
 Parse an identifier-style alias target path.

 Allows CONST_IDENT or AT_IDENT only as the final path segment and reports the
 final token kind for alias-name/source-kind validation.
 @param [&inout] ctx : "Parser context positioned at the first target path token."
 @param [&out] source_kind : "Receives the target path's final token kind."
*>
fn Node*? parse_alias_ident_target_path(ParseContext* ctx, TokenKind* source_kind) => @pool()
{
	return parse_path_expr_with_options(ctx, source_kind, { .allow_const_final = true, .allow_attr_final = true });
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
	if (!expect(ctx, ALIAS)!)
	{
		return ctx.ast.alloc_node(ERROR, start_pos);
	}

	Node* node            = ctx.ast.alloc_node(ALIAS_DECL, start_pos);
	AliasDecl* alias_decl = node.as(ALIAS_DECL);
	defer node.end_token = ctx.peek(0).pos;

	Token name = ctx.peek(0);
	if (!is_alias_name_kind(name.kind))
	{
		ctx.error("Expected alias name identifier");
		node.kind = MISSING;
	}
	else
	{
		alias_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(name));
		alias_decl.name_kind = name.kind;
		advance(ctx)!;
	}

	if (ctx.is(LESS))
	{
		bool generic_parse_failed = false;
		alias_decl.generic_params = parse_alias_generic_decl(ctx, &generic_parse_failed)!;
		if (generic_parse_failed)
		{
			node.kind = MISSING;
		}
	}

	skip_alias_attributes(ctx)!;

	if (!expect(ctx, EQ)!)
	{
		node.kind = MISSING;
		return node;
	}

	if (ctx.is(MODULE))
	{
		alias_decl.alias_kind = MODULE_ALIAS;
		advance(ctx)!;
		alias_decl.target = parse_alias_module_path(ctx)!;
		if (alias_decl.target.kind == ERROR || alias_decl.target.kind == MISSING)
		{
			node.kind = MISSING;
		}
	}
	else if (alias_decl.name_kind == TYPE_IDENT)
	{
		alias_decl.alias_kind = TYPE_ALIAS;
		alias_decl.target = parse_type_expr(ctx)!;
		if (alias_decl.target.kind == ERROR || alias_decl.target.kind == MISSING)
		{
			node.kind = MISSING;
		}
	}
	else
	{
		alias_decl.alias_kind = IDENT_ALIAS;
		TokenKind source_kind = INVALID;
		alias_decl.target = parse_alias_ident_target_path(ctx, &source_kind)!;
		if (!is_alias_source_name_kind(source_kind))
		{
			ctx.error("Expected identifier, constant identifier, or attribute identifier alias source");
			node.kind = MISSING;
		}
		if (alias_decl.name_kind != source_kind)
		{
			ctx.error("Alias name kind must match alias source kind");
			node.kind = MISSING;
		}
		if (ctx.is(LBRACE))
		{
			// TODO: represent generic target arguments for identifier aliases.
			skip_balanced_group(ctx, LBRACE, RBRACE)!;
		}
	}

	if (!expect(ctx, EOS)!)
	{
		node.kind = MISSING;
	}

	return node;
}

<*
 fn_decl ::= fn type_expr (type_expr '.')? ident '(' parameter_list? ')' attributes?
	fn_body ::= ('=>' short_body) | compound_stmt
*>
fn Node*? parse_fn_decl(ParseContext* ctx, ParseFlags flags = { })
{
	int start_pos = ctx.peek(0).pos;

	@expect_else(ctx, FN ; err)
	{
		return err;
	}!;

	log::debug("parse_fn");

	Node* node   = ctx.ast.alloc_node(FN_DECL, start_pos);
	FnDecl* func = node.as(FN_DECL);
	defer node.end_token = ctx.peek(0).pos;

	func.ret_type = parse_type_expr(ctx)!;

	if (is_type(ctx))
	{
		func.associated_type = parse_type_expr(ctx)!;

		if (!expect(ctx, DOT)!)
		{
			node.kind = MISSING;
		}

		Token t = @expect_else(ctx, IDENT ; err)
		{
			ctx.error("Expected member function name identifier");
			func.name = -1;
			return err;
		}!;

		func.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		advance(ctx)!;
	}
	else
	{
		// Standalone Function: No associated type prefix
		func.associated_type = null;

		if (!ctx.is(IDENT))
		{
			ctx.error("Expected function name identifier");
			return ctx.ast.error(start_pos);
		}

		Token t = ctx.peek(0);
		func.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		advance(ctx)!;
	}

	func.params = parse_parameter_list(ctx)!;

	if (ctx.is(LBRACE))
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have a structural block body");
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
			if (!expect(ctx, EOS)!)
			{
				node.kind = MISSING;
			}
		}
	}
	else
	{
		// No body provided
		if (!expect(ctx, EOS)!)
		{
			node.kind = MISSING;
		}
	}

	return node;
}

<*
 param_decl ::= type_expr ELLIPSIS? (non_type_ident ('=' expr))?
                | ELLIPSIS (CT_TYPE_IDENT | non_type_ident ('=' expr)?)?
 @param [&inout] ctx
*>
fn Node*? parse_param_decl(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;

	Node* node       = ctx.ast.alloc_node(PARAM_DECL, start_pos);
	ParamDecl* param = node.as(PARAM_DECL);
	defer node.end_token = ctx.peek(0).pos;

	param.type = parse_type_expr(ctx)!;

	if (consume(ctx, ELLIPSIS)!)
	{
		param.is_variadic = true;

		// Check if a compile-time type or identifier follows: (CT_TYPE_IDENT | non_type_ident)
		if (ctx.is(CT_TYPE_IDENT) || is_non_type_ident(ctx.current().kind))
		{
			Token t = ctx.peek(0);
			param.ident_kind = t.kind;
			param.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
			advance(ctx)!;

			// Handle optional default value assignment ('=' expr)
			if (consume(ctx, EQ)!)
			{
				param.default_value = parse_expr(ctx)!;
			}
		}

		return node;
	}

	// Check for optional trailing ellipsis (e.g., "int... values")
	if (consume(ctx, ELLIPSIS)!)
	{
		param.is_variadic = true;
	}

	if (is_non_type_ident(ctx.current().kind))
	{
		Token t = ctx.peek(0);
		param.ident_kind = t.kind;
		param.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		advance(ctx)!;

		// Handle optional default value assignment ('=' expr)
		if (consume(ctx, EQ)!)
		{
			param.default_value = parse_expr(ctx)!;
		}
	}

	return node;
}

<*
 var_decl ::= ('var' | type_expr) decl_element (',' decl_element)* ';'
*>
fn Node*? parse_var_decl(ParseContext* ctx, ParseFlags flags = { })
{
	int start_pos = ctx.peek(0).pos;

	if (flags.is_local)
	{
		if (flags.is_extern)
		{
			ctx.error("A local variable cannot have an 'extern' modifier");
			return ctx.ast.alloc_node(ERROR, start_pos);
		}
		if (flags.is_inline)
		{
			ctx.error("A local variable cannot be 'inline'");
			return ctx.ast.alloc_node(ERROR, start_pos);
		}
	}

	Node* type_node;

	if (flags.is_var)
	{
		advance(ctx)!; // Consume 'var'
	}
	else if (is_type_primitive(ctx.peek(0).kind) || ctx.is(IDENT) || ctx.is(TYPE_IDENT))
	{
		type_node = parse_type_expr(ctx, flags)!;
		if (type_node.kind == ERROR) return type_node;
	}
	else if (!flags.is_const)
	{
		ctx.error("Expected a valid type signature or 'var'");
		return ctx.ast.alloc_node(ERROR, start_pos);
	}

	Node* head_node;
	Node* tail_node;

	while (true)
	{
		Token t = ctx.peek(0);

		if (flags.is_const && t.kind != CONST_IDENT)
		{
			ctx.error("Constants must use an uppercase CONST_IDENT, found '%s'", ctx.token_text(t));
			return ctx.ast.alloc_node(ERROR, t.pos);
		}
		if (!flags.is_const && t.kind != IDENT && !flags.is_local)
		{
			ctx.error("Global variables must use lower-case IDENT, found '%s'", ctx.token_text(t));
			return ctx.ast.alloc_node(ERROR, t.pos);
		}
		if (t.kind != IDENT && t.kind != CONST_IDENT)
		{
			ctx.error("Expected a variable name identifier, got '%s'", ctx.token_text(t));
			return ctx.ast.alloc_node(ERROR, t.pos);
		}

		StringID name_id = ctx.ast.string_pool.internalize(ctx.token_text(t));
		advance(ctx)!;

		NodeArray attributes; // = parse_attributes(ctx)!;
		Node* init_expr = null;

		if (ctx.is(EQ))
		{
			advance(ctx)!;

			if (head_node != null)
			{
				ctx.error("Initializers are not allowed on multi decleration");
				return ctx.ast.alloc_node(ERROR, ctx.peek(0).pos);
			}
			if (flags.is_extern)
			{
				ctx.error("An extern declaration cannot contain an initial value assignment expression");
				return ctx.ast.alloc_node(ERROR, ctx.peek(0).pos);
			}

			init_expr = parse_expr(ctx)!;
			if (init_expr.kind == ERROR) return init_expr;
		}
		else if (flags.is_const && !flags.is_extern)
		{
			ctx.error("Constants must be initialized at their declaration site");
		}

		Node* var_node    = ctx.ast.alloc_node(VAR_DECL, t.pos);
		VarDecl* var_decl = var_node.as(VAR_DECL);

		var_decl.name = name_id;
		var_decl.type = type_node; // Reused across the entire chain segment
		var_decl.init_expr = init_expr;
		var_decl.attributes = attributes;
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