<*
 unit.c3 - parsing things which arent any of (Decl, Stmt, Expr)
*>
module parser::parser;
import parser::plog;

import parser::ast;
import lexer;

import std::io;
import std::collections::list;

<*
 parameter_list ::= (param_decl (',' param_decl)*)?
*>
fn NodeArray? parse_parameter_list(ParseContext* ctx, ParamParseFlags flags = { }) => @pool()
{
	int start_pos = ctx.peek(0).pos;

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
		Node* param = parse_param_decl(ctx, flags)!;
		temp_params.push(param);

		if (!consume(ctx, COMMA)!) break;

		if (ctx.is(RPAREN))
		{
			temp_params.push(unexpected_at(ctx, ctx.current(), "Expected parameter declaration after ','")!);
			break;
		}
	}
	if (!flags.is_call)
	{
		expect(ctx, RPAREN)!;
	}
	return alloc::clone_slice(ctx.arena, temp_params.array_view());
}

<*
 generic_param_list ::= '{' expr ( ',' expr )* '}'
*>
fn NodeArray? parse_generics_list(ParseContext* ctx)
{
	if (!consume(ctx, LBRACE)!) return { };
	List{Node*} params;
	params.init(tmem, 4);

	while (true)
	{
		if (ctx.is(RBRACE)) break;
		Node* param = parse_expr(ctx)!;
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

fn Node*? parse_contract_param(ParseContext* ctx)
{
	int start = ctx.current().pos;

	Node* node = ctx.ast.alloc_node(CONTRACT_PARAM, start);
	defer node.end_token = ctx.current().pos;
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
			break;
		default:
			ctx.error("Expected parameter name");
			ctx.skip_until({ EOS, EOF })!;
			return ctx.ast.error(ctx.current().pos);
	}

	param.name = parse_expr(ctx)!;

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
fn NodeArray? parse_arg_list(ParseContext* ctx) => @pool()
{
	List{Node*} args;
	args.tinit();

	while (true)
	{
		Node* expr    = null;
		int start_pos = ctx.peek(0).pos;

		if (ctx.is(ELLIPSIS) && ctx.can_peek(1) && ctx.peek(1).kind == CT_VAARG)
		{
			expr = parse_vasplat_expr(ctx)!;
		}
		else
		{
			expr = parse_expr(ctx)!;

			if (expr.kind == IDENT_EXPR && consume(ctx, COLON)!)
			{
				IdentExpr* ident  = expr.as(IDENT_EXPR);
				StringID arg_name = ident.ident;

				expr = ctx.ast.alloc_node(NAMED_ARG_EXPR, start_pos);
				NamedArgExpr* named = expr.as(NAMED_ARG_EXPR);
				named.name = arg_name;

				named.value = parse_expr(ctx)!;
				expr.end_token = ctx.peek(0).pos;
			}
			else if (expr.kind == CT_EVAL_EXPR && consume(ctx, COLON)!)
			{
				Node* inner = expr;
				expr = ctx.ast.alloc_node(EVAL_NAMED_ARG_EXPR, start_pos);
				EvalNamedArgExpr* eval_named = expr.as(EVAL_NAMED_ARG_EXPR);

				eval_named.name = inner;
				eval_named.value = parse_expr(ctx)!;
				expr.end_token = ctx.peek(0).pos;
			}
		}

		args.push(expr);

		if (!consume(ctx, COMMA)!) break;
		if (ctx.is(RPAREN)) break;
	}

	return alloc::clone_slice(ctx.arena, args.array_view());
}
