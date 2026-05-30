<*
 unit.c3 - parsing things which arent any of (Decl, Stmt, Expr)
*>
module parser::parser;

import parser::ast;
import lexer;

import std::io;
import std::collections::list;

<*
	parameter_list ::= (param_decl (',' param_decl)*)?
*>
fn NodeArray? parse_parameter_list(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;

	if (!expect(ctx, LPAREN)!)
	{
		return {ctx.ast.error(start_pos)};
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
        Node* param = parse_param_decl(ctx)!;
        temp_params.push(param);

        if (!consume(ctx, COMMA)!) break;

        if (ctx.is(RPAREN))
        {
            ctx.error("Expected parameter declaration after ','");
            temp_params.push(ctx.ast.alloc_node(MISSING, ctx.peek(0).pos));
            break;
        }
    }

	if (!expect(ctx, RPAREN)!)
	{
		//TODO!
	}

	return alloc::clone_slice(ctx.arena, temp_params.array_view());
}

<*
    generic_param_list ::= '{' expr ( ',' expr )* '}'
*>
fn NodeArray? parse_generics_list(ParseContext* ctx)
{
    if (!consume(ctx, LBRACE)!) return {};
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
        return {};
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
