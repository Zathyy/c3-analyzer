module c3_parser::parser;

import c3_parser::ast;
import lexer;
import c3_parser::common;

import std::collections::list;

fn uint? parse_label(Parser* p)
{
	if (p.is(TokenKind.CONST_IDENT))
	{
		uint label = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
		expect(p, TokenKind.COLON)!;
		return label;
	}

	return 0;
}

fn Node? parse_statement(Parser* p)
{
	TokenKind kind = p.current().kind;

	log::debug("parse_statement : %s - %s", p.current_text(), kind);

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
			advance(p)!;
			return parse_var_decl(p, { .is_var = true, .is_local = true })!;
		case TokenKind.CONST:
			advance(p)!;
			return parse_var_decl(p, { .is_const = true, .is_local = true })!;
		case TokenKind.RETURN:
			return parse_return(p)!;
		case TokenKind.DEFER:
			return parse_defer(p)!;
		case TokenKind.IF:
			return parse_if(p)!;
		case TokenKind.DO:
			return parse_do_while(p)!;
		case TokenKind.SWITCH:
			return parse_switch(p)!;
		case TokenKind.NEXTCASE:
			return parse_nextcase(p)!;
		case TokenKind.BREAK:
			return parse_break(p)!;
		case TokenKind.CONTINUE:
			return parse_continue_stmt(p)!;
		case TokenKind.FOREACH:
		case TokenKind.FOREACH_R:
			return parse_foreach(p)!;
		case TokenKind.WHILE:
			return parse_while_stmt(p)!;
		case TokenKind.FOR:
			return parse_for_stmt(p)!;
		case TokenKind.ASSERT:
			return parse_assert_stmt(p)!;
		default:
			{
				// if it's not a keyword or type, treat it as a expression statement
				return parse_expr_stmt(p)!;
			}
	}
}

<*
 for_stmt ::= 'for' label? '(' init? ';' cond? ';' incr? ')' statement
  label    ::= ':' IDENT
  init     ::= declaration | expression_list
  cond     ::= expression
  incr     ::= expression_list
*>
fn Node? parse_for_stmt(Parser* p)
{
	uint for_token = p.current_pos();
	expect(p, TokenKind.FOR)!;

	uint label = parse_label(p)!;

	expect(p, TokenKind.LPAREN)!;

	Node init_stmt;
	if (!p.is(TokenKind.EOS))
	{
		init_stmt = parse_statement(p)!;
	}
	else
	{
		expect(p, TokenKind.EOS)!;
	}

	Node cond_expr;
	if (!p.is(TokenKind.EOS))
	{
		cond_expr = parse_expr(p)!;
	}
	expect(p, TokenKind.EOS)!;

	Node incr_expr;
	if (!p.is(TokenKind.RPAREN))
	{
		incr_expr = parse_expr(p)!;
	}
	expect(p, TokenKind.RPAREN)!;
	Node body = parse_statement(p)!;

	uint[*] data = { (uint)init_stmt, (uint)cond_expr, (uint)incr_expr, (uint)body };

	uint ex = ast::push_extra_block(p.ast, &data);
	return ast::add_node(p.ast, NodeKind.FOR_STMT, for_token, p.current_pos(), ex);
}

fn Node? parse_compound(Parser* p)
{
	uint lbrace_tok = p.current_pos();
	expect(p, TokenKind.LBRACE)!;

	// we have to use a list here since we have no idea how many statements could be here
	List{uint} stmts;
	stmts.tinit(100);
	defer stmts.free();

	// push the size
	stmts.push(0);

	while (!p.is(TokenKind.RBRACE) && !p.eof())
	{
		if (p.eof())
		{
			log::error("EOF!!!!!");
		}
		Node stmt = parse_statement(p)!;
		stmts.push((uint)stmt);
	}

	expect(p, TokenKind.RBRACE)!;

	// len - 1 since first one is the size
	stmts[0] = (uint)stmts.len() - 1;
	uint ex = ast::push_extra_block(p.ast, stmts.array_view());

	return ast::add_node(p.ast, NodeKind.COMPOUND_STMT, lbrace_tok, p.current_pos(), ex);
}

fn Node? parse_decl_stmt(Parser* p)
{
	Node type_node = parse_type(p)!;

	if (p.current().kind == TokenKind.IDENT)
	{
		Token name_tok = p.current();
		advance(p)!;

		Node init;
		if (p.current().kind == TokenKind.EQ)
		{
			advance(p)!;
			init = parse_expr(p, { })!;
		}

		uint attr = parse_attributes(p)!;

		expect(p, TokenKind.EOS)!;

		uint name_sh = p.pool.intern(p.token_text(name_tok));
		uint[*] data = { name_sh, (uint)type_node, (uint)init, attr };
		uint ex = ast::push_extra_block(p.ast, &data);
		return ast::add_node(p.ast, NodeKind.LOCAL_DECL, name_tok.pos, p.current_pos(), ex);
	}

	Node expr = parse_expr_resuming_with_left(p, type_node, 0)!;
	expect(p, TokenKind.EOS)!;
	return expr;
}

fn Node? parse_expr_stmt(Parser* p)
{
	log::debug("parse_expr_stmt - %s : %s", p.current_text(), p.current().kind);
	Token t = p.current();
	Node expr = parse_expr(p)!;
	expect(p, TokenKind.EOS)!; // TODO: how should EOS be handled?

	return ast::add_node(p.ast, NodeKind.EXPR_STMT, t.pos, p.current_pos(), (uint)expr);
}

fn Node? parse_return(Parser* p)
{
	Token t = p.current();
	advance(p)!; // consume 'return'

	Node expr;
	if (p.current().kind != TokenKind.EOS)
	{
		expr = parse_expr(p, { })!;
	}

	expect(p, TokenKind.EOS)!;

	return ast::add_node(p.ast, NodeKind.RETURN_STMT, t.pos, p.current_pos(), (uint)expr);
}

fn Node? parse_if(Parser* p)
{
	Token t = p.current();
	advance(p)!; // consume 'if'

	expect(p, TokenKind.LPAREN)!;
	Node cond = parse_expr(p, { })!;
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

	return ast::add_node(p.ast, NodeKind.IF_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_ct_if(Parser* p)
{
	Token t = p.current();
	advance(p)!; // consume $if

	Node condition = parse_expr(p)!;

	expect(p, TokenKind.COLON)!;

	List{uint} then_stmts;
	then_stmts.tinit(16);
	then_stmts.push(0); // len
	defer then_stmts.free();

	while (!p.is(TokenKind.CT_ELSE) && !p.is(TokenKind.CT_ENDIF))
	{
		then_stmts.push((uint)parse_statement(p)!);
	}

	then_stmts[0] = (uint)then_stmts.len() - 1;
	uint ex_then = ast::push_extra_block(p.ast, then_stmts.array_view());
	Node then_block = ast::add_node(p.ast, NodeKind.BLOCK, t.pos, p.current_pos(), ex_then);

	Node else_block;
	if (consume(p, TokenKind.CT_ELSE)!)
	{
		List{uint} else_stmts;
		else_stmts.tinit(16);
		else_stmts.push(0); // len
		defer else_stmts.free();

		while (!p.is(TokenKind.CT_ENDIF) && !p.eof())
		{
			else_stmts.push((uint)parse_statement(p)!);
		}

		else_stmts[0] = (uint)else_stmts.len() - 1;
		uint ex = ast::push_extra_block(p.ast, else_stmts.array_view());
		else_block = ast::add_node(p.ast, NodeKind.BLOCK, t.pos, p.current_pos(), ex);
	}

	expect(p, TokenKind.CT_ENDIF)!;

	if (p.is(TokenKind.EOS))
	{
		advance(p)!;
	}

	uint[3] data = { (uint)condition, (uint)then_block, (uint)else_block };
	uint ex = ast::push_extra_block(p.ast, &data);
	return ast::add_node(p.ast, NodeKind.CT_IF_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_nextcase(Parser* p)
{
	Token t = p.current();
	advance(p)!;

	expect(p, TokenKind.EOS)!;

	return ast::add_node(p.ast, NodeKind.NEXTCASE_STMT, t.pos, p.current_pos(), 0);
}

fn Node? parse_continue_stmt(Parser* p)
{
	Token t = p.current();
	advance(p)!;

	uint label = parse_label(p)!;

	expect(p, TokenKind.EOS)!;

	return ast::add_node(p.ast, NodeKind.CONTINUE_STMT, t.pos, p.current_pos(), label);
}

fn Node? parse_switch(Parser* p)
{
	Token t = p.current();
	advance(p)!;

	expect(p, TokenKind.LPAREN)!;
	Node cond = parse_expr(p, { })!;
	expect(p, TokenKind.RPAREN)!;

	expect(p, TokenKind.LBRACE)!;

	List{uint} cases;
	cases.tinit(16);
	defer cases.free();
	cases.push((uint)cond);

	while (!p.is(TokenKind.RBRACE) && !p.is(TokenKind.EOS))
	{
		cases.push((uint)parse_switch_case(p)!);
	}

	expect(p, TokenKind.RBRACE)!;

	uint ex = ast::push_extra_block(p.ast, cases.array_view());
	return ast::add_node(p.ast, NodeKind.SWITCH_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_switch_case(Parser* p)
{
	Token t = p.current();
	if (consume(p, TokenKind.CASE)!)
	{
		Node label = parse_expr(p, { })!;
		expect(p, TokenKind.COLON)!;

		Node body;
		if (!p.is(TokenKind.CASE) && !p.is(TokenKind.DEFAULT) && !p.is(TokenKind.RBRACE))
		{
			body = parse_statement(p)!;
		}

		uint[*] data = { (uint)label, (uint)body };
		return ast::add_node(p.ast, NodeKind.CASE_STMT, t.pos, p.current_pos(), (uint)body);
	}
	else if (consume(p, TokenKind.DEFAULT)!)
	{
		expect(p, TokenKind.COLON)!;
		Node body = parse_statement(p)!;
		return ast::add_node(p.ast, NodeKind.DEFAULT_STMT, t.pos, p.current_pos(), (uint)body);
	}

	return parse_statement(p)!;
}

fn Node? parse_break(Parser* p)
{
	Token t = p.current();
	advance(p)!;

	expect(p, TokenKind.EOS)!;

	return ast::add_node(p.ast, NodeKind.BREAK_STMT, t.pos, p.current_pos(), 0);
}

fn Node? parse_ct_switch(Parser* p)
{
	Token t = p.current();
	advance(p)!;

	Node condition;
	if (!p.is(TokenKind.COLON))
	{
		condition = parse_expr(p, { })!;
	}

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
	return ast::add_node(p.ast, NodeKind.CT_SWITCH_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_ct_case(Parser* p)
{
	Token t = p.current();
	bool is_default = (t.kind == TokenKind.CT_DEFAULT);
	advance(p)!;

	Node label;
	if (!is_default)
	{
		label = parse_expr(p, { })!;
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
	return ast::add_node(p.ast, NodeKind.CT_CASE_STMT, t.pos, p.current_pos(), ex);
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
		cond = parse_expr(p, { })!;
		expect(p, TokenKind.RPAREN)!;

		expect(p, TokenKind.EOS)!;
	}

	uint[2] data = { (uint)body, (uint)cond };
	uint ex = ast::push_extra_block(p.ast, &data);
	return ast::add_node(p.ast, NodeKind.DO_WHILE_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_foreach_var(Parser* p)
{
	uint start_tok = p.current_pos();
	Node var_type;
	bool is_ref = false;

	if (is_type(p.current().kind)
		&& (p.peek(1).kind == TokenKind.IDENT || p.peek(1).kind == TokenKind.AMP
			|| p.peek(1).kind == TokenKind.ASTERISK))
	{
		var_type = parse_type(p)!;
	}

	if (consume(p, TokenKind.AMP)!) is_ref = true;

	Token t = p.current();
	expect(p, TokenKind.IDENT)!;
	uint name = p.pool.intern(p.token_text(t));

	uint[3] data = { (uint)var_type, name, is_ref ? 1 : 0 };
	uint ex = ast::push_extra_block(p.ast, &data);

	return ast::add_node(p.ast, NodeKind.FOREACH_VAR, t.pos, p.current_pos(), ex);
}

fn Node? parse_foreach(Parser* p)
{
	uint start_tok = p.current_pos();
	bool is_reverse = consume(p, TokenKind.FOREACH_R)!;
	if (!is_reverse) expect(p, TokenKind.FOREACH)!;

	uint label = 0;
	if (p.current().kind == TokenKind.CONST_IDENT && p.peek(1).kind == TokenKind.COLON)
	{
		Token t = p.current();
		label = p.pool.intern(p.token_text(t));
		advance(p)!; // ident
		advance(p)!; // colon
	}

	expect(p, TokenKind.LPAREN)!;

	uint[2] vars;
	vars[0] = (uint)parse_foreach_var(p)!;

	// if there is another var, then we flip the array
	// so if vars[1] != 0, then: vars[0] = index & vars[1] = variable
	// else vars[0] = variable
	if (consume(p, TokenKind.COMMA)!)
	{
		vars[1] = vars[0];
		vars[0] = (uint)parse_foreach_var(p)!;
	}

	expect(p, TokenKind.COLON)!;
	Node iterable = parse_expr(p, { })!;
	expect(p, TokenKind.RPAREN)!;

	Node body = parse_statement(p)!;

	uint[*] data = { label, vars[0], // index
	vars[1], // variable
	(uint)iterable, (uint)body };
	uint ex = ast::push_extra_block(p.ast, &data);

	return ast::add_node(
		p.ast,
		is_reverse ? NodeKind.FOREACH_R_STMT : NodeKind.FOREACH_STMT,
		start_tok,
		p.current_pos(),
		ex
	);
}

fn Node? parse_while_stmt(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, TokenKind.WHILE)!;

	uint label;
	if (p.is(TokenKind.CONST_IDENT))
	{
		label = p.pool.intern(p.token_text(p.current()));
	}

	expect(p, TokenKind.LPAREN)!;
	Node condition = parse_expr(p, { })!;
	expect(p, TokenKind.RPAREN)!;

	Node body = parse_statement(p)!;

	uint[*] data = { label, (uint)condition, (uint)body };
	uint ex = ast::push_extra_block(p.ast, &data);
	return ast::add_node(p.ast, NodeKind.WHILE_STMT, start_tok, p.current_pos(), ex);
}

fn Node? parse_defer(Parser* p)
{
	uint start_tok = p.current_pos();
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

	return ast::add_node(p.ast, NodeKind.DEFER_STMT, start_tok, p.current_pos(), ex);
}

fn Node? parse_assert_stmt(Parser* p)
{
    Token t = p.current();
    expect(p, TokenKind.ASSERT)!;
    expect(p, TokenKind.LPAREN)!;

    Node cond = parse_expr(p)!;

    Node message;
    List{uint} args;
    bool has_msg = false;

    // optional message: assert(cond, "message", ...)
    if (consume(p, TokenKind.COMMA)!)
    {
        has_msg = true;
        message = parse_expr(p, Precedence.LOWEST)!;

        while (consume(p, TokenKind.COMMA)!)
        {
            if (args.len() == 0) args.tinit(4);
            Node arg = parse_expr(p, Precedence.LOWEST)!;
            args.push((uint)arg);
        }
    }

    expect(p, TokenKind.RPAREN)!;

    List{uint} data;
    data.tinit(4 + args.len());
    data.push((uint)cond);
    data.push((uint)message);
    data.push((uint)args.len());
    if (args.len() > 0)
    {
        for (uint i = 0; i < args.len(); i++) 
		{
			data.push(args[i]);
		}
    }
    defer args.free();
    defer data.free();

    expect(p, TokenKind.EOS)!;

    uint ex = ast::push_extra_block(p.ast, data.array_view());
    return ast::add_node(p.ast, NodeKind.ASSERT_STMT, t.pos, p.current_pos(), ex);
}