module analyzer::parser;

import analyzer::core;
import std::collections::list;

fn Node*? parse_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Token t = ctx.current();

	plog::debug("parse_stmt: current = %s (%s)", ctx.token_text(t), t.kind.description);

	if (is_type(ctx) || t.kind == TLOCAL || t.kind == STATIC)
	{
		return parse_decl_stmt(scope)!;
	}

	switch (t.kind)
	{
		case LBRACE:
			return parse_compound_stmt(scope)!;
		case SWITCH:
			return parse_switch_stmt(scope)!;
		case CONTINUE:
		case BREAK:
			return parse_continue_break_stmt(scope)!;
		case NEXTCASE:
			return parse_nextcase_stmt(scope)!;
		case RETURN:
			return parse_return_stmt(scope)!;
		case DEFER:
			return parse_defer_stmt(scope)!;
		case CT_SWITCH:
			return parse_ct_switch_stmt(scope)!;
		case IF:
			return parse_if_stmt(scope)!;
		case CT_IF:
			return parse_ct_if_stmt(scope)!;
		case FOR:
			return parse_for_stmt(scope)!;
		case CT_FOR:
			return parse_ct_for_stmt(scope)!;
		case WHILE:
			return parse_while_stmt(scope)!;
		case DO:
			return parse_do_while_stmt(scope)!;
		case FOREACH:
		case FOREACH_R:
			return parse_foreach_stmt(scope)!;
		case CT_FOREACH:
			return parse_ct_foreach_stmt(scope)!;
		case CT_ASSERT:
			return parse_ct_assert_stmt(scope)!;
		case CT_ERROR:
			return parse_ct_error_stmt(scope)!;
		case CT_ECHO:
			return parse_ct_echo_stmt(scope)!;
		case VAR:
			return parse_var_decl(scope.with_flags({ .is_var = true, .is_local = true }), null);
		case CONST:
			advance(ctx)!;
			return parse_var_decl(scope.with_flags({ .is_const = true, .is_local = true }), null)!;
		case STATIC:
			advance(ctx)!;
			return parse_var_decl(scope.with_flags({ .is_static = true, .is_local = true }), null)!;
		case ASSERT:
			return parse_assert_stmt(scope)!;
		case CT_EXPAND:
			return parse_ct_expand_stmt(scope)!;
		case HASH_IDENT:
		case IDENT:
		case CONST_IDENT:
		case AMP:
		case AT_CONST_IDENT:
		case AT_IDENT:
		case AT_TYPE_IDENT:
		case BANG:
		case BIT_NOT:
		case BIT_OR:
		case BIT_XOR:
		case BUILTIN:
		case BYTES_LITERAL:
		case CHAR_LITERAL:
		case CT_AND_OP:
		case CT_CONCAT_OP:
		case CT_CONCAT_ASSIGN:
		case CT_CONST_IDENT:
		case CT_DEFINED:
		case CT_EMBED:
		case CT_EVAL:
		case CT_FEATURE:
		case CT_IDENT:
		case CT_OR_OP:
		case CT_REFLECT:
		case CT_STRINGIFY:
		case CT_TERNARY:
		case CT_VAARG:
		case FALSE:
		case INT_DECIMAL_LITERAL:
		case INT_BIN_LITERAL:
		case INT_HEX_LITERAL:
		case INT_OCTAL_LITERAL:
		case LENGTHOF:
		case LPAREN:
		case MINUS:
		case MINUSMINUS:
		case NULL:
		case OR:
		case PLUS:
		case PLUSPLUS:
		case FLOAT_DECIMAL_LITERAL:
		case FLOAT_HEX_LITERAL:
		case ASTERISK:
		case STRING_LITERAL:
		case TRUE:
			return parse_expr_stmt(scope)!;
		case EOS:
			advance(ctx)!;
			return ctx.ast.alloc_node(NOP_STMT, t.pos);
		default:
			break;
	}

	advance(ctx)!;
	return unexpected_at(ctx, t, "Unexpected '%s' found when expecting a statement", t.kind.description);
}

<*
 parse a expression inside a statement
	expr_stmt ::= expr ';'
*>
fn Node*? parse_expr_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(EXPR_STMT, start_pos);
	ExprStmt* es  = node.as(EXPR_STMT);
	es.expr_stmt = parse_expr(scope)!;
	node.offset.end = ctx.current_pos();
	expect(ctx, EOS);
	return node;
}

<*
 decl_stmt ::= expr ';' | decl
*>
fn Node*? parse_decl_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;

	ParseFlags flags;
	flags.is_static = consume(ctx, STATIC)!;
	flags.is_tlocal = consume(ctx, TLOCAL)!;

	Node* type = parse_type_expr(scope)!;
	switch (ctx.current().kind)
	{
		case IDENT:
		case CT_IDENT:
			return parse_var_decl(scope.with_flags(flags), type);
		default:
	}

	Node* expr = parse_expr_resuming_with_left(scope, type, LOWEST)!;
	expect(ctx, EOS)!;
	return expr;
}

<*
 compound_stmt ::= ('{' stmt* '}')
*>
fn Node*? parse_compound_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	expect(ctx, LBRACE)!;
	Node* node          = ctx.ast.alloc_node(COMPOUND_STMT, start_pos);
	CompoundStmt* block = node.as(COMPOUND_STMT);

	List{Node*} temp_stmts;
	temp_stmts.init(tmem, 8);

	while (!ctx.is(RBRACE) && !ctx.eof())
	{
		Node*? stmt = parse_stmt(scope);
		if (catch stmt)
		{
			ctx.error("Malformed statement inside block");
			Node* err_node = ctx.ast.error(ctx.current().pos);
			temp_stmts.push(err_node);
			ctx.skip_until({ RBRACE, EOS })!;
			continue;
		}

		if (stmt != null)
		{
			temp_stmts.push(stmt);
		}
	}
	
	node.offset.end = ctx.current_pos();

	expect(ctx, RBRACE)!;

	block.statements = alloc::clone_slice(ctx.arena, temp_stmts.array_view());

	return node;
}

<*
 switch_body ::= '{' (case_stmt | nextcase_stmt | default_stmt)* '}'
*>
fn bool? parse_switch_body(ContextScope scope, List{Node*}* cases)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	while (!ctx.eof() && !ctx.is(RBRACE))
	{
		if (ctx.eof())
		{
			ctx.error("Unexpected EOF, expected closing '}' for switch body");
			return false;
		}

		Node* result   = null;
		TokenKind kind = ctx.current().kind;

		switch (kind)
		{
			case CASE:
				result = parse_case_stmt(scope)!;
				if (result.kind == ERROR) return false;
			case DEFAULT:
				result = parse_default_stmt(scope)!;
				if (result.kind == ERROR) return false;
			default:
				ctx.error("Expected 'case' or 'default' inside switch body, got '%s'", kind.description);
				return false;
		}

		cases.push(result);
	}

	return true;
}

<*
 case_stmts ::= (compound_stmt, stmt*)
*>
fn Node*? parse_case_stmts(ContextScope scope, sz row) => @pool()
{
	ParseContext* ctx = scope.ctx;

	if (token_type_ends_case(ctx.current().kind))
	{
		Location next_loc = ctx.line_map.resolve(ctx.current().pos);

		if (next_loc.line > row + 1 && ctx.current().kind != RBRACE)
		{
			ctx.error(
				"Fallthrough cases with empty rows or comments have unclear meaning, an explicit 'break' or 'nextcase' is needed (or remove the spacing)."
			);
			return ctx.ast.error(ctx.current().pos);
		}
	}

	Node* compound_node    = ctx.ast.alloc_node(COMPOUND_STMT, ctx.current().pos);
	CompoundStmt* compound = compound_node.as(COMPOUND_STMT);

	List{Node*} stmts;
	stmts.tinit();

	while (!ctx.eof() && !token_type_ends_case(ctx.current().kind))
	{
		Node* child_stmt = parse_stmt(scope)!;
		if (child_stmt.kind == ERROR) return child_stmt;
		stmts.push(child_stmt);
	}

	compound.statements = alloc::clone_slice(ctx.arena, stmts.array_view());
	compound_node.offset.end = ctx.current().pos;

	return compound_node;
}

<*
 case_stmt ::= 'case' expr ('..' expr)? ':' stmt*

*>
fn Node*? parse_case_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	int pos            = ctx.current().pos;
	TokenKind expected = flags.is_comptime ? CT_CASE : CASE;
	@expect_else(ctx, expected ; err)
	{
		return err;
	}!;

	Location loc = ctx.line_map.resolve((sz)pos);
	sz case_row  = loc.line;

	Node* node = ctx.ast.alloc_node(CASE_STMT, pos);
	defer node.offset.end = ctx.current().pos;
	CaseStmt* case_stmt = node.as(CASE_STMT);

	case_stmt.expr = parse_expr(scope)!;
	if (consume(ctx, DOTDOT)!)
	{
		case_stmt.to_expr = parse_expr(scope)!;
	}
	@expect_else(ctx, COLON ; err)
	{
		return err;
	}!;

	case_stmt.body = parse_case_stmts(scope, case_row)!;

	return node;
}

<*
 default_stmt ::= default | $default ':' case_stmts
*>
fn Node*? parse_default_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
  ParseFlags flags = scope.flags;

	int start_pos      = ctx.current().pos;
	TokenKind expected = flags.is_comptime ? CT_DEFAULT : DEFAULT;
	@expect_else(ctx, expected ; err)
	{
		return err;
	}!;

	@expect_else(ctx, COLON ; err)
	{
		return err;
	}!;

	Node* node      = ctx.ast.alloc_node(DEFAULT_STMT, start_pos);
	DefaultStmt* sw = node.as(DEFAULT_STMT);
	defer node.offset.end = ctx.current().pos;

	Location loc = ctx.line_map.resolve((sz)start_pos);
	sz row       = loc.line;

	sw.body = parse_case_stmts(scope, row)!;

	return node;
}

<*
 nextcase_stmt ::= NEXTCASE ((CONST_IDENT ':')? expression)? ';'
*>
fn Node*? parse_nextcase_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	@expect_else(ctx, NEXTCASE ; err)
	{
		return err;
	}!;

	Node* node       = ctx.ast.alloc_node(NEXTCASE_STMT, start_pos);
	NextcaseStmt* nc = node.as(NEXTCASE_STMT);
	defer node.offset.end = ctx.current().pos;

	if (consume(ctx, EOS)!)
	{
		return node;
	}
	if (ctx.is(CONST_IDENT) && ctx.peek(1)!.kind == COLON)
	{
		nc.label = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
		@expect_else(ctx, COLON ; err)
		{
			return err;
		}!;
	}
	if (consume(ctx, DEFAULT)!)
	{
		nc.is_default = true;
	}
	else
	{
		nc.expr = parse_expr(scope)!;
	}
	return node;
}

<*
 continue_break_stmt ::= continue | break LABEL? ';'
*>
fn Node*? parse_continue_break_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos    = ctx.current().pos;
	bool is_continue = consume(ctx, CONTINUE)!;
	if (!is_continue) consume(ctx, BREAK)!;

	Node* node            = ctx.ast.alloc_node(CONTINUE_BREAK_STMT, start_pos);
	ContinueBreakStmt* cb = node.as(CONTINUE_BREAK_STMT);

	cb.is_continue = is_continue;
	cb.label = string_pool::EMPTY_STR;

	if (ctx.is(CONST_IDENT))
	{
		cb.label = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
	}

	node.offset.end = ctx.current_pos();

	expect(ctx, EOS)!;

	return node;
}

<*
 switch ::= switch LABEL? ('(' cond ')')? switch_body
*>
fn Node*? parse_switch_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	@expect_else(ctx, SWITCH ; err)
	{
		return err;
	}!;

	Node* node     = ctx.ast.alloc_node(SWITCH_STMT, start_pos);
	SwitchStmt* sw = node.as(SWITCH_STMT);

	if (ctx.is(CONST_IDENT))
	{
		Token label_tok = ctx.current();
		sw.label = ctx.ast.string_pool.internalize(ctx.token_text(label_tok));
		advance(ctx)!;
		expect(ctx, COLON)!;
	}

	if (consume(ctx, LPAREN)!)
	{
		sw.cond = parse_cond_expr(scope)!;
		expect(ctx, RPAREN)!;
	}

	expect(ctx, LBRACE)!;

	List{Node*} bodies;
	bodies.tinit();
	bool success = parse_switch_body(scope, &bodies)!;
	if (!success)
	{
		ctx.skip_until({ RBRACE, EOF })!;
	}
	
	node.offset.end = ctx.current_pos();
	expect(ctx, RBRACE)!;

	sw.cases = alloc::clone_slice(ctx.arena, bodies.array_view());
	return node;
}

<*
 return_stmt ::= return expression | return ';'
*>
fn Node*? parse_return_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	expect(ctx, RETURN)!;

	Node* node      = ctx.ast.alloc_node(RETURN_STMT, start_pos);
	ReturnStmt* ret = node.as(RETURN_STMT);

	if (!ctx.is(EOS))
	{
		ret.expr = parse_expr(scope)!;
	}

	node.offset.end = ctx.current_pos();
	expect(ctx, EOS)!;

	return node;
}

<*
 ct_switch_stmt ::= CT_SWITCH const_expr? ':' ct_case_statement* CT_ENDSWITCH
 ct_case_statement ::= (CT_CASE constant_expr | CT_DEFAULT) ':' opt_stmt_list
*>
fn Node*? parse_ct_switch_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	expect(ctx, CT_SWITCH)!;

	Node* node       = ctx.ast.alloc_node(CT_SWITCH_STMT, start_pos);
	CtSwitchStmt* cs = node.as(CT_SWITCH_STMT);
	defer node.offset.end = ctx.current().pos;

	if (!ctx.is(COLON))
	{
		if (ctx.is(CT_CASE))
		{
			ctx.error("Expected ':' after $switch");
			return ctx.ast.error(ctx.current().pos);
		}

		cs.cond = parse_constant_expr(scope)!;
	}

	expect(ctx, COLON)!;

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ENDSWITCH))
	{
		TokenKind kind = ctx.current().kind;
		plog::debug("parse_ct_switch_stmt - kind: %s", kind.description);
		switch (kind)
		{
			case CT_CASE:
				stmts.push(parse_case_stmt(scope.with_only_flags({ .is_comptime = true }))!);
			case CT_DEFAULT:
				stmts.push(parse_default_stmt(scope.with_only_flags({ .is_comptime = true }))!);
			default:
				ctx.error("'$case' or '$default' expected");
				return ctx.ast.error(ctx.current().pos - 1);
		}
	}

	expect(ctx, CT_ENDSWITCH)!;

	cs.cases = alloc::clone_slice(ctx.arena, stmts.array_view());
	return node;
}

<*
 if_stmt ::= IF LABEL? '(' cond_expr ')' compound_stmt (ELSE compound_stmt)?
	| IF LABEL? '(' cond_expr ')' statement
*>
fn Node*? parse_if_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	expect(ctx, IF)!;

	Node* node      = ctx.ast.alloc_node(IF_STMT, start_pos);
	IfStmt* if_stmt = node.as(IF_STMT);

	if (ctx.is(CONST_IDENT))
	{
		if_stmt.label = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
		expect(ctx, COLON)!;
	}

	expect(ctx, LPAREN)!;

	if_stmt.condition = parse_cond_expr(scope)!;

	expect(ctx, RPAREN)!;

	if_stmt.then_body = parse_stmt(scope)!;
	node.offset.end = if_stmt.then_body.offset.end;

	if (consume(ctx, ELSE)!)
	{
		if_stmt.else_body = parse_stmt(scope)!;
		node.offset.end = if_stmt.else_body.offset.end;
	}
	
	return node;
}

<*
 ct_if_statement ::= "$if" constant_expression ":" statement* ("$else" statement*)? "$endif"
*>
fn Node*? parse_ct_if_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	@expect_else(ctx, CT_IF ; err)
	{
		return err;
	}!;

	Node* node        = ctx.ast.alloc_node(CT_IF_STMT, start_pos);
	CtIfStmt* if_stmt = node.as(CT_IF_STMT);
	defer node.offset.end = ctx.current().pos;

	if_stmt.expr = parse_expr(scope)!;
	@expect_else(ctx, COLON ; err)
	{
		ctx.skip_until({ EOS, EOF, RBRACE })!;
		return err;
	}!;

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ELSE) && !ctx.is(CT_ENDIF))
	{
		stmts.push(parse_stmt(scope)!);
	}

	if_stmt.then_stmts = alloc::clone_slice(ctx.arena, stmts.array_view());
	if (ctx.is(CT_ELSE))
	{
		advance(ctx)!;
		stmts.clear();
		while (!ctx.eof() && !ctx.is(CT_ELSE) && !ctx.is(CT_ENDIF))
		{
			stmts.push(parse_stmt(scope)!);
		}
		if_stmt.else_stmts = alloc::clone_slice(ctx.arena, stmts.array_view());
	}

	@expect_else(ctx, CT_ENDIF ; err)
	{
		return err;
	}!;

	return node;
}

<*
 for_stmt ::= 'for' LABEL? '(' expression_list? ';' cond? ';' expression_list? ')' statement
*>
fn Node*? parse_for_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	@expect_else(ctx, FOR ; err)
	{
		return err;
	}!;

	Node* node        = ctx.ast.alloc_node(FOR_STMT, start_pos);
	ForStmt* for_stmt = node.as(FOR_STMT);
	defer node.offset.end = ctx.current().pos;

	if (ctx.is(CONST_IDENT))
	{
		for_stmt.label = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
		@expect_else(ctx, COLON ; err)
		{
			ctx.skip_until({ EOS, EOF })!;
			return err;
		}!;
	}
	else
	{
		for_stmt.label = string_pool::EMPTY_STR;
	}

	@expect_else(ctx, LPAREN ; err)
	{
		ctx.skip_until({ RPAREN, EOS, EOF })!;
		return err;
	}!;

	if (!consume(ctx, EOS)!)
	{
		for_stmt.init.set(parse_expr_list(scope))!;
		@expect_else(ctx, EOS ; err)
		{
			return err;
		}!;
	}

	if (!consume(ctx, EOS)!)
	{
		for_stmt.cond.set(parse_cond_expr(scope))!;
		@expect_else(ctx, EOS ; err)
		{
			return err;
		}!;
	}

	if (!consume(ctx, RPAREN)!)
	{
		for_stmt.incr.set(parse_expr_list(scope))!;
		@expect_else(ctx, RPAREN ; err)
		{
			return err;
		}!;
	}

	Location prev_loc = ctx.line_map.resolve((sz)ctx.current().pos);
	for_stmt.body = parse_stmt(scope)!;
	Location body_loc = ctx.line_map.resolve((sz)for_stmt.body.offset.start);
	if (for_stmt.body.kind != COMPOUND_STMT && prev_loc.line != body_loc.line)
	{
		ctx.error("A single statement after 'for' must be placed on the same line, or be enclosed in {}");
		return ctx.ast.error(ctx.current().pos);
	}

	return node;
}

<*
 ct_for_stmt ::= '$for' ct_expression_list? ';' ct_cond? ';' ct_expression_list? ':' statement
*>
fn Node*? parse_ct_for_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	@expect_else(ctx, CT_FOR ; err)
	{
		return err;
	}!;

	Node* node        = ctx.ast.alloc_node(CT_FOR_STMT, start_pos);
	CtForStmt* for_stmt = node.as(CT_FOR_STMT);
	defer node.offset.end = ctx.current().pos;

	if (!consume(ctx, EOS)!)
	{
		for_stmt.init.set(parse_expr_list(scope))!;
		@expect_else(ctx, EOS ; err)
		{
			return err;
		}!;
	}

	if (!consume(ctx, EOS)!)
	{
		for_stmt.cond.set(parse_cond_expr(scope))!;
		@expect_else(ctx, EOS ; err)
		{
			return err;
		}!;
	}

	if (!consume(ctx, RPAREN)!)
	{
		for_stmt.incr.set(parse_expr_list(scope))!;
		@expect_else(ctx, RPAREN ; err)
		{
			return err;
		}!;
	}

	Location prev_loc = ctx.line_map.resolve((sz)ctx.current().pos);
	for_stmt.body = parse_stmt(scope)!;
	Location body_loc = ctx.line_map.resolve((sz)for_stmt.body.offset.start);
	if (for_stmt.body.kind != COMPOUND_STMT && prev_loc.line != body_loc.line)
	{
		ctx.error("A single statement after 'for' must be placed on the same line, or be enclosed in {}");
		return ctx.ast.error(ctx.current().pos);
	}

	return node;
}

<*
 while_stmt ::= 'while' LABEL? '(' cond_expr ')' statement
*>
fn Node*? parse_while_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	expect(ctx, WHILE);

	Node* node            = ctx.ast.alloc_node(WHILE_STMT, start_pos);
	WhileStmt* while_stmt = node.as(WHILE_STMT);
	defer node.offset.end = ctx.current().pos;

	if (ctx.is(CONST_IDENT))
	{
		while_stmt.label = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
		expect(ctx, COLON)!;
	}
	else
	{
		while_stmt.label = string_pool::EMPTY_STR;
	}
	expect(ctx, LPAREN)!;
	while_stmt.cond = parse_cond_expr(scope)!;
	expect(ctx, RPAREN)!;

	Location prev_loc = ctx.line_map.resolve((sz)ctx.current().pos);
	while_stmt.body = parse_stmt(scope)!;
	Location body_loc = ctx.line_map.resolve((sz)while_stmt.body.offset.start);
	if (while_stmt.body.kind != COMPOUND_STMT && prev_loc.line != body_loc.line)
	{
		ctx.error("A single statement after 'while' must be placed on the same line, or be enclosed in {}.");
		return ctx.ast.error(ctx.current().pos);
	}

	return node;
}

<*
 do_while_stmt ::= 'do' LABEL? compound_stmt ('while' '(' cond_expr ')')? ';'
*>
fn Node*? parse_do_while_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	@expect_else(ctx, DO ; err)
	{
		return err;
	}!;

	Node* node = ctx.ast.alloc_node(DO_WHILE_STMT, start_pos);
	defer node.offset.end = ctx.current().pos;
	DoWhileStmt* do_while_stmt = node.as(DO_WHILE_STMT);

	if (ctx.is(CONST_IDENT))
	{
		do_while_stmt.label = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
		@expect_else(ctx, COLON ; err)
		{
			ctx.skip_until({ EOS, EOF })!;
			return err;
		}!;
	}
	else
	{
		do_while_stmt.label = string_pool::EMPTY_STR;
	}

	do_while_stmt.body = parse_compound_stmt(scope)!;

	if (consume(ctx, WHILE)!)
	{
		@expect_else(ctx, LPAREN ; err)
		{
			return err;
		}!;
		do_while_stmt.cond.set(parse_cond_expr(scope)!);
		@expect_else(ctx, RPAREN ; err)
		{
			return err;
		}!;
	}

	@expect_else(ctx, EOS ; err)
	{
		return err;
	}!;

	return node;
}

fn Node*? parse_foreach_var(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos  = ctx.current().pos;
	Node* var_node = ctx.ast.alloc_node(VAR_DECL, start_pos);
	defer var_node.offset.end = ctx.current().pos;
	VarDecl* v = var_node.as(VAR_DECL);
	v.kind = VAR_LOCAL;

	// Parse optional type: if not a plain identifier or '&', a type is expected.
	if (!ctx.is(IDENT) && !ctx.is(AMP))
	{
		v.type = parse_type_expr(scope)!;
	}

	v.flags.is_ref = consume(ctx, AMP)!;

	if (!ctx.is(IDENT))
	{
		if (v.type != null)
		{
			ctx.error("Expected an identifier after the type.");
		}
		else
		{
			ctx.error("Expected an identifier or type.");
		}
		ctx.ast.missing(ctx.current().pos);
		v.name = string_pool::EMPTY_STR;
		ctx.skip_until({ COMMA, COLON, RPAREN })!;
		return var_node;
	}

	v.name = ctx.ast.string_pool.internalize(ctx.token_text(ctx.current()));
	advance(ctx)!;

	return var_node;
}

<*
 foreach_stmt ::= ("foreach" | "foreach_r") label? "(" foreach_vars ":" expression ")" statement
 foreach_vars ::= foreach_var ("," foreach_var)?
 foreach_var  ::= type? "&"? IDENTIFIER
*>
fn Node*? parse_foreach_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos   = ctx.current().pos;
	bool is_reverse = ctx.is(FOREACH_R);
	advance(ctx)!;

	Node* node                = ctx.ast.alloc_node(FOREACH_STMT, start_pos);
	ForeachStmt* foreach_stmt = node.as(FOREACH_STMT);
	defer node.offset.end = ctx.current().pos;
	foreach_stmt.is_reverse = is_reverse;

	if (ctx.is(CONST_IDENT))
	{
		foreach_stmt.label = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
		@expect_else_skip(ctx, COLON, { EOS, EOF } ; err)
		{
			return err;
		}!;
	}
	else
	{
		foreach_stmt.label = string_pool::EMPTY_STR;
	}

	@expect_else_skip(ctx, LPAREN, { RPAREN, EOS, EOF } ; err)
	{
		return err;
	}!;


	Node* idx_or_variable = parse_foreach_var(scope)!;
	VarDecl* var_decl     = idx_or_variable.as(VAR_DECL);

	if (consume(ctx, COMMA)!)
	{
		foreach_stmt.index = idx_or_variable;
		foreach_stmt.index_by_ref = var_decl.flags.is_ref;

		foreach_stmt.variable = parse_foreach_var(scope)!;
		var_decl = foreach_stmt.variable.as(VAR_DECL);
		foreach_stmt.value_by_ref = var_decl.flags.is_ref;
	}
	else
	{
		foreach_stmt.variable = idx_or_variable;
		foreach_stmt.value_by_ref = var_decl.flags.is_ref;
	}

	@expect_else_skip(ctx, COLON, { RPAREN, EOS, EOF } ; err)
	{
		return err;
	}!;

	foreach_stmt.enumeration = parse_expr(scope)!;

	@expect_else_skip(ctx, RPAREN, { EOS, EOF } ; err)
	{
		return err;
	}!;

	foreach_stmt.body = parse_stmt(scope)!;

	return node;
}

<*
 ct_assert_stmt ::= '$assert' constant_expression (":" constant_expression)? ";"
*>
fn Node*? parse_ct_assert_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	@expect_else_skip(ctx, CT_ASSERT, { EOS } ; missing)
	{
		return missing;
	}!;

	Node* node                   = ctx.ast.alloc_node(CT_ASSERT_STMT, start_pos);
	CtAssertStmt* ct_assert_stmt = node.as(CT_ASSERT_STMT);
	defer node.offset.end = ctx.current().pos;

	ct_assert_stmt.expr = parse_constant_expr(scope)!;
	if (consume(ctx, COLON)!)
	{
		ct_assert_stmt.msg_expr.set(parse_constant_expr(scope)!);
	}

	expect(ctx, EOS)!;

	return node;
}

<*
 ct_error_stmt ::= '$error' constant_expression ";"
*>
fn Node*? parse_ct_error_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	@expect_else(ctx, CT_ERROR ; err)
	{
		return err;
	}!;

	Node* node                 = ctx.ast.alloc_node(CT_ERROR_STMT, start_pos);
	CtErrorStmt* ct_error_stmt = node.as(CT_ERROR_STMT);
	defer node.offset.end = ctx.current().pos;

	ct_error_stmt.expr = parse_constant_expr(scope)!;

	@expect_else(ctx, EOS ; err)
	{
		return err;
	}!;

	return node;
}

<*
 ct_echo_stmt ::= '$echo' constant_expression ";"
*>
fn Node*? parse_ct_echo_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	@expect_else(ctx, CT_ECHO ; err)
	{
		return err;
	}!;

	Node* node               = ctx.ast.alloc_node(CT_ECHO_STMT, start_pos);
	CtEchoStmt* ct_echo_stmt = node.as(CT_ECHO_STMT);
	defer node.offset.end = ctx.current().pos;

	ct_echo_stmt.expr = parse_constant_expr(scope)!;

	@expect_else(ctx, EOS ; err)
	{
		return err;
	}!;

	return node;
}

<*
 defer_statement ::= "defer" defer_kind? statement
 defer_kind      ::= "try"
                  |  "catch"
                  |  "(" "catch" IDENTIFIER ")"
*>
fn Node*? parse_defer_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	expect(ctx, DEFER)!;
	Node* node     = ctx.ast.alloc_node(DEFER_STMT, start_pos);
	DeferStmt* def = node.as(DEFER_STMT);

	DeferKind kind = NORMAL;

	plog::debug("parse_defer");

	if CHECK: (consume(ctx, TRY)!)
	{
		kind = TRY;
	}
	else if (consume(ctx, CATCH)!)
	{
		kind = CATCH;
	}
	else if (ctx.is(LPAREN) && ctx.peek(1)!.kind == CATCH)
	{
		advance(ctx, 2)!; // ( and catch
		Token ident_token = ctx.current();
		Node* ident       = parse_expr(scope)!;
		if (ident.kind != IDENT_EXPR)
		{
			unexpected_at(ctx, ident_token, "Expected identifier here")!;
		}

		def.ident = ident;
		kind = CATCH_VAR;

		expect(ctx, RPAREN)!;
	}

	def.kind = kind;
	def.body = parse_stmt(scope)!;

	return node;
}

<*
 assert_stmt ::= ASSERT '(' assert_expr (',' expr)? ')' ';'
*>
fn Node*? parse_assert_stmt(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	expect(ctx, ASSERT)!;
	Node* node      = ctx.ast.alloc_node(ASSERT_STMT, start_pos);
	AssertStmt* ass = node.as(ASSERT_STMT);

	expect(ctx, LPAREN)!;
	ass.expr = parse_expr(scope)!;
	if (consume(ctx, COMMA)!)
	{
		ass.message = parse_constant_expr(scope)!;

		@pool()
		{
			List{Node*} args;
			args.tinit();

			while (!ctx.eof() && consume(ctx, COMMA)!)
			{
				args.push(parse_expr(scope)!);
			}

			ass.args = alloc::clone_slice(ctx.arena, args.array_view());
		};
	}
	expect(ctx, RPAREN)!;
	expect(ctx, EOS)!;
	return node;
}

<*
 ct_foreach_stmt ::= '$foreach' ct_foreach_vars ':' expression ':' statement* '$endforeach'
 ct_foreach_vars ::= CT_IDENT (',' CT_IDENT)?
*>
fn Node*? parse_ct_foreach_stmt(ContextScope scope) => @pool()
{
	ParseContext* ctx = scope.ctx;

	int start_pos = ctx.current().pos;
	@expect_else(ctx, CT_FOREACH ; err)
	{
		return err;
	}!;

	Node* node = ctx.ast.alloc_node(CT_FOREACH_STMT, start_pos);
	defer node.offset.end = ctx.current().pos;
	CtForeachStmt* ct_foreach_stmt = node.as(CT_FOREACH_STMT);

	Node* idx_or_variable = parse_ct_foreach_var(scope)!;
	if (consume(ctx, COMMA)!)
	{
		ct_foreach_stmt.index = idx_or_variable;
		ct_foreach_stmt.value = parse_ct_foreach_var(scope)!;
	}
	else
	{
		ct_foreach_stmt.value = idx_or_variable;
	}

	@expect_else_skip(ctx, COLON, { EOS, EOF, CT_ENDFOREACH } ; err)
	{
		return err;
	}!;

	ct_foreach_stmt.expr = parse_expr(scope)!;

	@expect_else_skip(ctx, COLON, { EOS, EOF, CT_ENDFOREACH } ; err)
	{
		return err;
	}!;

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ENDFOREACH))
	{
		stmts.push(parse_stmt(scope)!);
	}

	Node* body = ctx.ast.alloc_node(COMPOUND_STMT, start_pos);
	body.offset.end = ctx.current().pos;
	CompoundStmt* block = body.as(COMPOUND_STMT);
	block.statements = alloc::clone_slice(ctx.arena, stmts.array_view());
	ct_foreach_stmt.body = body;

	@expect_else(ctx, CT_ENDFOREACH ; err)
	{
		return err;
	}!;

	return node;
}

fn Node*? parse_ct_foreach_var(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;

	int start_pos  = ctx.current().pos;
	Node* node = ctx.ast.alloc_node(VAR_DECL, start_pos);
	defer node.offset.end = ctx.current().pos;
	VarDecl* var_decl = node.as(VAR_DECL);
	var_decl.kind = VAR_LOCAL;

	Token token = @expect_else_skip(ctx, CT_IDENT, { COMMA, COLON, EOS, EOF } ; err)
	{
		var_decl.name = string_pool::EMPTY_STR;
		return node;
	}!;

	var_decl.name = ctx.ast.string_pool.internalize(ctx.token_text(token));
	return node;
}
