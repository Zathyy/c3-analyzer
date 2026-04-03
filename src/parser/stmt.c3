module c3_parser::parser;

import c3_parser::ast;
import lexer;
import c3_parser::common;

import std::collections::list;

fn Node? parse_statement(Parser* p)
{
	TokenKind kind = p.current().kind;

	if (is_type(kind))
    {
        return parse_decl_stmt(p);
    }

	switch (kind)
	{
		case TokenKind.LBRACE:
			return parse_compound(p)!;
		case TokenKind.VAR:
			return parse_decl_stmt(p)!;
		case TokenKind.RETURN:
			return parse_return(p)!;
		case TokenKind.DEFER:
			return parse_defer(p)!;
		case TokenKind.IF:
			return parse_if(p)!;
		default:
		{	
			// if it's not a keyword or type, treat it as a expression statement
			return parse_expr_stmt(p)!;
		}
	}
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
    Node cond_expr = parse_expr(p)!; // e.g., i < 10;
    expect(p, TokenKind.EOS)!;
    Node inc_expr  = parse_expr(p)!; // e.g., i++
    
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

	// we have to use a list here since we have no idea how many statements could be here
	List{ uint } stmts;
	stmts.tinit(100);
	defer stmts.free();

	// push the size
	stmts.push(0);

    while (!p.is(TokenKind.RBRACE) && !p.eof())
    {
        Node stmt = parse_statement(p)!;
		stmts.push((uint)stmt);
    }

    expect(p, TokenKind.RBRACE)!;

	// len - 1 since first one is the size
	stmts[0] = (uint)stmts.len() - 1;
	uint ex = ast::push_extra_block(p.ast, stmts.array_view());

    return ast::add_node(p.ast, NodeKind.COMPOUND_STMT, lbrace_tok, ex);
}

fn Node? parse_decl_stmt(Parser* p)
{
    Node type_node = parse_type(p)!;
	Token name_tok = p.current();
    expect(p, TokenKind.IDENT)!;
    uint name_sh = p.pool.intern(p.token_text(name_tok));

    Node init_expr;

    if (p.current().kind == TokenKind.EQ)
    {
        advance(p)!;
        init_expr = parse_expr(p, 0)!; 
    }

    expect(p, TokenKind.EOS)!;

    uint[3] data = { (uint)type_node, name_sh, (uint)init_expr };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.VAR_DECL_STMT, name_tok.pos, ex);
}

fn Node? parse_expr_stmt(Parser* p)
{
    Token t = p.current();
    Node expr = parse_expr(p, 0)!;
    (void)expect(p, TokenKind.EOS); // TODO: how should EOS be handled?

    return ast::add_node(p.ast, NodeKind.EXPR_STMT, t.pos, (uint)expr);
}

fn Node? parse_return(Parser* p)
{
    Token t = p.current();
    advance(p)!; // consume 'return'

    Node expr;
    if (p.current().kind != TokenKind.EOS)
    {
        expr = parse_expr(p, 0)!;
    }
    expect(p, TokenKind.EOS)!;

    return ast::add_node(p.ast, NodeKind.RETURN_STMT, t.pos, (uint)expr);
}

fn Node? parse_if(Parser* p)
{
    Token t = p.current();
    advance(p)!; // consume 'if'

    expect(p, TokenKind.LPAREN)!;
    Node cond = parse_expr(p, 0)!;
    expect(p, TokenKind.RPAREN)!;

    // Parse the "then" branch
    Node then_block = parse_statement(p)!;
    Node else_block;

    // Check for optional "else"
    if (p.current().kind == TokenKind.ELSE)
    {
        advance(p)!; // consume 'else'
        // This handles "else if" automatically because parse_statement 
        // will see the 'if' and call this function recursively.
        else_block = parse_statement(p)!;
    }

    uint[3] data = { (uint)cond, (uint)then_block, (uint)else_block };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.IF_STMT, t.pos, ex);
}

fn Node? parse_defer(Parser* p)
{
    uint start_tok = p.pos;
    expect(p, TokenKind.DEFER)!;

    DeferKind kind = DeferKind.NORMAL;
    uint var_name = 0;

    // (TRY | CATCH | '(' CATCH var ')')?
    if (consume(p, TokenKind.TRY)!) 
    {
        kind = DeferKind.TRY;
    } 
    else if (consume(p, TokenKind.CATCH)!) 
    {
        kind = DeferKind.CATCH;
    } 
    else if (p.is(TokenKind.LPAREN) && p.peek(1).kind == TokenKind.CATCH) 
    {
		advance(p)!; // (
        advance(p)!; // catch
        
        if (!p.is(TokenKind.IDENT)) 
        {
            p.error("Expected variable name after 'catch'");
            return UNEXPECTED_TOKEN~;
        }
        
        var_name = p.pool.intern(p.token_text(p.current()));
        advance(p)!;
        
        expect(p, TokenKind.RPAREN)!;
        kind = DeferKind.CATCH_VAR;
    }

    Node stmt = parse_statement(p)!;

    // Extra Block Layout: [Kind, StmtNode, VarName]
    uint[3] data = { (uint)kind, (uint)stmt, var_name };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.DEFER_STMT, start_tok, ex);
}