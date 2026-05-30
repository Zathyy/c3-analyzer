module parser::parser;

import parser::ast;
import lexer;
import parser::constants;

import std::collections::list;

fn Node*? parse_stmt(ParseContext* ctx)
{
	Token t = ctx.current();
	switch (t.kind)
	{
		case LBRACE:
			return parse_compound_stmt(ctx)!;
		default:
			break;
	}

	ctx.error("Unhandled statement (%s)", t.kind.description);
	return ctx.ast.error(t.pos);
}

<*
 compound_stmt ::= ('{' stmt* '}')
*>
fn Node*? parse_compound_stmt(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	if (!expect(ctx, LBRACE)!)
	{
		ctx.error("Expected opening '{'");
		return ctx.ast.error(start_pos);
	}

	Node* node          = ctx.ast.alloc_node(COMPOUND_STMT, start_pos);
	CompoundStmt* block = node.as(COMPOUND_STMT);
	defer node.end_token = ctx.peek(0).pos;

	List{Node*} temp_stmts;
	temp_stmts.init(tmem, 8);

	while (!ctx.is(RBRACE) && !ctx.eof())
	{
		Node*? stmt = parse_stmt(ctx);
		if (catch stmt)
		{
			ctx.error("Malformed statement inside block");
			Node* err_node = ctx.ast.error(ctx.peek(0).pos);
			temp_stmts.push(err_node);
			ctx.skip_until({ RBRACE, EOS })!;
			continue;
		}

		if (stmt != null)
		{
			temp_stmts.push(stmt);
		}
	}

	if (!expect(ctx, RBRACE)!)
	{
		node.kind = MISSING;
	}

	block.statements = alloc::clone_slice(ctx.arena, temp_stmts.array_view());

	return node;
}