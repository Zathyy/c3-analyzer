module c3_parser::parser;

import c3_parser::ast;
import lexer;
import c3_parser::common;
import c3_parser::constants;

import std::collections::list;

fn uint? parse_label(Parser* p, bool check_for_colon = false)
{
	if (p.is(CONST_IDENT))
	{
		uint label = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
		if (check_for_colon)
		{
			if (!consume(p, COLON)!)
			{
				p.error("Expected colon after label");
			}
		}
		return label;
	}

	return 0;
}

fn Node? parse_statement(Parser* p)
{
	TokenKind kind = p.current().kind;

	log::debug("parse_statement : %s - %s", p.current_text(), kind);

	if (is_type(p)
		|| kind == TLOCAL 
		|| kind == STATIC)
	{
		return parse_decl_stmt(p);
	}

	switch (kind)
	{
		case CT_IF:
			return parse_ct_if(p)!;
		case CT_SWITCH:
			return parse_ct_switch(p)!;
		case CT_FOREACH:
			return parse_ct_foreach(p)!; 
		case LBRACE:
			return parse_compound(p)!;
		case VAR:
			return parse_var_decl(p, { .is_var = true, .is_local = true })!;
		case CONST:
			advance(p)!;
			return parse_var_decl(p, { .is_const = true, .is_local = true })!;
		case STATIC:
			advance(p)!;
			return parse_var_decl(p, { .is_static = true, .is_local = true })!;
		case RETURN:
			return parse_return(p)!;
		case DEFER:
			return parse_defer(p)!;
		case IF:
			return parse_if(p)!;
		case DO:
			return parse_do_while(p)!;
		case SWITCH:
			return parse_switch(p)!;
		case NEXTCASE:
			return parse_nextcase(p)!;
		case BREAK:
			return parse_break(p)!;
		case CONTINUE:
			return parse_continue_stmt(p)!;
		case FOREACH:
		case FOREACH_R:
			return parse_foreach(p)!;
		case WHILE:
			return parse_while_stmt(p)!;
		case FOR:
			return parse_for_stmt(p)!;
		case CT_FOR:
			return parse_ct_for_stmt(p)!;
		case ASSERT:
			return parse_assert_stmt(p)!;
		case CT_ASSERT:
		case CT_ERROR:
			return parse_ct_assert(p);
		case CT_ECHO:
			uint token_pos = p.current_pos();
			advance(p)!;
			Node expr = parse_constant_expr(p)!;
			return p.ast.add_node(CT_ECHO_STMT, token_pos, p.current_pos(), (uint)expr);
		case ASM:
			return parse_asm_block_stmt(p)!;
		case EOS:
			uint token_pos = p.current_pos();
			advance(p)!;
			return p.ast.add_node(NOP_STMT, token_pos, token_pos, 0);
		default:
			{
				// if it's not a keyword or type, treat it as a expression statement
				return parse_expr_stmt(p)!;
			}
	}
}

<*
	ct_error_stmt ::= CT_ERROR constant_expression (',' constant_expression)* ';'
*>
fn Node? parse_ct_assert(Parser* p)
{
	uint start_pos = p.current().pos;
	advance(p)!;

	Node cond = parse_constant_expr(p)!;
	Node message;
	uint args;

	if (consume(p, COLON)!)
	{
		message = parse_constant_expr(p)!;

		@with_scratch(; watermark)
		{
			while (consume(p, COMMA)!)
			{
				scratch.push((uint)parse_constant_expr(p)!);
			}
			uint count = (uint)scratch.len() - watermark;
			args = p.ast.push_extra_list(scratch_view(watermark, count));
		};
	}
	expect(p, EOS)!;

	uint[*] data = views::@data{CtAssertViewFields}
	(
		COND, cond,
		MESSAGE, message,
		ARGS, args,
	);

	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(CT_ASSERT_STMT, start_pos, p.current_pos(), ex);
}

fn Node? parse_for_stmt(Parser* p)
{
	uint for_token = p.current_pos();
	expect(p, FOR)!;

	uint label = parse_label(p, true)!;

	expect(p, LPAREN)!;

	Node init;
	if (!p.is(EOS))
	{
		init = parse_expr_list(p)!;
	}
	expect(p, EOS)!;

	Node cond_expr;
	if (!p.is(EOS))
	{
		cond_expr = parse_expr(p)!;
	}
	expect(p, EOS)!;

	Node incr_expr;
	if (!p.is(RPAREN))
	{
		incr_expr = parse_expr_list(p)!;
	}
	expect(p, RPAREN)!;
	Node body = parse_statement(p)!;

	uint[*] data = { (uint)init, (uint)cond_expr, (uint)incr_expr, (uint)body };

	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(FOR_STMT, for_token, p.current_pos(), ex);
}

// TODO: needs eos refinement
fn Node? parse_ct_for_stmt(Parser* p)
{
	uint start_pos = p.current().pos;
	advance(p)!;

	Node init;
	Node cond;
	Node incr;

	if (!p.is(EOS))
	{
		init = parse_ct_expr_list(p)!; 
	}

	consume(p, EOS)!;

	cond = parse_expr(p)!;

	consume(p, EOS)!;

	if (!p.is(COLON))
	{
		incr = parse_ct_expr_list(p)!;
	}

	expect(p, COLON)!;

	uint stmts;
	@with_scratch(; watermark)
	{
		while (!p.is(CT_ENDFOR) && !p.eof())
		{
			Node stmt = parse_statement(p)!;
			scratch.push((uint)stmt);
		}

		uint count = (uint)scratch.len() - watermark;
		stmts = p.ast.push_extra_list(scratch_view(watermark, count));
	};

	expect(p, CT_ENDFOR)!;

	uint[4] final_data = {
		(uint)init,
		(uint)cond,
		(uint)incr,
		stmts
	};

	uint ex = p.ast.push_extra_block(&final_data); 
	return p.ast.add_node(CT_FOR_STMT, start_pos, p.current_pos(), ex);
}

<*
	parses all statments within a { ... }
*>
fn Node? parse_compound(Parser* p) => @with_scratch(; watermark)
{
	uint lbrace_tok = p.current_pos();
	expect(p, LBRACE)!;

	while (!p.is(RBRACE) && !p.eof())
	{
		Node stmt = parse_statement(p)!;
		scratch.push((uint)stmt);
	}

	expect(p, RBRACE)!;

	uint count = (uint)scratch.len() - watermark;
	uint ex = p.ast.push_extra_list(scratch_view(watermark, count));
	return p.ast.add_node(COMPOUND_STMT, lbrace_tok, p.current_pos(), ex);
}

fn Node? parse_decl_stmt(Parser* p)
{
	uint token_pos = p.current_pos();

	ParseFlags flags;
	if (consume(p, STATIC)!)
	{
		flags.is_static = true;
	}
	if (consume(p, TLOCAL)!)
	{
		flags.is_tlocal = true;
	}

	Node type_node = parse_type(p)!;

	TokenKind kind;
	switch (kind = p.current().kind) 
	{
		case IDENT:
		case CT_IDENT:
			return parse_local(p, token_pos, type_node, flags);

		default:
	}

	Node expr = parse_expr_resuming_with_left(p, type_node, 0)!;
	expect(p, EOS)!;
	return expr;
}

fn Node? parse_expr_stmt(Parser* p)
{
	log::debug("parse_expr_stmt - %s : %s", p.current_text(), p.current().kind);
	Token t = p.current();
	Node expr = parse_expr(p)!;
	expect(p, EOS)!; // TODO: how should EOS be handled?

	return p.ast.add_node(EXPR_STMT, t.pos, p.current_pos(), (uint)expr);
}

fn Node? parse_return(Parser* p)
{
	Token t = p.current();
	advance(p)!; // consume 'return'

	Node expr;
	if (p.current().kind != EOS)
	{
		expr = parse_expr(p, { })!;
	}

	expect(p, EOS)!;

	return p.ast.add_node(RETURN_STMT, t.pos, p.current_pos(), (uint)expr);
}

fn Node? parse_if(Parser* p)
{
	Token t = p.current();
	advance(p)!; // consume 'if'

	uint label = parse_label(p, true)!;

	expect(p, LPAREN)!;
	Node cond = parse_cond(p)!;
	expect(p, RPAREN)!;

	// Parse the "then" branch
	Node then_block = parse_statement(p)!;
	Node else_block;

	// Check for optional "else"
	if (p.current().kind == ELSE)
	{
		advance(p)!; // consume 'else'
		// This handles "else if" automatically because parse_statement
		// will see the 'if' and call this function recursively.
		else_block = parse_statement(p)!;
	}

	uint[*] data = views::@data{IfViewFields}
	(
		CONDITION, cond,
		LABEL, label,
		THEN_BLOCK, then_block,
		ELSE_BLOCK, else_block,
	);

	uint ex = p.ast.push_extra_block(&data);

	return p.ast.add_node(IF_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_ct_if(Parser* p)
{
	Token t = p.current();
	advance(p)!; // consume $if

	Node condition = parse_expr(p)!;

	expect(p, COLON)!;

	List{uint} then_stmts;
	then_stmts.tinit(16);
	then_stmts.push(0); // len
	defer then_stmts.free();

	while (!p.is(CT_ELSE) && !p.is(CT_ENDIF))
	{
		then_stmts.push((uint)parse_statement(p)!);
	}

	then_stmts[0] = (uint)then_stmts.len() - 1;
	uint ex_then = p.ast.push_extra_list(then_stmts.array_view());
	Node then_block = p.ast.add_node(BLOCK, t.pos, p.current_pos(), ex_then);

	Node else_block;
	if (consume(p, CT_ELSE)!)
	{
		List{uint} else_stmts;
		else_stmts.tinit(16);
		else_stmts.push(0); // len
		defer else_stmts.free();

		while (!p.is(CT_ENDIF) && !p.eof())
		{
			else_stmts.push((uint)parse_statement(p)!);
		}

		else_stmts[0] = (uint)else_stmts.len() - 1;
		uint ex = p.ast.push_extra_list(else_stmts.array_view());
		else_block = p.ast.add_node(BLOCK, t.pos, p.current_pos(), ex);
	}

	expect(p, CT_ENDIF)!;

	if (p.is(EOS))
	{
		advance(p)!;
	}

	uint[3] data = { (uint)condition, (uint)then_block, (uint)else_block };
	uint ex = p.ast.push_extra_list(&data);
	return p.ast.add_node(CT_IF_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_nextcase(Parser* p)
{
	Token t = p.current();
	advance(p)!;

	Node expr;
	if (!p.is(EOS))
	{
		expr = parse_expr(p)!;
	}
	else
	{
		expr = p.ast.add_empty(t.pos);
	}

	expect(p, EOS)!;

	return p.ast.add_node(NEXTCASE_STMT, t.pos, p.current_pos(), 0);
}

fn Node? parse_continue_stmt(Parser* p)
{
	Token t = p.current();
	advance(p)!;

	uint label = parse_label(p)!;

	expect(p, EOS)!;

	return p.ast.add_node(CONTINUE_STMT, t.pos, p.current_pos(), label);
}

fn Node? parse_switch(Parser* p)
{
	Token t = p.current();
	advance(p)!;
	
	Node cond;
	if (consume(p, LPAREN)!)
	{
		cond = parse_expr(p)!;
		expect(p, RPAREN)!;	
	}

	expect(p, LBRACE)!;

	uint cases;
	@with_scratch(; watermark)
	{
		while (!p.is(RBRACE) && !p.is(EOS))
		{
			scratch.push((uint)parse_switch_case(p)!);
		}

		uint count = (uint)scratch.len() - watermark;
		cases = p.ast.push_extra_list(scratch_view(watermark, count));
	};

	expect(p, RBRACE)!;

	uint[2] final_data = {
		(uint)cond,
		cases
	};

	uint ex = p.ast.push_extra_block(&final_data);
	return p.ast.add_node(SWITCH_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_switch_case(Parser* p)
{
	Token t = p.current();
	if (consume(p, CASE)!)
	{
		Node label = parse_expr(p)!;
		Node range_end;

		if (consume(p, DOTDOT)!)
		{
			range_end = parse_expr(p)!;
		}

		expect(p, COLON)!;

		uint stmts;
        @with_scratch(; watermark)
        {
            while (!p.is(CASE) && !p.is(DEFAULT) && !p.is(RBRACE) && !p.eof())
            {
                Node stmt = parse_statement(p)!;
                scratch.push((uint)stmt);
            }
            uint count = (uint)scratch.len() - watermark;
            stmts = p.ast.push_extra_list(scratch_view(watermark, count));
        };

		uint[*] data = { (uint)label, (uint)range_end, stmts };
		uint ex = p.ast.push_extra_block(&data);
		return p.ast.add_node(CASE_STMT, t.pos, p.current_pos(), ex);
	}
	else if (consume(p, DEFAULT)!)
	{
		expect(p, COLON)!;
		uint stmts;
        @with_scratch(; watermark)
        {
            while (!p.is(CASE) && !p.is(DEFAULT) && !p.is(RBRACE) && !p.eof())
            {
                Node stmt = parse_statement(p)!;
                scratch.push((uint)stmt);
            }
            uint count = (uint)scratch.len() - watermark;
            stmts = p.ast.push_extra_list(scratch_view(watermark, count));
        };
		return p.ast.add_node(DEFAULT_STMT, t.pos, p.current_pos(), stmts);
	}

	return parse_statement(p)!;
}

fn Node? parse_break(Parser* p)
{
	Token t = p.current();
	advance(p)!;

	uint label = parse_label(p)!;

	expect(p, EOS)!;

	return p.ast.add_node(BREAK_STMT, t.pos, p.current_pos(), label);
}

fn Node? parse_ct_switch(Parser* p)
{
    Token t = p.current();
    advance(p)!; // consume $switch

    Node condition;
    if (!p.is(COLON))
    {
        condition = parse_expr(p)!;
    }
    expect(p, COLON)!;

    uint cases_list_ex;
    @with_scratch(; watermark)
    {
        while (p.current().kind != CT_ENDSWITCH && !p.eof())
        {
            TokenKind k = p.current().kind;
            Node n = (k == CT_CASE || k == CT_DEFAULT) 
                ? parse_ct_case(p)! 
                : parse_statement(p)!;
            
            scratch.push((uint)n);
        }
        cases_list_ex = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
    };

    expect(p, CT_ENDSWITCH)!;

    uint[2] header = { (uint)condition, cases_list_ex };
    uint ex = p.ast.push_extra_block(&header);
    return p.ast.add_node(CT_SWITCH_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_ct_case(Parser* p)
{
    Token t = p.current();
    bool is_default = (t.kind == CT_DEFAULT);
    advance(p)!;

    Node label = !is_default ? parse_expr(p)! : {};
    expect(p, COLON)!;

    uint body_list_ex;
    @with_scratch(; watermark)
    {
        while (true)
        {
            TokenKind k = p.current().kind;
            if (k == CT_CASE || k == CT_DEFAULT || k == CT_ENDSWITCH || p.eof()) break;
            
            scratch.push((uint)parse_statement(p)!);
        }
        body_list_ex = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
    };

    uint[2] header = { (uint)label, body_list_ex };
    uint ex = p.ast.push_extra_block(&header);

    return p.ast.add_node(CT_CASE_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_do_while(Parser* p)
{
	Token t = p.current();
	advance(p)!; // consume 'do'

	uint label = parse_label(p, true)!;

	Node cond;
	Node body = parse_statement(p)!;

	if (!consume(p, EOS)!)
	{
		expect(p, WHILE)!;

		expect(p, LPAREN)!;
		cond = parse_expr(p)!;
		expect(p, RPAREN)!;

		expect(p, EOS)!;
	}

	uint[3] data = { (uint)body, (uint)cond, label };
	uint ex = p.ast.push_extra_list(&data);
	return p.ast.add_node(DO_WHILE_STMT, t.pos, p.current_pos(), ex);
}

fn Node? parse_foreach_var(Parser* p)
{
	uint start_tok = p.current_pos();
	Node var_type;
	bool is_ref = false;

	if (is_type(p)
		&& (p.peek(1).kind == IDENT || p.peek(1).kind == AMP
			|| p.peek(1).kind == ASTERISK))
	{
		var_type = parse_type(p)!;
	}

	if (consume(p, AMP)!) is_ref = true;

	Token t = p.current();
	expect(p, IDENT)!;
	uint name = p.pool.intern(p.token_text(t));

	uint[3] data = { (uint)var_type, name, is_ref ? 1 : 0 };
	uint ex = p.ast.push_extra_list(&data);

	return p.ast.add_node(FOREACH_VAR, t.pos, p.current_pos(), ex);
}

<*
	ct_foreach_stmt ::= CT_FOREACH CT_IDENT (',' CT_IDENT)? ':' expr ':' statement* CT_ENDFOREACH
*>
fn Node? parse_ct_foreach(Parser* p)
{
    uint start_pos = p.current_pos();
    expect(p, CT_FOREACH)!;

    Token val_tok = p.current();
    expect(p, CT_IDENT)!;
    uint val_sh = p.pool.intern(p.token_text(val_tok));

    uint index_sh = 0;
    if (consume(p, COMMA)!)
    {
        Token index_tok = p.current();
        expect(p, CT_IDENT)!;
        index_sh = p.pool.intern(p.token_text(index_tok));
    }

    expect(p, COLON)!;
    Node iterable = parse_expr(p)!;
    expect(p, COLON)!;

    uint body_ex = 0;
    @with_scratch(; watermark)
    {
        while (!p.is(CT_ENDFOREACH) && !p.eof())
        {
            Node stmt = parse_statement(p)!;
            if (stmt.is_valid()) scratch.push((uint)stmt);
        }
        body_ex = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
    };

    expect(p, CT_ENDFOREACH)!;

    uint[4] data = { val_sh, index_sh, (uint)iterable, body_ex };
    uint ex = p.ast.push_extra_block(&data); 

    return p.ast.add_node(CT_FOREACH_STMT, start_pos, p.current_pos(), ex);
}

fn Node? parse_foreach(Parser* p)
{
	uint start_tok = p.current_pos();
	bool is_reverse = consume(p, FOREACH_R)!;
	if (!is_reverse) expect(p, FOREACH)!;

	uint label = 0;
	if (p.current().kind == CONST_IDENT && p.peek(1).kind == COLON)
	{
		Token t = p.current();
		label = p.pool.intern(p.token_text(t));
		advance(p)!; // ident
		advance(p)!; // colon
	}

	expect(p, LPAREN)!;

	uint[2] vars;
	vars[0] = (uint)parse_foreach_var(p)!;

	// if there is another var, then we flip the array
	// so if vars[1] != 0, then: vars[0] = index & vars[1] = variable
	// else vars[0] = variable
	if (consume(p, COMMA)!)
	{
		vars[1] = vars[0];
		vars[0] = (uint)parse_foreach_var(p)!;
	}

	expect(p, COLON)!;
	Node iterable = parse_expr(p, { })!;
	expect(p, RPAREN)!;

	Node body = parse_statement(p)!;

	uint[*] data = { label, vars[0], // index
	vars[1], // variable
	(uint)iterable, (uint)body };
	uint ex = p.ast.push_extra_block(&data);

	return p.ast.add_node(
		is_reverse ? FOREACH_R_STMT : FOREACH_STMT,
		start_tok,
		p.current_pos(),
		ex
	);
}

fn Node? parse_while_stmt(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, WHILE)!;

	uint label = parse_label(p, true)!;

	expect(p, LPAREN)!;
	Node condition = parse_cond(p)!;
	expect(p, RPAREN)!;

	Node body = parse_statement(p)!;

	uint[*] data = { label, (uint)condition, (uint)body };
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(WHILE_STMT, start_tok, p.current_pos(), ex);
}

fn Node? parse_defer(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, DEFER)!;

	DeferKind kind = DeferKind.NORMAL;
	uint var_name = 0;

	// (TRY | CATCH | '(' CATCH var ')')?
	if (consume(p, TRY)!)
	{
		kind = DeferKind.TRY;
	}
	else if (consume(p, CATCH)!)
	{
		kind = DeferKind.CATCH;
	}
	else if (p.is(LPAREN) && p.peek(1).kind == CATCH)
	{
		advance(p)!; // (
		advance(p)!; // catch

		if (!p.is(IDENT))
		{
			p.error("Expected variable name after 'catch'");
			return UNEXPECTED_TOKEN~;
		}

		var_name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;

		expect(p, RPAREN)!;
		kind = DeferKind.CATCH_VAR;
	}

	Node stmt = parse_statement(p)!;

	uint[3] data = { (uint)kind, (uint)stmt, var_name };
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(DEFER_STMT, start_tok, p.current_pos(), ex);
}

fn Node? parse_assert_stmt(Parser* p)
{
	Token t = p.current();
	expect(p, ASSERT)!;
	expect(p, LPAREN)!;

	Node cond = parse_expr(p)!;

	Node message;
	bool has_msg = false;
	uint args;

	// optional message: assert(cond, "message", ...)
	@with_scratch(; watermark)
	{
		if (consume(p, COMMA)!)
		{
			has_msg = true;
			message = parse_expr(p, Precedence.LOWEST)!;

			while (consume(p, COMMA)!)
			{
				Node arg = parse_expr(p, Precedence.LOWEST)!;
				scratch.push((uint)arg);
			}

			uint count = (uint)scratch.len() - watermark;
			args = p.ast.push_extra_list(scratch_view(watermark, count));
		}
	};

	expect(p, RPAREN)!;
	expect(p, EOS)!;

	uint[3] final_data = {
		(uint)cond,
		(uint)message,
		args
	};

	uint ex = p.ast.push_extra_block(&final_data);
	return p.ast.add_node(ASSERT_STMT, t.pos, p.current_pos(), ex);
}