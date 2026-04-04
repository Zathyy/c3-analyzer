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
		case TokenKind.CT_IF:
            return parse_ct_if(p)!;
		case TokenKind.CT_SWITCH:
			return parse_ct_switch(p)!;
		case TokenKind.LBRACE:
			return parse_compound(p)!;
		case TokenKind.VAR:
			return parse_var_decl(p)!;
		case TokenKind.RETURN:
			return parse_return(p)!;
		case TokenKind.DEFER:
			return parse_defer(p)!;
		case TokenKind.IF:
			return parse_if(p)!;
		case TokenKind.DO:
			return parse_do_while(p)!;
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

    if (p.current().kind == TokenKind.IDENT)
    {
        Token name_tok = p.current();
        advance(p)!;

        Node init = 0;
        if (p.current().kind == TokenKind.EQ)
        {
            advance(p)!;
            init = parse_expr(p, 0)!;
        }
        expect(p, TokenKind.EOS)!;

        uint name_sh = p.pool.intern(p.token_text(name_tok));
        uint[*] data = { name_sh, (uint)type_node, (uint)init };
        uint ex = ast::push_extra_block(p.ast, &data);
        return ast::add_node(p.ast, NodeKind.LOCAL_DECL, name_tok.pos, ex);
    }

    Node expr = parse_expr_resuming_with_left(p, type_node, 0)!;
    expect(p, TokenKind.EOS)!;
    return expr;
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

fn Node? parse_ct_if(Parser* p)
{
    Token t = p.current();
    advance(p)!; // consume $if

    Node condition = parse_expr(p, 0)!;
    
    expect(p, TokenKind.COLON)!; 

    Node then_block = parse_statement(p)!;
    Node else_block;

    if (p.current().kind == TokenKind.CT_ELSE)
    {
        advance(p)!;
        else_block = parse_statement(p)!;
    }

	expect(p, TokenKind.CT_ENDIF)!;

    uint[3] data = { (uint)condition, (uint)then_block, (uint)else_block };
    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, NodeKind.CT_IF_STMT, t.pos, ex);
}

fn Node? parse_ct_switch(Parser* p)
{
    Token t = p.current();
    advance(p)!;

    Node condition = parse_expr(p, 0)!;

    expect(p, TokenKind.COLON)!;

    // Parse the body until $endswitch
    List{uint} cases;
    cases.tinit(16);
    defer cases.free();

    while (p.current().kind != TokenKind.CT_ENDSWITCH && p.current().kind != TokenKind.EOF)
    {
        TokenKind k = p.current().kind;
        if (k == TokenKind.CT_CASE || k == TokenKind.CT_DEFAULT)
        {
            cases.push((uint)parse_ct_case(p)!);
        }
        else
        {
            Node n = parse_statement(p)!;
            cases.push((uint)n);
        }
    }

    expect(p, TokenKind.CT_ENDSWITCH)!;

    uint[2] data = { (uint)condition, (uint)ast::push_extra_block(p.ast, cases.array_view()) };
    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, NodeKind.CT_SWITCH_STMT, t.pos, ex);
}

fn Node? parse_ct_case(Parser* p)
{
    Token t = p.current();
    bool is_default = (t.kind == TokenKind.CT_DEFAULT);
    advance(p)!;

    Node label = 0;
    if (!is_default)
    {
        label = parse_expr(p, 0)!;
    }

    expect(p, TokenKind.COLON)!;

    List{uint} body;
    body.tinit(8);
    while (true)
    {
        TokenKind k = p.current().kind;
        if (k == TokenKind.CT_CASE || k == TokenKind.CT_DEFAULT || k == TokenKind.CT_ENDSWITCH || k == TokenKind.EOF)
        {
            break;
        }
        body.push((uint)parse_statement(p)!);
    }

    uint[2] data = { (uint)label, (uint)ast::push_extra_block(p.ast, body.array_view()) };
    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, NodeKind.CT_CASE_STMT, t.pos, ex);
}

fn Node? parse_do_while(Parser* p)
{
    Token t = p.current();
    advance(p)!; // consume 'do'

	Node cond;
    Node body = parse_statement(p)!;

	if (!consume(p, TokenKind.EOS)!)
	{
		expect(p, TokenKind.WHILE)!;

		expect(p, TokenKind.LPAREN)!;
		cond = parse_expr(p, 0)!;
		expect(p, TokenKind.RPAREN)!;

		expect(p, TokenKind.EOS)!;
	}

    uint[2] data = { (uint)body, (uint)cond };
    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, NodeKind.DO_WHILE_STMT, t.pos, ex);
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