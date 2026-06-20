<*
 unit.c3 - parsing things which arent any of (Decl, Stmt, Expr)
*>
module analyzer::parser;
import analyzer::core;

import std::io;
import std::collections::list;

import analyzer::core::string_pool;

<*
 @require t.kind == IDENT
*>
fn StringID parse_identifier(ContextScope scope, Token t) 
{   
	ParseContext* ctx = scope.ctx;
	String name = ctx.token_text(t);
	if (!constants::is_valid_name(name)) 
	{
		unexpected_at(ctx, t, "Reserved identifier");
		return string_pool::EMPTY_STR;
	}
	return ctx.ast.string_pool.internalize(name);
}

<*
 parameter_list ::= (param_decl (',' param_decl)*)?
*>
fn NodeArray? parse_parameter_list(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;
	int start_pos = ctx.current().pos;

	if (!flags.is_call)
	{
		expect(ctx, LPAREN)!;
	}

	List{Node*} temp_params;
	temp_params.init(tmem, 4);

	if (ctx.is(RPAREN))
	{
		advance(ctx)!;
		return alloc::clone_slice(ctx.arena, temp_params.array_view());
	}

	while (true)
	{
		if (flags.is_macro && ctx.is(EOS))
		{
			break;
		}

		Node* param = parse_param_decl(scope)!;
		temp_params.push(param);

		if (!consume(ctx, COMMA)!) break;

		if (ctx.is(RPAREN))
		{
			temp_params.push(unexpected_at(ctx, ctx.current(), "Expected parameter declaration after ','")!);
			break;
		}
	}
	if (!flags.is_call && !flags.is_macro)
	{
		expect(ctx, RPAREN)!;
	}
	return alloc::clone_slice(ctx.arena, temp_params.array_view());
}

fn void? parse_macro_params(ContextScope scope, Node* macro_node)
{
	ParseContext* ctx = scope.ctx;
	NodeArray params = parse_parameter_list(scope.with_flags({ .is_macro = true }))!;
	MacroDecl* mac   = macro_node.as(MACRO_DECL);
	mac.params = params;

	if (consume(ctx, EOS)!)
	{
		Token at_tok = ctx.current();
		expect(ctx, AT_IDENT)!;

		Node* body_param_node     = ctx.ast.alloc_node(BODY_PARAM_DECL, at_tok.pos);
		BodyParamDecl* body_param = body_param_node.as(BODY_PARAM_DECL);

		body_param.params = parse_parameter_list(scope)!;
	}

	expect(ctx, RPAREN)!;
}

<*
 generic_param_list ::= '{' expr ( ',' expr )* '}'
*>
fn NodeArray? parse_generics_list(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	if (!consume(ctx, LBRACE)!) return { };
	List{Node*} params;
	params.init(tmem, 4);

	while (true)
	{
		if (ctx.is(RBRACE)) break;
		Node* param = parse_expr(scope)!;
		params.push(param);
		if (!consume(ctx, COMMA)!) break;
	}

	if (!consume(ctx, RBRACE)!)
	{
		ctx.error("Expected closing '}' after generic parameter list");
		return { };
	}

	return alloc::clone_slice(ctx.arena, params.array_view());
}

fn Node*? parse_contract_param(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	int start = ctx.current().pos;

	Node* node = ctx.ast.alloc_node(CONTRACT_PARAM, start);
	defer node.offset.end = ctx.current().pos;
	ContractParam* param = node.as(CONTRACT_PARAM);

	if (consume(ctx, LBRACKET)!)
	{
		param.by_ref = consume(ctx, AMP)!;
		String modifier_name = ctx.token_text(ctx.current());
		switch (modifier_name)
		{
			case "in":
				param.modifier = IN;
				advance(ctx)!;
				break;
			case "inout":
				param.modifier = INOUT;
				advance(ctx)!;
				break;
			case "out":
				param.modifier = OUT;
				advance(ctx)!;
				break;
			default:
				ctx.error("'in', 'out' or 'inout' expected");
				ctx.skip_until({ EOS, EOF })!;
				return ctx.ast.error(ctx.current().pos);
		}

		if (!consume(ctx, RBRACKET)!)
		{
			ctx.error("Expected a closing ']'");
			ctx.skip_until({ EOS, EOF })!;
			return ctx.ast.error(ctx.current().pos);
		}
	}

	switch (ctx.current().kind)
	{
		case IDENT:
		case CT_IDENT:
		case TYPE_IDENT:
		case CT_TYPE_IDENT:
		case HASH_IDENT:
			break;
		default:
			ctx.error("Expected parameter name");
			ctx.skip_until({ EOS, EOF })!;
			return ctx.ast.error(ctx.current().pos);
	}

	param.name = parse_expr(scope)!;

	if (ctx.is(COLON))
	{
		advance(ctx)!;
		param.description = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
	}
	else if (ctx.is(STRING_LITERAL))
	{
		ctx.error("Expected ':' before string");
		ctx.skip_until({ EOS, EOF })!;
		return ctx.ast.error(ctx.current().pos);
	}

	return node;
}

<*
 param_list ::= ('...' arg | arg (',' arg)*)?
 parameter ::= ((param_path '=')? expr) | param_path
*>
fn NodeArray? parse_arg_list(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	List{Node*} args;
	args.tinit();

	while (!ctx.eof() && !ctx.is(RPAREN))
	{
		int pos_before = ctx.pos;
		Node* expr    = null;
		int start_pos = ctx.current().pos;
		if (ctx.is(RPAREN)) break;

		plog::debug("parse arg - %s", ctx.current_text());

		if (ctx.is(ELLIPSIS) && ctx.can_peek(1) && ctx.peek(1)!.kind == CT_VAARG)
		{
			expr = parse_vasplat_expr(scope)!;
		}
		else
		{
			expr = parse_expr(scope)!;

			if (expr.kind == IDENT_EXPR && consume(ctx, COLON)!)
			{
				IdentExpr* ident  = expr.as(IDENT_EXPR);
				StringID arg_name = ident.ident;

				expr = ctx.ast.alloc_node(NAMED_ARG_EXPR, start_pos);
				NamedArgExpr* named = expr.as(NAMED_ARG_EXPR);
				named.name = arg_name;

				named.value = parse_expr(scope)!;
				expr.offset.end = ctx.current().pos;
			}
			else if (expr.kind == CT_EVAL_EXPR && consume(ctx, COLON)!)
			{
				Node* inner = expr;
				expr = ctx.ast.alloc_node(EVAL_NAMED_ARG_EXPR, start_pos);
				EvalNamedArgExpr* eval_named = expr.as(EVAL_NAMED_ARG_EXPR);

				eval_named.name = inner;
				eval_named.value = parse_expr(scope)!;
				expr.offset.end = ctx.current().pos;
			}
		}

		plog::debug("parse arg AFTER - %s", ctx.current_text());

		args.push(expr);

		if (ctx.pos == pos_before)
        {
            plog::error("Parser loop stalled in argument list at token: %s", ctx.current().kind);
            advance(ctx)!; 
        }

		if (!consume(ctx, COMMA)!) break;
		if (ctx.is(RPAREN)) break;
	}

	return alloc::clone_slice(ctx.arena, args.array_view());
}

<*
 parse short body: =>
 wraps the short body in a compound and a return
*>
fn Node*? parse_short_body(ContextScope scope, bool is_regular)
{
	ParseContext* ctx = scope.ctx;
	int pos         = ctx.current().pos;
	Node* node_comp = ctx.ast.alloc_node(COMPOUND_STMT, pos);
	Node* ret_node  = ctx.ast.alloc_node(RETURN_STMT, pos);

	CompoundStmt* comp = node_comp.as(COMPOUND_STMT);
	ReturnStmt* ret    = ret_node.as(RETURN_STMT);

	comp.statements = alloc::alloc_array(ctx.arena, Node*, 1);
	comp.statements[0] = ret_node;
	
	Node* expr = parse_expr(scope)!;

	if (expr.kind == CALL_EXPR)
	{
		CallExpr* call = expr.as(CALL_EXPR);
		if (call.macro_body_expr)
		{
			is_regular = false;
			call.is_outer_call = true;
			ret_node.kind = EXPR_STMT;
			ExprStmt* ex_stmt = ret_node.as(EXPR_STMT);
			ex_stmt.expr_stmt = expr;
		}
	}
	else
	{
		ret.expr = expr;
	}
	
	if (is_regular)
	{
		expect(ctx, EOS)!;
	}
	
	return node_comp;
}
