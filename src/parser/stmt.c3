module c3_parser::parser;

import c3_parser::ast;
import lexer;
import c3_parser::common;

import std::collections::list;

fn Node? parse_statement(Parser* p)
{
	unreachable("not implemented");
}

fn Node? parse_for_statement(Parser* p)
{
    uint for_token = p.pos;
    expect(p, TokenKind.FOR)!;

	if (!consume(p, TokenKind.LPAREN)!) 
	{
		p.error("Expected '(' to open for-loop header, found '%s'", p.current().kind);
		return UNEXPECTED_TOKEN~;
	}

    // Parse the three headers
    Node init_stmt = parse_statement(p)!; // e.g., int i = 0;
    expect(p, TokenKind.EOS)!;
    Node cond_expr = parse_expression(p)!; // e.g., i < 10;
    expect(p, TokenKind.EOS)!;
    Node inc_expr  = parse_expression(p)!; // e.g., i++
    
	if (!consume(p, TokenKind.RPAREN)!) 
	{
		p.error("Expected ')' to close for-loop header, found '%s'", p.current().kind);
		return UNEXPECTED_TOKEN~;
	}
    Node body = parse_statement(p)!;

    uint[] data = { 
        (uint)init_stmt, 
        (uint)cond_expr, 
        (uint)inc_expr, 
        (uint)body 
    };
    uint ex = ast::push_extra_block(p.ast, data);

    return ast::add_node(p.ast, NodeKind.FOR_STMT, for_token, ex);
}

fn Node? parse_compound(Parser* p)
{
    uint lbrace_tok = p.pos;
    expect(p, TokenKind.LBRACE)!;

    List{Node} statements;
    statements.tinit(8); 
    defer statements.free();

    while (!p.is(TokenKind.RBRACE) && !p.eof())
    {
        Node stmt = parse_statement(p)!;
        statements.push(stmt);
    }

    expect(p, TokenKind.RBRACE)!;

    uint count = (uint)statements.len();
    
    uint ex = ast::reserve_extra(p.ast, 1 + count);
    
    p.ast.extra_data[ex] = count;
    for (uint i = 0; i < count; i++)
    {
        p.ast.extra_data[(usz)ex + 1 + i] = (uint)statements[i];
    }

    return ast::add_node(p.ast, NodeKind.COMPOUND_STMT, lbrace_tok, ex);
}