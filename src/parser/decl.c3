module analyzer::parser;
import analyzer::core;
import std::collections::list;
import std::io;

<*
 module_decl ::= module path_expr ';' attributes?
*>
fn Node*? parse_module_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, MODULE)!;
	plog::debug("parse_mod");
	Node* node           = ctx.ast.alloc_node(MODULE_DECL, start_pos);
	ModuleDecl* mod_decl = node.as(MODULE_DECL);

	mod_decl.path = parse_path_expr(scope)!;
	mod_decl.generics = parse_generic_decl(scope)!;

	if (ctx.is(AT_IDENT))
	{
		mod_decl.attributes = parse_attributes(scope, node)!;
	}

	node.offset.end = ctx.current_pos();

	expect(ctx, EOS)!;

	PathExpr* path = mod_decl.path.as(PATH_EXPR);
    String mod_name = path.full_path(&ctx.ast.string_pool, ctx.allocator)!;
    defer mod_name.free(ctx.allocator);

    if (ctx.on_new_module != null)
    {
        ctx.section = ctx.on_new_module(ctx.user_data, mod_name);
    }

	return node;
}

<*

*>
fn Node*? parse_contract_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
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
				requires.push(parse_contract_expr(scope)!);
			}
			else if (attr == constants::KW_AT_ENSURE)
			{
				plog::debug("parse_contract_decl - @ensure");
				ensures.push(parse_contract_expr(scope)!);
			}
			else if (attr == constants::KW_AT_PARAM)
			{
				params.push(parse_contract_param(scope))!;
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
				if (ctx.current().kind == EOS && ctx.peek(1)!.kind == STRING_LITERAL)
				{
					advance(ctx)!;
				}
				int start = ctx.current().pos;
				if (ctx.is(STRING_LITERAL))
				{
					List{Node*} exprs;
					exprs.tinit(1);
					exprs.push(parse_expr(scope)!);
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
						returns.push(parse_expr(scope)!);
						if (!consume(ctx, COMMA)!)
						{
							break;
						}
					}
				}
				else
				{
					contract.return_desc = parse_expr(scope)!;
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
fn Node*? parse_import_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, IMPORT)!;
	Node* node      = ctx.ast.alloc_node(IMPORT_DECL, start_pos);
	ImportDecl* imp = node.as(IMPORT_DECL);

	List{Node*} temp_paths;
	temp_paths.init(tmem, 4);

	while (true)
	{
		Node* path_node = parse_path_expr(scope)!;
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
		imp.attributes = parse_attributes(scope, node)!;
	}

	node.offset.end = ctx.current_pos();
	
	expect(ctx, EOS)!;

	return node;
}

<*
 alias_type_decl ::= 'alias' TYPE_IDENT generic_decl? attributes? '=' type_expr ';'
 module_alias_decl ::= 'alias' IDENT attributes? '=' 'module' module_path ';'
 alias_decl ::= 'alias' alias_name generic_decl? attributes? '=' alias_source ';'

 Alias names are classified by lexer token kind. A TYPE_IDENT name parses a
 type-expression target, `module` after '=' parses a module path target, and
 identifier-style aliases require the target path's final token kind to match
 the alias name kind. Alias generics and attributes use the shared declaration
 parsers and are represented on AliasDecl.
 @require(scope.ctx != null) : "Parser context positioned at the alias keyword."
*>
fn Node*? parse_alias_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, ALIAS)!;
	Node* node            = ctx.ast.alloc_node(ALIAS_DECL, start_pos);
	AliasDecl* alias_decl = node.as(ALIAS_DECL);

	do CHECK_NAME:
	{
		Token t = @expect_some_else(ctx, { TYPE_IDENT, IDENT, CONST_IDENT, AT_IDENT } ; err)
		{
			ctx.error("Expected alias name identifier");
			alias_decl.name = string_pool::EMPTY_STR;
			break CHECK_NAME;
		}!;

		alias_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		alias_decl.name_kind = t.kind;
	};

	alias_decl.generics = parse_generic_decl(scope)!;
	alias_decl.attributes = parse_attributes(scope, node, { .allow_type_ident = true })!;

	expect(ctx, EQ)!;

	if (ctx.is(MODULE))
	{
		alias_decl.alias_kind = MODULE_ALIAS;
		advance(ctx)!;
		alias_decl.target = parse_path_expr(scope)!;
	}
	else if (alias_decl.name_kind == TYPE_IDENT)
	{
		alias_decl.alias_kind = TYPE_ALIAS;
		alias_decl.target = parse_alias_type_target(scope)!;
	}
	else
	{
		alias_decl.alias_kind = IDENT_ALIAS;
		alias_decl.target = parse_expr(scope)!;
		if (ctx.is(LBRACE))
		{
			// TODO: represent generic target arguments for identifier aliases.
			skip_balanced_group(ctx, LBRACE, RBRACE)!;
		}
	}

	node.offset.end = ctx.current_pos();

	expect(ctx, EOS)!;
	return node;
}

<*
 typedef_decl ::= 'typedef' TYPE_IDENT interface_list? attributes? '=' 'inline'? type_expr attributes? ';'

 Typedef declarations create distinct types. Function pointer syntax is
 alias-only in C3, so a typedef base beginning with `fn` is consumed only for
 recovery and an ERROR node is returned.
*>
fn Node*? parse_typedef_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = ctx.current().pos;
	expect(ctx, TYPEDEF)!;
	Node* node                = ctx.ast.alloc_node(TYPEDEF_DECL, start_pos);
	TypedefDecl* typedef_decl = node.as(TYPEDEF_DECL);

	if (flags.is_inline)
	{
		ctx.error("'inline' must appear after '=' in typedef declarations");
		node.kind = MISSING;
	}

	Token name = ctx.current();
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

	typedef_decl.generics = parse_generic_decl(scope)!;
	typedef_decl.interfaces = parse_interface_type_list(scope)!;
	foreach (interface_type : typedef_decl.interfaces)
	{
		if (is_error_or_missing_node(interface_type))
		{
			node.kind = MISSING;
		}
	}

	List{Node*} attributes;
	attributes.init(tmem, 4);
	parse_attributes_into(scope, node, &attributes)!;

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
		typedef_decl.base_type = parse_type_expr(scope)!;
	}

	parse_attributes_into(scope, node, &attributes)!;
	typedef_decl.attributes = alloc::clone_slice(ctx.arena, attributes.array_view());
	node.offset.end = ctx.current_pos();
	expect(ctx, EOS)!;
	return node;
}

<*
 macro_decl ::= macro type_expr? (type_expr '.')? ident '(' parameter_list? ')' attributes?
 fn_body ::= ('=>' short_body) | compound_stmt
*>
fn Node*? parse_macro_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = ctx.current().pos;

	expect(ctx, MACRO)!;

	plog::debug("parse_macro");

	Node* node     = ctx.ast.alloc_node(MACRO_DECL, start_pos);
	MacroDecl* mac = node.as(MACRO_DECL);

	if (is_type(ctx) && ctx.peek(1)!.kind != DOT)
	{
		mac.ret_type.set(parse_type_expr(scope)!);
	}

	if IS_TYPE: (is_type(ctx))
	{
		mac.associated_type.set(parse_type_expr(scope)!);

		expect(ctx, DOT)!;

		Token t;
		if (ctx.is(AT_IDENT))
		{
			t = ctx.current();
			advance(ctx)!;
		}
		else
		{
			t = @expect_else_skip(ctx, IDENT, { EOS, LPAREN } ; err)
			{
				ctx.error("Expected member function name identifier");
				mac.name = string_pool::EMPTY_STR;
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
			mac.name = string_pool::EMPTY_STR;
			break IS_TYPE;
		}!;
		mac.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	parse_macro_params(scope, node)!;

	if (ctx.is(AT_IDENT))
	{
		mac.attributes = parse_attributes(scope, node)!;
	}

	if (ctx.is(LBRACE))
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have a structural block body");
			return ctx.ast.error(start_pos);
		}
		mac.body = parse_compound_stmt(scope)!;
		node.offset.end = mac.body.offset.end;
	}
	else if (consume(ctx, IMPLIES)!)
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have an expression body");
			return ctx.ast.error(start_pos);
		}

		mac.body = parse_short_body(scope, true)!;
		node.offset.end = mac.body.offset.end;		
	}
	else
	{
		// No body provided
		node.offset.end = ctx.current_pos();
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
 @require (scope.ctx != null)
*>
fn Node*? parse_param_decl(ContextScope scope, ParamParseFlags flags = {})
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;

	Node* node     = ctx.ast.alloc_node(VAR_DECL, start_pos);
	VarDecl* param = node.as(VAR_DECL);

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
		parsed_type = parse_type_expr(scope)!;
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

	Token t = ctx.current();
	switch (t.kind)
	{
		case CT_CONST_IDENT:
			ctx.error("Parameter names may not be all uppercase.");
			ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
			return ctx.ast.error(start_pos);
		case CT_IDENT:
			param.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
			param.kind = VAR_PARAM_CT;
			node.offset.end = ctx.current_pos();
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
			node.offset.end = ctx.current_pos();
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
			node.offset.end = ctx.current_pos();
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
			node.offset.end = ctx.current_pos();
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
			param.name = string_pool::EMPTY_STR;
			param.kind = VAR_PARAM;
			break;

		default:
			ctx.error("Expected a valid parameter definition.");
			ctx.skip_until({ EOF, EOS, RPAREN, RBRACE })!;
			return ctx.ast.error(start_pos);
	}

	if (ctx.is(AT_IDENT))
	{
		param.attributes = parse_attributes(scope, node)!;
	}

	if (consume(ctx, EQ)!)
	{
		if (consume(ctx, ELLIPSIS)!)
		{
			param.flags.is_macro_optional_ellipsis = true;
		}
		else
		{
			param.init_expr = parse_expr(scope)!;
			node.offset.end = param.init_expr.offset.end;
		}
	}

	return node;
}

<*
 var_decl ::= ('var' | type_expr) decl_element (',' decl_element)* ';'
*>
fn Node*? parse_var_decl(ContextScope scope, Node* type = null)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = ctx.current().pos;

	Node* contract;
	if (ctx.is(CONTRACT))
	{
		contract = parse_contract_decl(scope)!;
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
		else if (is_type_primitive(ctx.current().kind) || ctx.is(IDENT) || ctx.is(TYPE_IDENT))
		{
			type_node = parse_type_expr(scope.with_only_flags(flags), null)!;
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
		Token t = ctx.current();

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
		if (t.kind != CT_IDENT && t.kind != CT_TYPE_IDENT && flags.is_comptime)
		{
			unexpected(ctx, "name must be a $ident")!;
		}

		StringID name_id = ctx.ast.string_pool.internalize(ctx.token_text(t));
		advance(ctx)!;

		Node* var_node    = ctx.ast.alloc_node(VAR_DECL, t.pos);
		VarDecl* var_decl = var_node.as(VAR_DECL);

		if (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
		{
			var_decl.attributes = parse_attributes(scope, var_node, { .allow_type_ident = true })!;
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

			init_expr = parse_expr(scope)!;
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

		var_node.offset.end = ctx.current().pos;

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
			return ctx.ast.alloc_node(ERROR, ctx.current().pos);
		}
	}

	return head_node;
}

<*
 attributes ::= attribute attribute*
  attribute  ::= AT_IDENT ("(" expression_list? ")")?
 @require(scope.ctx != null)
*>
fn NodeArray? parse_attributes(ContextScope scope, Node* parent_node, AttributeParseFlags flags = { }) => @pool()
{
	ParseContext* ctx = scope.ctx;
	List{Node*} nodes;
	nodes.init(tmem, 4);

	while (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
	{
		if (ctx.is(AT_TYPE_IDENT) && !flags.allow_type_ident)
		{
			unexpected(ctx, "Tried parsing a @TypeIdent when not allowed")!;
		}

		Token t = ctx.current();
		advance(ctx)!;

		Node* attr_node = ctx.ast.alloc_node(ATTRIBUTE_DECL, t.pos);
		AttributeDecl* attr = attr_node.as(ATTRIBUTE_DECL);
		String text         = ctx.token_text(t);
		attr.name = text.copy(&ctx.ast.arena);
		attr.kind = core::get_attribute_from_string(text);

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
				exprs.push(parse_constant_expr(scope)!);
				if (!consume(ctx, COMMA)!) break;
			}
			attr_node.offset.end = ctx.current_pos();
			expect(ctx, RPAREN)!;
			attr.exprs = alloc::clone_slice(&ctx.ast.arena, exprs.array_view());
		}

		nodes.push(attr_node);

		if (flags.use_comma)
		{
			attr_node.offset.end = ctx.current_pos();
			consume(ctx, COMMA)!;
		}
	}

	if (parent_node) parent_node.flags.has_attributes = nodes.len() > 0;

	return alloc::clone_slice(&ctx.ast.arena, nodes.array_view());
}

<*
 ct_expand_decl ::= $expand '(' expr ')' attributes? ';'
*>
fn Node*? parse_expand_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, CT_EXPAND)!;
	Node* node           = ctx.ast.alloc_node(CT_EXPAND_DECL, start_pos);
	CtExpandDecl* expand = node.as(CT_EXPAND_DECL);
	expect(ctx, LPAREN)!;
	expand.expr = parse_constant_expr(scope)!;
	expect(ctx, RPAREN)!;
	if (ctx.is(AT_IDENT))
	{
		expand.attributes = parse_attributes(scope, node)!;
	}
	node.offset.end = ctx.current_pos();
	expect(ctx, EOS)!;
	return node;
}

<*
 struct_decl ::= "struct | union" TYPE_IDENT ("(" type ("," type)* ")")? attributes? "{" struct_body "}"
*>
fn Node*? parse_struct_union_decl(ContextScope scope, bool is_sub = false) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	int start_pos  = ctx.current().pos;
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

	do NAME_CHECK:
	{
		if (!is_sub)
		{
			Token t = @expect_some_else(ctx, { TYPE_IDENT } ; err)
			{
				ctx.error("Structs must have a 'Type' identifier");
				struct_decl.name = string_pool::EMPTY_STR;
				break NAME_CHECK;
			}!;

			struct_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
			break NAME_CHECK;
		}

		if (ctx.is(IDENT))
		{
			struct_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(ctx.current()));
			advance(ctx)!;
		}
	};

	struct_decl.interfaces = parse_interface_type_list(scope)!;
	struct_decl.generics = parse_generic_decl(scope)!;
	struct_decl.attributes = parse_attributes(scope, node, { .allow_type_ident = true })!;

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
				sub_decl = parse_bitstruct_decl(scope, true)!;
			}
			else
			{
				sub_decl = parse_struct_union_decl(scope, true)!;
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
			ParseFlags struct_flags;
			struct_flags.is_struct = true;
			struct_flags.is_inline = consume(ctx, INLINE)!;
			Node* field = parse_var_decl(scope.with_only_flags(struct_flags), null)!;
			fields.push(field);
		}
	}

	node.offset.end = ctx.current_pos();
	expect(ctx, RBRACE)!;

	struct_decl.fields = alloc::clone_slice(ctx.arena, fields.array_view());
	return node;
}

<*
 bitstruct_decl ::= "bitstruct" TYPE_IDENT ("(" type ("," type)* ")")? ":" type attributes? "{" bitstruct_body "}"
*>
fn Node*? parse_bitstruct_decl(ContextScope scope, bool is_nested = false) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, BITSTRUCT)!;
	Node* node              = ctx.ast.alloc_node(STRUCT_DECL, start_pos);
	StructDecl* struct_decl = node.as(STRUCT_DECL);

	if COND: (true)
	{
		Token t = @expect_some_else(ctx, { IDENT, TYPE_IDENT } ; err)
		{
			ctx.error("Bitstructs must have a name identifier");
			struct_decl.name = string_pool::EMPTY_STR;
			break COND;
		}!;

		struct_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	struct_decl.interfaces = parse_interface_type_list(scope.with_only_flags({ .no_generics = true }))!;

	if (consume(ctx, COLON)!)
	{
		struct_decl.type = parse_type_expr(scope.with_only_flags({ .no_generics = true }), null)!;
		struct_decl.attributes = parse_attributes(scope, node)!;
	}

	@expect_else_skip(ctx, LBRACE, { RBRACE } ; brace_err)
	{
		return brace_err;
	}!;

	List{Node*} fields;
	fields.tinit();

	while (!ctx.is(RBRACE) && !ctx.is(EOF))
	{
		int field_start  = ctx.current().pos;
		Node* field_node = ctx.ast.alloc_node(VAR_DECL, field_start);
		VarDecl* field   = field_node.as(VAR_DECL);
		field.kind = VAR_BITFIELD;

		if (ctx.is(CONTRACT)) field.contract.set(parse_contract_decl(scope)!);
		field.type = parse_type_expr(scope)!;
		field.attributes = parse_attributes(scope, field_node)!;

		if IF_IDENT: (true)
		{
			Token t = @expect_else_skip(ctx, IDENT, { COLON, EOS, RBRACE } ; name_err)
			{
				field.name = string_pool::EMPTY_STR;
				break IF_IDENT;
			}!;

			field.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		}

		if (consume(ctx, COLON)!)
		{
			field.init_expr = parse_constant_expr(scope)!;
			if (consume(ctx, DOTDOT)!)
			{
				field.bit_end = parse_constant_expr(scope)!;
			}
		}
		expect(ctx, EOS)!;
		field_node.offset.end = ctx.current().pos;
		fields.push(field_node);
	}

	node.offset.end = ctx.current_pos();
	expect(ctx, RBRACE)!;
	struct_decl.fields = alloc::clone_slice(ctx.arena, fields.array_view());
	return node;
}

<*
 faultdef_decl ::= FAULTDEF CONST_IDENT (',' CONST_IDENT)* ','? ';'
*>
fn Node*? parse_faultdef_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, FAULTDEF)!;
	Node* node       = ctx.ast.alloc_node(FAULTDEF_DECL, start_pos);
	FaultdefDecl* fd = node.as(FAULTDEF_DECL);

	List{Node*} faults;
	faults.tinit();

	while (!ctx.eof() && !ctx.is(EOS))
	{
		Node* fault_node      = ctx.ast.alloc_node(FAULT_DECL, ctx.current().pos);
		FaultDecl* fault_decl = fault_node.as(FAULT_DECL);
		if (ctx.is(AT_IDENT))
		{
			fault_decl.contract.set(parse_contract_decl(scope)!);
		}

		if CHECK_IDENT: (true)
		{
			Token t = @expect_else(ctx, CONST_IDENT ; err)
			{
				fault_decl.name = string_pool::EMPTY_STR;
				break CHECK_IDENT;
			}!;

			fault_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		}

		fault_decl.attributes = parse_attributes(scope, node)!;

		node.offset.end = ctx.current_pos();
		if (consume(ctx, COMMA)!) continue;
		node.offset.end = ctx.current_pos();
		expect(ctx, EOS)!;
		break;
	}

	fd.faults = alloc::clone_slice(ctx.arena, faults.array_view());

	return node;
}

<*
 interface_decl ::= 'interface' TYPE_IDENT ':' (TYPE_IDENT (',' TYPE_IDENT) interface_body
*>
fn Node*? parse_interface_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, INTERFACE)!;
	Node* node           = ctx.ast.alloc_node(INTERFACE_DECL, start_pos);
	InterfaceDecl* inter = node.as(INTERFACE_DECL);

	if CHECK_NAME: (true)
	{
		Token t = @expect_else_skip(ctx, TYPE_IDENT, { EOS, AT_IDENT, COLON, LBRACE } ; err)
		{
			inter.name = string_pool::EMPTY_STR;
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
			list.push(parse_type_expr(scope.with_only_flags({ .no_generics = true }), null)!);
		} while (consume(ctx, COMMA)!);
	}

	inter.interfaces = alloc::clone_slice(ctx.arena, list.array_view());
	list.clear();
	inter.attributes = parse_attributes(scope, node)!;

	expect(ctx, LBRACE)!;

	while (!ctx.eof() && !ctx.is(RBRACE))
	{
		Node* contract;
		if (ctx.is(CONTRACT))
		{
			contract = parse_contract_decl(scope)!;
		}
		Node* func_node = parse_fn_decl(scope.with_only_flags({ .is_interface = true }))!;
		FnDecl* func    = func_node.as(FN_DECL);
		if (contract)
		{
			func.contract.set(contract);
		}
	}

	inter.methods = alloc::clone_slice(ctx.arena, list.array_view());
	node.offset.end = ctx.current_pos();
	expect(ctx, RBRACE)!;

	return node;
}

<*
 attrdef_decl ::= "attrdef" AT_IDENT ("(" parameter_list? ")")? ("=" attribute_list)? ";"
*>
fn Node*? parse_attrdef_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	int start_pos = ctx.current().pos;
	expect(ctx, ATTRDEF)!;
	Node* node       = ctx.ast.alloc_node(ATTRDEF_DECL, start_pos);
	AttrdefDecl* def = node.as(ATTRDEF_DECL);

	if CHECK_NAME: (true)
	{
		Token t = @expect_else_skip(ctx, AT_TYPE_IDENT, { EOS, EQ, LPAREN, RPAREN } ; err)
		{
			def.name = string_pool::EMPTY_STR;
			break CHECK_NAME;
		}!;

		def.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	if (ctx.is(LPAREN))
	{
		def.params = parse_parameter_list(scope)!;//, { .is_attrdef = true })!;
	}

	if (consume(ctx, EOS)!)
	{
		return node;
	}

	expect(ctx, EQ)!;

	def.attributes = parse_attributes(scope, node, { .use_comma = true })!;

	node.offset.end = ctx.current_pos();
	expect(ctx, EOS)!;

	return node;
}

<*
 enum_decl ::= "enum" TYPE_IDENT ("(" type ("," type)* ")")? (":" type? enum_param_list?)? attributes? "{" enum_body "}"

    constdef_decl ::= "constdef" TYPE_IDENT ("(" type ("," type)* ")")? (":" "inline"? type)? attributes? "{" constdef_body "}"
*>
fn Node*? parse_enum_constdef_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = ctx.current().pos;

	expect(ctx, flags.is_constdef ? CONSTDEF : ENUM)!;

	Node* node = ctx.ast.alloc_node(ENUM_DECL, start_pos);
	EnumDecl* enum_decl = node.as(ENUM_DECL);

	if CHECK_IDENT: (true)
	{
		Token t = @expect_else_skip(ctx, TYPE_IDENT, { COLON, LBRACE, EOS } ; err)
		{
			enum_decl.name = string_pool::EMPTY_STR;
			log::error("Set enum to empty");
			break CHECK_IDENT;
		}!;

		enum_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	enum_decl.interfaces = parse_interface_type_list(scope)!;

	// Optional backing type and/or associated value parameters: ":" "inline"? type? enum_param_list?
	if (consume(ctx, COLON)!)
	{
		enum_decl.is_inline_backing = consume(ctx, INLINE)!;

		if (!ctx.is(LPAREN))
		{
			enum_decl.backing_type = parse_type_expr(scope.with_only_flags({ .no_generics = true }), null)!;
		}

		if (consume(ctx, LPAREN)!)
		{
			List{Node*} assoc;
			assoc.init(tmem, 4);
			while (!ctx.is(RPAREN) && !ctx.eof())
			{
				Node* param = ctx.ast.alloc_node(VAR_DECL, ctx.current().pos);
				VarDecl* p  = param.as(VAR_DECL);

				p.type = parse_type_expr(scope)!;
				if (is_non_type_ident(ctx.current().kind))
				{
					p.name = ctx.ast.string_pool.internalize(ctx.token_text(ctx.current()));
					advance(ctx)!;
				}
				if (ctx.is(AT_IDENT))
				{
					parse_attributes(scope, param)!;
				}
				param.offset.end = ctx.current().pos;
				assoc.push(param);
				if (!consume(ctx, COMMA)!) break;
			}
			expect(ctx, RPAREN)!;
			enum_decl.assoc_params = alloc::clone_slice(ctx.arena, assoc.array_view());
		}
	}

	if (ctx.is(AT_IDENT))
	{
		enum_decl.attributes = parse_attributes(scope, node)!;
	}

	expect(ctx, LBRACE)!;

	List{Node*} variants;
	variants.init(tmem, 4);
	while ENUM_VARIANT: (!ctx.is(RBRACE) && !ctx.eof())
	{
		Node* contract;
		if (ctx.is(CONTRACT))
		{
			contract = parse_contract_decl(scope)!;
		}
		if (!ctx.is(CONST_IDENT))
		{
			variants.push(unexpected(ctx, "Expected enum variant name")!);
			ctx.skip_until({ COMMA, RBRACE, CONTRACT, CONST_IDENT })!;
            consume(ctx, COMMA)!;
			continue;
		}

		Node* variant = ctx.ast.alloc_node(VAR_DECL, ctx.current().pos);
		VarDecl* v    = variant.as(VAR_DECL);
		v.kind = VAR_GLOBAL;
		v.contract.set(contract);
		v.flags.is_const = true;
		v.name = ctx.ast.string_pool.internalize(ctx.token_text(ctx.current()));
		advance(ctx)!;

		// Optional per-variant attributes: @attr ...  (come before = and {})
		if (ctx.is(AT_IDENT))
		{
			v.attributes = parse_attributes(scope, variant)!;
		}

		// Optional ordinal: "=" expr
		if (consume(ctx, EQ)!)
		{
			v.init_expr = parse_expr(scope)!;
		}

		// Optional associated values: "{" expr ("," expr)* "}"
		if (ctx.is(LBRACE))
		{
			v.assoc_values = parse_expr(scope)!;
		}

		variant.offset.end = ctx.current().pos;
		variants.push(variant);

		if (!consume(ctx, COMMA)!) break;
	}

	node.offset.end = ctx.current_pos();

	expect(ctx, RBRACE)!;

	enum_decl.variants = alloc::clone_slice(ctx.arena, variants.array_view());

	return node;
}

<*
 generic_decl ::= '<' (type_expr | ident_expr)* '>'
 @return "null if no generics are present"
*>
fn Node*? parse_generic_decl(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
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

	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(GENERIC_DECL, start_pos);
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
		params.push(parse_expr(scope, HIGHEST)!);
		if (!consume(ctx, COMMA)!) break;
	}
	node.offset.end = ctx.current_pos();
	expect(ctx, GREATER)!;
	gen.params = alloc::clone_slice(ctx.arena, params.array_view());
	return node;
}
