module c3_parser::parser;

import c3_parser::ast;
import lexer;
import c3_parser::common;
import c3_parser::constants;

import std::collections::list;

fn uint? parse_label(ParseContext* ctx, bool check_for_colon = false)
{
	if (ctx.is(CONST_IDENT))
	{
		uint label = ctx.pool.intern(ctx.token_text(ctx.current()));
		advance(ctx)!;
		if (check_for_colon)
		{
			if (!consume(ctx, COLON)!)
			{
				ctx.error("Expected colon after label");
			}
		}
		return label;
	}

	return 0;
}

fn Node? parse_statement(ParseContext* ctx)
{
	TokenKind kind = ctx.current().kind;

	log::debug("parse_statement : %s - %s", ctx.current_text(), kind);

	if (is_type(ctx)
		|| kind == TLOCAL 
		|| kind == STATIC)
	{
		return parse_decl_stmt(ctx);
	}

	switch (kind)
	{
		case CT_IF:
			return parse_ct_if(ctx)!;
		case CT_SWITCH:
			return parse_ct_switch(ctx)!;
		case CT_FOREACH:
			return parse_ct_foreach(ctx)!; 
		case LBRACE:
			return parse_compound(ctx)!;
		case VAR:
			return parse_var_decl(ctx, { .is_var = true, .is_local = true })!;
		case CONST:
			advance(ctx)!;
			return parse_var_decl(ctx, { .is_const = true, .is_local = true })!;
		case STATIC:
			advance(ctx)!;
			return parse_var_decl(ctx, { .is_static = true, .is_local = true })!;
		case RETURN:
			return parse_return(ctx)!;
		case DEFER:
			return parse_defer(ctx)!;
		case IF:
			return parse_if(ctx)!;
		case DO:
			return parse_do_while(ctx)!;
		case SWITCH:
			return parse_switch(ctx)!;
		case NEXTCASE:
			return parse_nextcase(ctx)!;
		case BREAK:
			return parse_break(ctx)!;
		case CONTINUE:
			return parse_continue_stmt(ctx)!;
		case FOREACH:
		case FOREACH_R:
			return parse_foreach(ctx)!;
		case WHILE:
			return parse_while_stmt(ctx)!;
		case FOR:
			return parse_for_stmt(ctx)!;
		case CT_FOR:
			return parse_ct_for_stmt(ctx)!;
		case ASSERT:
			return parse_assert_stmt(ctx)!;
		case CT_ASSERT:
		case CT_ERROR:
			return parse_ct_assert(ctx);
		case CT_ECHO:
			uint token_pos = ctx.current_pos();
			advance(ctx)!;
			Node expr = parse_constant_expr(ctx)!;
			return ctx.ast.add_node(CT_ECHO_STMT, token_pos, ctx.current_pos(), (uint)expr);
		case ASM:
			return parse_asm_block_stmt(ctx)!;
		case EOS:
			uint token_pos = ctx.current_pos();
			advance(ctx)!;
			return ctx.ast.add_node(NOP_STMT, token_pos, token_pos, 0);
		default:
			{
				// if it's not a keyword or type, treat it as a expression statement
				return parse_expr_stmt(ctx)!;
			}
	}
}

<*
	ct_error_stmt ::= CT_ERROR constant_expression (',' constant_expression)* ';'
*>
fn Node? parse_ct_assert(ParseContext* ctx)
{
	uint start_pos = ctx.current().pos;
	advance(ctx)!;

	Node cond = parse_constant_expr(ctx)!;
	Node message;
	uint args;

	if (consume(ctx, COLON)!)
	{
		message = parse_constant_expr(ctx)!;

		@with_scratch(; watermark)
		{
			while (consume(ctx, COMMA)!)
			{
				scratch.push((uint)parse_constant_expr(ctx)!);
			}
			uint count = (uint)scratch.len() - watermark;
			args = ctx.ast.push_extra_list(scratch_view(watermark, count));
		};
	}
	expect(ctx, EOS)!;

	uint[*] data = views::@data{CtAssertViewFields}
	(
		COND, cond,
		MESSAGE, message,
		ARGS, args,
	);

	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(CT_ASSERT_STMT, start_pos, ctx.current_pos(), ex);
}

fn Node? parse_for_stmt(ParseContext* ctx)
{
	uint for_token = ctx.current_pos();
	expect(ctx, FOR)!;

	uint label = parse_label(ctx, true)!;

	expect(ctx, LPAREN)!;

	Node init;
	if (!ctx.is(EOS))
	{
		init = parse_expr_list(ctx)!;
	}
	expect(ctx, EOS)!;

	Node cond_expr;
	if (!ctx.is(EOS))
	{
		cond_expr = parse_expr(ctx)!;
	}
	expect(ctx, EOS)!;

	Node incr_expr;
	if (!ctx.is(RPAREN))
	{
		incr_expr = parse_expr_list(ctx)!;
	}
	expect(ctx, RPAREN)!;
	Node body = parse_statement(ctx)!;

	uint[*] data = { (uint)init, (uint)cond_expr, (uint)incr_expr, (uint)body };

	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(FOR_STMT, for_token, ctx.current_pos(), ex);
}

// TODO: needs eos refinement
fn Node? parse_ct_for_stmt(ParseContext* ctx)
{
	uint start_pos = ctx.current().pos;
	advance(ctx)!;

	Node init;
	Node cond;
	Node incr;

	if (!ctx.is(EOS))
	{
		init = parse_ct_expr_list(ctx)!; 
	}

	consume(ctx, EOS)!;

	cond = parse_expr(ctx)!;

	consume(ctx, EOS)!;

	if (!ctx.is(COLON))
	{
		incr = parse_ct_expr_list(ctx)!;
	}

	expect(ctx, COLON)!;

	uint stmts;
	@with_scratch(; watermark)
	{
		while (!ctx.is(CT_ENDFOR) && !ctx.eof())
		{
			Node stmt = parse_statement(ctx)!;
			scratch.push((uint)stmt);
		}

		uint count = (uint)scratch.len() - watermark;
		stmts = ctx.ast.push_extra_list(scratch_view(watermark, count));
	};

	expect(ctx, CT_ENDFOR)!;

	uint[4] final_data = {
		(uint)init,
		(uint)cond,
		(uint)incr,
		stmts
	};

	uint ex = ctx.ast.push_extra_block(&final_data); 
	return ctx.ast.add_node(CT_FOR_STMT, start_pos, ctx.current_pos(), ex);
}

<*
	parses all statments within a { ... }
*>
fn Node? parse_compound(ParseContext* ctx) => @with_scratch(; watermark)
{
	uint lbrace_tok = ctx.current_pos();
	expect(ctx, LBRACE)!;

	while (!ctx.is(RBRACE) && !ctx.eof())
	{
		Node stmt = parse_statement(ctx)!;
		scratch.push((uint)stmt);
	}

	expect(ctx, RBRACE)!;

	uint count = (uint)scratch.len() - watermark;
	uint ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
	return ctx.ast.add_node(COMPOUND_STMT, lbrace_tok, ctx.current_pos(), ex);
}

fn Node? parse_decl_stmt(ParseContext* ctx)
{
	uint token_pos = ctx.current_pos();

	ParseFlags flags;
	if (consume(ctx, STATIC)!)
	{
		flags.is_static = true;
	}
	if (consume(ctx, TLOCAL)!)
	{
		flags.is_tlocal = true;
	}

	Node type_node = parse_type(ctx)!;

	TokenKind kind;
	switch (kind = ctx.current().kind) 
	{
		case IDENT:
		case CT_IDENT:
			return parse_local(ctx, token_pos, type_node, flags);

		default:
	}

	Node expr = parse_expr_resuming_with_left(ctx, type_node, 0)!;
	expect(ctx, EOS)!;
	return expr;
}

fn Node? parse_expr_stmt(ParseContext* ctx)
{
	log::debug("parse_expr_stmt - %s : %s", ctx.current_text(), ctx.current().kind);
	Token t = ctx.current();
	Node expr = parse_expr(ctx)!;
	expect(ctx, EOS)!; // TODO: how should EOS be handled?

	return ctx.ast.add_node(EXPR_STMT, t.pos, ctx.current_pos(), (uint)expr);
}

fn Node? parse_return(ParseContext* ctx)
{
	Token t = ctx.current();
	advance(ctx)!; // consume 'return'

	Node expr;
	if (ctx.current().kind != EOS)
	{
		expr = parse_expr(ctx, { })!;
	}

	expect(ctx, EOS)!;

	return ctx.ast.add_node(RETURN_STMT, t.pos, ctx.current_pos(), (uint)expr);
}

fn Node? parse_if(ParseContext* ctx)
{
	Token t = ctx.current();
	advance(ctx)!; // consume 'if'

	uint label = parse_label(ctx, true)!;

	expect(ctx, LPAREN)!;
	Node cond = parse_cond(ctx)!;
	expect(ctx, RPAREN)!;

	// Parse the "then" branch
	Node then_block = parse_statement(ctx)!;
	Node else_block;

	// Check for optional "else"
	if (ctx.current().kind == ELSE)
	{
		advance(ctx)!; // consume 'else'
		// This handles "else if" automatically because parse_statement
		// will see the 'if' and call this function recursively.
		else_block = parse_statement(ctx)!;
	}

	uint[*] data = views::@data{IfViewFields}
	(
		CONDITION, cond,
		LABEL, label,
		THEN_BLOCK, then_block,
		ELSE_BLOCK, else_block,
	);

	uint ex = ctx.ast.push_extra_block(&data);

	return ctx.ast.add_node(IF_STMT, t.pos, ctx.current_pos(), ex);
}

fn Node? parse_ct_if(ParseContext* ctx)
{
	Token t = ctx.current();
	advance(ctx)!; // consume $if

	Node condition = parse_expr(ctx)!;

	expect(ctx, COLON)!;

	List{uint} then_stmts;
	then_stmts.tinit(16);
	then_stmts.push(0); // len
	defer then_stmts.free();

	while (!ctx.is(CT_ELSE) && !ctx.is(CT_ENDIF))
	{
		then_stmts.push((uint)parse_statement(ctx)!);
	}

	then_stmts[0] = (uint)then_stmts.len() - 1;
	uint ex_then = ctx.ast.push_extra_list(then_stmts.array_view());
	Node then_block = ctx.ast.add_node(BLOCK, t.pos, ctx.current_pos(), ex_then);

	Node else_block;
	if (consume(ctx, CT_ELSE)!)
	{
		List{uint} else_stmts;
		else_stmts.tinit(16);
		else_stmts.push(0); // len
		defer else_stmts.free();

		while (!ctx.is(CT_ENDIF) && !ctx.eof())
		{
			else_stmts.push((uint)parse_statement(ctx)!);
		}

		else_stmts[0] = (uint)else_stmts.len() - 1;
		uint ex = ctx.ast.push_extra_list(else_stmts.array_view());
		else_block = ctx.ast.add_node(BLOCK, t.pos, ctx.current_pos(), ex);
	}

	expect(ctx, CT_ENDIF)!;

	if (ctx.is(EOS))
	{
		advance(ctx)!;
	}

	uint[3] data = { (uint)condition, (uint)then_block, (uint)else_block };
	uint ex = ctx.ast.push_extra_list(&data);
	return ctx.ast.add_node(CT_IF_STMT, t.pos, ctx.current_pos(), ex);
}

fn Node? parse_nextcase(ParseContext* ctx)
{
	Token t = ctx.current();
	advance(ctx)!;

	Node expr;
	if (!ctx.is(EOS))
	{
		expr = parse_expr(ctx)!;
	}
	else
	{
		expr = ctx.ast.add_empty(t.pos);
	}

	expect(ctx, EOS)!;

	return ctx.ast.add_node(NEXTCASE_STMT, t.pos, ctx.current_pos(), 0);
}

fn Node? parse_continue_stmt(ParseContext* ctx)
{
	Token t = ctx.current();
	advance(ctx)!;

	uint label = parse_label(ctx)!;

	expect(ctx, EOS)!;

	return ctx.ast.add_node(CONTINUE_STMT, t.pos, ctx.current_pos(), label);
}

fn Node? parse_switch(ParseContext* ctx)
{
	Token t = ctx.current();
	advance(ctx)!;
	
	Node cond;
	if (consume(ctx, LPAREN)!)
	{
		cond = parse_expr(ctx)!;
		expect(ctx, RPAREN)!;	
	}

	expect(ctx, LBRACE)!;

	uint cases;
	@with_scratch(; watermark)
	{
		while (!ctx.is(RBRACE) && !ctx.is(EOS))
		{
			scratch.push((uint)parse_switch_case(ctx)!);
		}

		uint count = (uint)scratch.len() - watermark;
		cases = ctx.ast.push_extra_list(scratch_view(watermark, count));
	};

	expect(ctx, RBRACE)!;

	uint[2] final_data = {
		(uint)cond,
		cases
	};

	uint ex = ctx.ast.push_extra_block(&final_data);
	return ctx.ast.add_node(SWITCH_STMT, t.pos, ctx.current_pos(), ex);
}

fn Node? parse_switch_case(ParseContext* ctx)
{
	Token t = ctx.current();
	if (consume(ctx, CASE)!)
	{
		Node label = parse_expr(ctx)!;
		Node range_end;

		if (consume(ctx, DOTDOT)!)
		{
			range_end = parse_expr(ctx)!;
		}

		expect(ctx, COLON)!;

		uint stmts;
        @with_scratch(; watermark)
        {
            while (!ctx.is(CASE) && !ctx.is(DEFAULT) && !ctx.is(RBRACE) && !ctx.eof())
            {
                Node stmt = parse_statement(ctx)!;
                scratch.push((uint)stmt);
            }
            uint count = (uint)scratch.len() - watermark;
            stmts = ctx.ast.push_extra_list(scratch_view(watermark, count));
        };

		uint[*] data = { (uint)label, (uint)range_end, stmts };
		uint ex = ctx.ast.push_extra_block(&data);
		return ctx.ast.add_node(CASE_STMT, t.pos, ctx.current_pos(), ex);
	}
	else if (consume(ctx, DEFAULT)!)
	{
		expect(ctx, COLON)!;
		uint stmts;
        @with_scratch(; watermark)
        {
            while (!ctx.is(CASE) && !ctx.is(DEFAULT) && !ctx.is(RBRACE) && !ctx.eof())
            {
                Node stmt = parse_statement(ctx)!;
                scratch.push((uint)stmt);
            }
            uint count = (uint)scratch.len() - watermark;
            stmts = ctx.ast.push_extra_list(scratch_view(watermark, count));
        };
		return ctx.ast.add_node(DEFAULT_STMT, t.pos, ctx.current_pos(), stmts);
	}

	return parse_statement(ctx)!;
}

fn Node? parse_break(ParseContext* ctx)
{
	Token t = ctx.current();
	advance(ctx)!;

	uint label = parse_label(ctx)!;

	expect(ctx, EOS)!;

	return ctx.ast.add_node(BREAK_STMT, t.pos, ctx.current_pos(), label);
}

fn Node? parse_ct_switch(ParseContext* ctx)
{
    Token t = ctx.current();
    advance(ctx)!; // consume $switch

    Node condition;
    if (!ctx.is(COLON))
    {
        condition = parse_expr(ctx)!;
    }
    expect(ctx, COLON)!;

    uint cases_list_ex;
    @with_scratch(; watermark)
    {
        while (ctx.current().kind != CT_ENDSWITCH && !ctx.eof())
        {
            TokenKind k = ctx.current().kind;
            Node n = (k == CT_CASE || k == CT_DEFAULT) 
                ? parse_ct_case(ctx)! 
                : parse_statement(ctx)!;
            
            scratch.push((uint)n);
        }
        cases_list_ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
    };

    expect(ctx, CT_ENDSWITCH)!;

    uint[2] header = { (uint)condition, cases_list_ex };
    uint ex = ctx.ast.push_extra_block(&header);
    return ctx.ast.add_node(CT_SWITCH_STMT, t.pos, ctx.current_pos(), ex);
}

fn Node? parse_ct_case(ParseContext* ctx)
{
    Token t = ctx.current();
    bool is_default = (t.kind == CT_DEFAULT);
    advance(ctx)!;

    Node label = !is_default ? parse_expr(ctx)! : {};
    expect(ctx, COLON)!;

    uint body_list_ex;
    @with_scratch(; watermark)
    {
        while (true)
        {
            TokenKind k = ctx.current().kind;
            if (k == CT_CASE || k == CT_DEFAULT || k == CT_ENDSWITCH || ctx.eof()) break;
            
            scratch.push((uint)parse_statement(ctx)!);
        }
        body_list_ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
    };

    uint[2] header = { (uint)label, body_list_ex };
    uint ex = ctx.ast.push_extra_block(&header);

    return ctx.ast.add_node(CT_CASE_STMT, t.pos, ctx.current_pos(), ex);
}

fn Node? parse_do_while(ParseContext* ctx)
{
	Token t = ctx.current();
	advance(ctx)!; // consume 'do'

	uint label = parse_label(ctx, true)!;

	Node cond;
	Node body = parse_statement(ctx)!;

	if (!consume(ctx, EOS)!)
	{
		expect(ctx, WHILE)!;

		expect(ctx, LPAREN)!;
		cond = parse_expr(ctx)!;
		expect(ctx, RPAREN)!;

		expect(ctx, EOS)!;
	}

	uint[3] data = { (uint)body, (uint)cond, label };
	uint ex = ctx.ast.push_extra_list(&data);
	return ctx.ast.add_node(DO_WHILE_STMT, t.pos, ctx.current_pos(), ex);
}

fn Node? parse_foreach_var(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	Node var_type;
	bool is_ref = false;

	if (is_type(ctx)
		&& (ctx.peek(1).kind == IDENT || ctx.peek(1).kind == AMP
			|| ctx.peek(1).kind == ASTERISK))
	{
		var_type = parse_type(ctx)!;
	}

	if (consume(ctx, AMP)!) is_ref = true;

	Token t = ctx.current();
	expect(ctx, IDENT)!;
	uint name = ctx.pool.intern(ctx.token_text(t));

	uint[3] data = { (uint)var_type, name, is_ref ? 1 : 0 };
	uint ex = ctx.ast.push_extra_list(&data);

	return ctx.ast.add_node(FOREACH_VAR, t.pos, ctx.current_pos(), ex);
}

<*
	ct_foreach_stmt ::= CT_FOREACH CT_IDENT (',' CT_IDENT)? ':' expr ':' statement* CT_ENDFOREACH
*>
fn Node? parse_ct_foreach(ParseContext* ctx)
{
    uint start_pos = ctx.current_pos();
    expect(ctx, CT_FOREACH)!;

    Token val_tok = ctx.current();
    expect(ctx, CT_IDENT)!;
    uint val_sh = ctx.pool.intern(ctx.token_text(val_tok));

    uint index_sh = 0;
    if (consume(ctx, COMMA)!)
    {
        Token index_tok = ctx.current();
        expect(ctx, CT_IDENT)!;
        index_sh = ctx.pool.intern(ctx.token_text(index_tok));
    }

    expect(ctx, COLON)!;
    Node iterable = parse_expr(ctx)!;
    expect(ctx, COLON)!;

    uint body_ex = 0;
    @with_scratch(; watermark)
    {
        while (!ctx.is(CT_ENDFOREACH) && !ctx.eof())
        {
            Node stmt = parse_statement(ctx)!;
            if (stmt.is_valid()) scratch.push((uint)stmt);
        }
        body_ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
    };

    expect(ctx, CT_ENDFOREACH)!;

    uint[4] data = { val_sh, index_sh, (uint)iterable, body_ex };
    uint ex = ctx.ast.push_extra_block(&data); 

    return ctx.ast.add_node(CT_FOREACH_STMT, start_pos, ctx.current_pos(), ex);
}

fn Node? parse_foreach(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	bool is_reverse = consume(ctx, FOREACH_R)!;
	if (!is_reverse) expect(ctx, FOREACH)!;

	uint label = 0;
	if (ctx.current().kind == CONST_IDENT && ctx.peek(1).kind == COLON)
	{
		Token t = ctx.current();
		label = ctx.pool.intern(ctx.token_text(t));
		advance(ctx)!; // ident
		advance(ctx)!; // colon
	}

	expect(ctx, LPAREN)!;

	uint[2] vars;
	vars[0] = (uint)parse_foreach_var(ctx)!;

	// if there is another var, then we flip the array
	// so if vars[1] != 0, then: vars[0] = index & vars[1] = variable
	// else vars[0] = variable
	if (consume(ctx, COMMA)!)
	{
		vars[1] = vars[0];
		vars[0] = (uint)parse_foreach_var(ctx)!;
	}

	expect(ctx, COLON)!;
	Node iterable = parse_expr(ctx, { })!;
	expect(ctx, RPAREN)!;

	Node body = parse_statement(ctx)!;

	uint[*] data = { label, vars[0], // index
	vars[1], // variable
	(uint)iterable, (uint)body };
	uint ex = ctx.ast.push_extra_block(&data);

	return ctx.ast.add_node(
		is_reverse ? FOREACH_R_STMT : FOREACH_STMT,
		start_tok,
		ctx.current_pos(),
		ex
	);
}

fn Node? parse_while_stmt(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, WHILE)!;

	uint label = parse_label(ctx, true)!;

	expect(ctx, LPAREN)!;
	Node condition = parse_cond(ctx)!;
	expect(ctx, RPAREN)!;

	Node body = parse_statement(ctx)!;

	uint[*] data = { label, (uint)condition, (uint)body };
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(WHILE_STMT, start_tok, ctx.current_pos(), ex);
}

fn Node? parse_defer(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, DEFER)!;

	DeferKind kind = DeferKind.NORMAL;
	uint var_name = 0;

	// (TRY | CATCH | '(' CATCH var ')')?
	if (consume(ctx, TRY)!)
	{
		kind = DeferKind.TRY;
	}
	else if (consume(ctx, CATCH)!)
	{
		kind = DeferKind.CATCH;
	}
	else if (ctx.is(LPAREN) && ctx.peek(1).kind == CATCH)
	{
		advance(ctx)!; // (
		advance(ctx)!; // catch

		if (!ctx.is(IDENT))
		{
			ctx.error("Expected variable name after 'catch'");
			return UNEXPECTED_TOKEN~;
		}

		var_name = ctx.pool.intern(ctx.token_text(ctx.current()));
		advance(ctx)!;

		expect(ctx, RPAREN)!;
		kind = DeferKind.CATCH_VAR;
	}

	Node stmt = parse_statement(ctx)!;

	uint[3] data = { (uint)kind, (uint)stmt, var_name };
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(DEFER_STMT, start_tok, ctx.current_pos(), ex);
}

fn Node? parse_assert_stmt(ParseContext* ctx)
{
	Token t = ctx.current();
	expect(ctx, ASSERT)!;
	expect(ctx, LPAREN)!;

	Node cond = parse_expr(ctx)!;

	Node message;
	bool has_msg = false;
	uint args;

	// optional message: assert(cond, "message", ...)
	@with_scratch(; watermark)
	{
		if (consume(ctx, COMMA)!)
		{
			has_msg = true;
			message = parse_expr(ctx, Precedence.LOWEST)!;

			while (consume(ctx, COMMA)!)
			{
				Node arg = parse_expr(ctx, Precedence.LOWEST)!;
				scratch.push((uint)arg);
			}

			uint count = (uint)scratch.len() - watermark;
			args = ctx.ast.push_extra_list(scratch_view(watermark, count));
		}
	};

	expect(ctx, RPAREN)!;
	expect(ctx, EOS)!;

	uint[3] final_data = {
		(uint)cond,
		(uint)message,
		args
	};

	uint ex = ctx.ast.push_extra_block(&final_data);
	return ctx.ast.add_node(ASSERT_STMT, t.pos, ctx.current_pos(), ex);
}