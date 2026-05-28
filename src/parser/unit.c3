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
		return {ctx.ast.alloc_node(ERROR, start_pos)};
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