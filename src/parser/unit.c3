<*
 unit.c3 - parsing things which arent any of (Decl, Stmt, Expr)
*>
module parser::parser;

import parser::ast;
import parser::common;
import lexer;

import std::io;
import std::collections::list;

<*
	parameter_list ::= (param_decl (',' param_decl)*)?
*>
fn NodeArray? parse_parameter_list(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;

	List{Node*} temp_params;
    temp_params.init(tmem, 4);

	if (ctx.is(RPAREN))
    {
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

	return alloc::clone_slice(ctx.arena, temp_params.array_view());
}