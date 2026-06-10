module parser::parser;

import parser::ast;
import lexer;
import parser::constants;

import std::collections::list;

fn Node*? parse_stmt(ParseContext* ctx)
{
	Token t = ctx.current();

	if (is_type(ctx) || t.kind == TLOCAL || t.kind == STATIC)
	{
		return parse_decl_stmt(ctx)!;
	}

	switch (t.kind)
	{
		case LBRACE:
			return parse_compound_stmt(ctx)!;
		case SWITCH:
			return parse_switch_stmt(ctx)!;
		case CONTINUE:
		case BREAK:
			return parse_continue_break_stmt(ctx)!;
		case NEXTCASE:
			return parse_nextcase_stmt(ctx)!;
		case RETURN:
			return parse_return_stmt(ctx)!;
		case CT_SWITCH:
			return parse_ct_switch_stmt(ctx)!;
		case IF:
			return parse_if_stmt(ctx)!;
		case CT_IF:
			return parse_ct_if_stmt(ctx)!;
		case FOR:
			return parse_for_stmt(ctx)!;
		case WHILE:
			return parse_while_stmt(ctx)!;
		case FOREACH:
		case FOREACH_R:
			return parse_foreach_stmt(ctx)!;
		case CT_ASSERT:
			return parse_ct_assert_stmt(ctx)!;
		case CT_ERROR:
			return parse_ct_error_stmt(ctx)!;
		case CT_ECHO:
			return parse_ct_echo_stmt(ctx)!;
		case VAR:
			return parse_var_decl(ctx, null, { .is_var = true, .is_local = true });
		case CONST:
			advance(ctx)!;
			return parse_var_decl(ctx, null, { .is_const = true, .is_local = true })!;
		case STATIC:
			advance(ctx)!;
			return parse_var_decl(ctx, null, { .is_static = true, .is_local = true })!;
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
			return parse_expr_stmt(ctx)!;
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
fn Node*? parse_expr_stmt(ParseContext* ctx)
{
	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(EXPR_STMT, start_pos);
	ExprStmt* es  = node.as(EXPR_STMT);
	defer node.end_token = ctx.peek(0).pos;
	es.expr_stmt = parse_expr(ctx)!;
	@expect_else(ctx, EOS ; err)
	{
		return err;
	}!;
	return node;
}

<*
 decl_stmt ::= expr ';' | decl
*>
fn Node*? parse_decl_stmt(ParseContext* ctx)
{
	int start_pos = ctx.current().pos;

	ParseFlags flags;
	flags.is_static = consume(ctx, STATIC)!;
	flags.is_tlocal = consume(ctx, TLOCAL)!;

	Node* type = parse_type_expr(ctx)!;
	switch (ctx.current().kind)
	{
		case IDENT:
		case CT_IDENT:
			return parse_var_decl(ctx, type, flags);
		default:
	}

	Node* expr = parse_expr_resuming_with_left(ctx, type, LOWEST)!;
	expect(ctx, EOS)!;
	return expr;
}

<*
 compound_stmt ::= ('{' stmt* '}')
*>
fn Node*? parse_compound_stmt(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	expect(ctx, LBRACE)!;
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

	expect(ctx, RBRACE)!;

	block.statements = alloc::clone_slice(ctx.arena, temp_stmts.array_view());

	return node;
}

<*
 switch_body ::= '{' (case_stmt | nextcase_stmt | default_stmt)* '}'
*>
fn bool? parse_switch_body(ParseContext* ctx, List{Node*}* cases)
{
	int start_pos = ctx.peek(0).pos;
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
				result = parse_case_stmt(ctx)!;
				if (result.kind == ERROR) return false;
			case DEFAULT:
				result = parse_default_stmt(ctx)!;
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
fn Node*? parse_case_stmts(ParseContext* ctx, sz row) => @pool()
{
	if (token_type_ends_case(ctx.current().kind))
	{
		Location next_loc = ctx.line_map.resolve(ctx.current().pos);

		if (next_loc.line > row + 1 && ctx.current().kind != RBRACE)
		{
			ctx.error(
				"Fallthrough cases with empty rows or comments have unclear meaning, " "an explicit 'break' or 'nextcase' is needed (or remove the spacing)."
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
		Node* child_stmt = parse_stmt(ctx)!;
		if (child_stmt.kind == ERROR) return child_stmt;
		stmts.push(child_stmt);
	}

	compound.statements = alloc::clone_slice(ctx.arena, stmts.array_view());
	compound_node.end_token = ctx.peek(0).pos;

	return compound_node;
}

<*
 case_stmt ::= 'case' expr ('..' expr)? ':' stmt*

*>
fn Node*? parse_case_stmt(ParseContext* ctx, ParseFlags flags = { }) => @pool()
{
	int pos            = ctx.current().pos;
	TokenKind expected = flags.is_comptime ? CT_CASE : CASE;
	@expect_else(ctx, expected ; err)
	{
		return err;
	}!;

	Location loc = ctx.line_map.resolve((sz)pos);
	sz case_row  = loc.line;

	Node* node = ctx.ast.alloc_node(CASE_STMT, pos);
	defer node.end_token = ctx.peek(0).pos;
	CaseStmt* case_stmt = node.as(CASE_STMT);

	case_stmt.expr = parse_expr(ctx)!;
	if (consume(ctx, DOTDOT)!)
	{
		case_stmt.to_expr = parse_expr(ctx)!;
	}
	@expect_else(ctx, COLON ; err)
	{
		return err;
	}!;

	case_stmt.body = parse_case_stmts(ctx, case_row)!;

	return node;
}

<*
 default_stmt ::= default | $default ':' case_stmts
*>
fn Node*? parse_default_stmt(ParseContext* ctx, ParseFlags flags = { })
{
	int start_pos      = ctx.peek(0).pos;
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
	defer node.end_token = ctx.peek(0).pos;

	Location loc = ctx.line_map.resolve((sz)start_pos);
	sz row       = loc.line;

	sw.body = parse_case_stmts(ctx, row)!;

	return node;
}

<*
 nextcase_stmt ::= NEXTCASE ((CONST_IDENT ':')? expression)? ';'
*>
fn Node*? parse_nextcase_stmt(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;
	@expect_else(ctx, NEXTCASE ; err)
	{
		return err;
	}!;

	Node* node       = ctx.ast.alloc_node(NEXTCASE_STMT, start_pos);
	NextcaseStmt* nc = node.as(NEXTCASE_STMT);
	defer node.end_token = ctx.peek(0).pos;

	if (consume(ctx, EOS)!)
	{
		return node;
	}
	if (ctx.is(CONST_IDENT) && ctx.peek(1).kind == COLON)
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
		nc.expr = parse_expr(ctx)!;
	}
	return node;
}

<*
 continue_break_stmt ::= continue | break LABEL? ';'
*>
fn Node*? parse_continue_break_stmt(ParseContext* ctx)
{
	int start_pos    = ctx.peek(0).pos;
	bool is_continue = consume(ctx, CONTINUE)!;
	if (!is_continue) consume(ctx, BREAK)!;

	Node* node            = ctx.ast.alloc_node(CONTINUE_BREAK_STMT, start_pos);
	ContinueBreakStmt* cb = node.as(CONTINUE_BREAK_STMT);
	defer node.end_token = ctx.peek(0).pos;

	cb.is_continue = is_continue;
	cb.label = ast::EMPTY_STR;

	if (ctx.is(CONST_IDENT))
	{
		cb.label = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
	}

	@expect_else(ctx, EOS ; err)
	{
		return err;
	}!;

	return node;
}

<*
 switch ::= switch LABEL? ('(' cond ')')? switch_body
*>
fn Node*? parse_switch_stmt(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	@expect_else(ctx, SWITCH ; err)
	{
		return err;
	}!;

	Node* node     = ctx.ast.alloc_node(SWITCH_STMT, start_pos);
	SwitchStmt* sw = node.as(SWITCH_STMT);
	defer node.end_token = ctx.peek(0).pos;

	if (ctx.is(CONST_IDENT))
	{
		Token label_tok = ctx.peek(0);
		sw.label = ctx.ast.string_pool.internalize(ctx.token_text(label_tok));
		advance(ctx)!;
		expect(ctx, COLON)!;
	}

	if (consume(ctx, LPAREN)!)
	{
		sw.cond = parse_cond_expr(ctx)!;
		@expect_else(ctx, RPAREN ; err)
		{
			return err;
		}!;
	}

	@expect_else(ctx, LBRACE ; err)
	{
		return err;
	}!;

	List{Node*} bodies;
	bodies.tinit();
	bool success = parse_switch_body(ctx, &bodies)!;
	if (!success)
	{
		ctx.skip_until({ RBRACE, EOF })!;
	}
	@expect_else(ctx, RBRACE ; err)
	{
		return err;
	}!;

	sw.cases = alloc::clone_slice(ctx.arena, bodies.array_view());
	return node;
}

<*
 return_stmt ::= return expression | return ';'
*>
fn Node*? parse_return_stmt(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;
	@expect_else(ctx, RETURN ; err)
	{
		return err;
	}!;

	Node* node      = ctx.ast.alloc_node(RETURN_STMT, start_pos);
	ReturnStmt* ret = node.as(RETURN_STMT);
	defer node.end_token = ctx.peek(0).pos;

	if (!ctx.is(EOS))
	{
		ret.expr = parse_expr(ctx)!;
	}

	@expect_else(ctx, EOS ; err)
	{
		return err;
	}!;

	return node;
}

<*
 ct_switch_stmt ::= CT_SWITCH const_expr? ':' ct_case_statement* CT_ENDSWITCH
 ct_case_statement ::= (CT_CASE constant_expr | CT_DEFAULT) ':' opt_stmt_list
*>
fn Node*? parse_ct_switch_stmt(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	@expect_else(ctx, CT_SWITCH ; err)
	{
		return err;
	}!;

	Node* node       = ctx.ast.alloc_node(CT_SWITCH_STMT, start_pos);
	CtSwitchStmt* cs = node.as(CT_SWITCH_STMT);
	defer node.end_token = ctx.peek(0).pos;

	if (!ctx.is(COLON))
	{
		if (ctx.is(CT_CASE))
		{
			ctx.error("Expected ':' after $switch");
			return ctx.ast.error(ctx.current().pos);
		}

		cs.cond = parse_constant_expr(ctx)!;
	}

	@expect_else(ctx, COLON ; err)
	{
		return err;
	}!;

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ENDSWITCH))
	{
		TokenKind kind = ctx.current().kind;
		log::debug("parse_ct_switch_stmt - kind: %s", kind.description);
		switch (kind)
		{
			case CT_CASE:
				stmts.push(parse_case_stmt(ctx, { .is_comptime = true })!);
			case CT_DEFAULT:
				stmts.push(parse_default_stmt(ctx, { .is_comptime = true })!);
			default:
				ctx.error("'$case' or '$default' expected");
				return ctx.ast.error(ctx.current().pos);
		}
	}

	@expect_else(ctx, CT_ENDSWITCH ; err)
	{
		return err;
	}!;

	cs.cases = alloc::clone_slice(ctx.arena, stmts.array_view());
	return node;
}

<*
 if_stmt ::= IF LABEL? '(' cond_expr ')' compound_stmt (ELSE compound_stmt)?
	| IF LABEL? '(' cond_expr ')' statement
*>
fn Node*? parse_if_stmt(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;
	@expect_else(ctx, IF ; err)
	{
		return err;
	}!;

	Node* node      = ctx.ast.alloc_node(IF_STMT, start_pos);
	IfStmt* if_stmt = node.as(IF_STMT);
	defer node.end_token = ctx.peek(0).pos;

	if (ctx.is(CONST_IDENT))
	{
		if_stmt.label = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
		@expect_else(ctx, COLON ; err)
		{
			ctx.skip_until({ EOS, EOF, RBRACE })!;
			return err;
		}!;
	}

	@expect_else(ctx, LPAREN ; err)
	{
		ctx.skip_until({ EOS, EOF, RBRACE })!;
		return err;
	}!;

	if_stmt.condition = parse_cond_expr(ctx)!;

	@expect_else(ctx, RPAREN ; err)
	{
		ctx.skip_until({ EOS, EOF, RBRACE })!;
		return err;
	}!;

	if_stmt.then_body = parse_stmt(ctx)!;

	if (consume(ctx, ELSE)!)
	{
		if_stmt.else_body = parse_stmt(ctx)!;
	}

	return node;
}

<*
 ct_if_statement ::= "$if" constant_expression ":" statement* ("$else" statement*)? "$endif"
*>
fn Node*? parse_ct_if_stmt(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	@expect_else(ctx, CT_IF ; err)
	{
		return err;
	}!;

	Node* node        = ctx.ast.alloc_node(CT_IF_STMT, start_pos);
	CtIfStmt* if_stmt = node.as(CT_IF_STMT);
	defer node.end_token = ctx.peek(0).pos;

	if_stmt.expr = parse_expr(ctx)!;
	@expect_else(ctx, COLON ; err)
	{
		ctx.skip_until({ EOS, EOF, RBRACE })!;
		return err;
	}!;

	List{Node*} stmts;
	stmts.tinit();
	while (!ctx.eof() && !ctx.is(CT_ELSE) && !ctx.is(CT_ENDIF))
	{
		stmts.push(parse_stmt(ctx)!);
	}

	if_stmt.then_stmts = alloc::clone_slice(ctx.arena, stmts.array_view());
	if (ctx.is(CT_ELSE))
	{
		advance(ctx)!;
		stmts.clear();
		while (!ctx.eof() && !ctx.is(CT_ELSE) && !ctx.is(CT_ENDIF))
		{
			stmts.push(parse_stmt(ctx)!);
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
 for_stmt ::= 'if' LABEL? '(' expression_list? ';' cond? ';' expression_list? ')' statement
*>
fn Node*? parse_for_stmt(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;
	@expect_else(ctx, FOR ; err)
	{
		return err;
	}!;

	Node* node        = ctx.ast.alloc_node(FOR_STMT, start_pos);
	ForStmt* for_stmt = node.as(FOR_STMT);
	defer node.end_token = ctx.peek(0).pos;

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
		for_stmt.label = ast::EMPTY_STR;
	}

	@expect_else(ctx, LPAREN ; err)
	{
		ctx.skip_until({ RPAREN, EOS, EOF })!;
		return err;
	}!;

	if (!consume(ctx, EOS)!)
	{
		for_stmt.init.set(parse_expr_list(ctx))!;
		@expect_else(ctx, EOS ; err)
		{
			return err;
		}!;
	}

	if (!consume(ctx, EOS)!)
	{
		for_stmt.cond.set(parse_cond_expr(ctx))!;
		@expect_else(ctx, EOS ; err)
		{
			return err;
		}!;
	}

	if (!consume(ctx, RPAREN)!)
	{
		for_stmt.incr.set(parse_expr_list(ctx))!;
		@expect_else(ctx, RPAREN ; err)
		{
			return err;
		}!;
	}

	Location prev_loc = ctx.line_map.resolve((sz)ctx.current().pos);
	for_stmt.body = parse_stmt(ctx)!;
	Location body_loc = ctx.line_map.resolve((sz)for_stmt.body.start_token);
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
fn Node*? parse_while_stmt(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;
	@expect_else(ctx, WHILE ; err)
	{
		return err;
	}!;

	Node* node            = ctx.ast.alloc_node(WHILE_STMT, start_pos);
	WhileStmt* while_stmt = node.as(WHILE_STMT);
	defer node.end_token = ctx.peek(0).pos;

	if (ctx.is(CONST_IDENT))
	{
		while_stmt.label = ctx.ast.string_pool.internalize(ctx.current_text());
		advance(ctx)!;
		@expect_else(ctx, COLON ; err)
		{
			ctx.skip_until({ EOS, EOF })!;
			return err;
		}!;
	}
	@expect_else(ctx, LPAREN ; err)
	{
		return err;
	}!;
	while_stmt.cond = parse_cond_expr(ctx)!;
	@expect_else(ctx, RPAREN ; err)
	{
		return err;
	}!;

	Location prev_loc = ctx.line_map.resolve((sz)ctx.current().pos);
	while_stmt.body = parse_stmt(ctx)!;
	Location body_loc = ctx.line_map.resolve((sz)while_stmt.body.start_token);
	if (while_stmt.body.kind != COMPOUND_STMT && prev_loc.line != body_loc.line)
	{
		ctx.error("A single statement after 'while' must be placed on the same line, or be enclosed in {}.");
		return ctx.ast.error(ctx.current().pos);
	}

	return node;
}

fn Node*? parse_foreach_var(ParseContext* ctx)
{
	int start_pos  = ctx.peek(0).pos;
	Node* var_node = ctx.ast.alloc_node(VAR_DECL, start_pos);
	defer var_node.end_token = ctx.peek(0).pos;
	VarDecl* v = var_node.as(VAR_DECL);
	v.kind = VAR_LOCAL;

	// Parse optional type: if not a plain identifier or '&', a type is expected.
	if (!ctx.is(IDENT) && !ctx.is(AMP))
	{
		v.type = parse_type_expr(ctx)!;
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
		ctx.ast.missing(ctx.peek(0).pos);
		v.name = ast::EMPTY_STR;
		ctx.skip_until({ COMMA, COLON, RPAREN })!;
		return var_node;
	}

	v.name = ctx.ast.string_pool.internalize(ctx.token_text(ctx.peek(0)));
	advance(ctx)!;

	return var_node;
}

<*
 foreach_stmt ::= ("foreach" | "foreach_r") label? "(" foreach_vars ":" expression ")" statement
 foreach_vars ::= foreach_var ("," foreach_var)?
 foreach_var  ::= type? "&"? IDENTIFIER
*>
fn Node*? parse_foreach_stmt(ParseContext* ctx)
{
	int start_pos   = ctx.peek(0).pos;
	bool is_reverse = ctx.is(FOREACH_R);
	advance(ctx)!;

	Node* node                = ctx.ast.alloc_node(FOREACH_STMT, start_pos);
	ForeachStmt* foreach_stmt = node.as(FOREACH_STMT);
	defer node.end_token = ctx.peek(0).pos;
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
		foreach_stmt.label = ast::EMPTY_STR;
	}

	@expect_else_skip(ctx, LPAREN, { RPAREN, EOS, EOF } ; err)
	{
		return err;
	}!;


	Node* idx_or_variable = parse_foreach_var(ctx)!;
	VarDecl* var_decl     = idx_or_variable.as(VAR_DECL);

	if (consume(ctx, COMMA)!)
	{
		foreach_stmt.index = idx_or_variable;
		foreach_stmt.index_by_ref = var_decl.flags.is_ref;

		foreach_stmt.variable = parse_foreach_var(ctx)!;
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

	foreach_stmt.enumeration = parse_expr(ctx)!;

	@expect_else_skip(ctx, RPAREN, { EOS, EOF } ; err)
	{
		return err;
	}!;

	foreach_stmt.body = parse_stmt(ctx)!;

	return node;
}

<*
 ct_assert_stmt ::= '$assert' constant_expression (":" constant_expression)? ";"
*>
fn Node*? parse_ct_assert_stmt(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	@expect_else_skip(ctx, CT_ASSERT, { EOS } ; missing)
	{
		return missing;
	}!;

	Node* node                   = ctx.ast.alloc_node(CT_ASSERT_STMT, start_pos);
	CtAssertStmt* ct_assert_stmt = node.as(CT_ASSERT_STMT);
	defer node.end_token = ctx.peek(0).pos;

	ct_assert_stmt.expr = parse_constant_expr(ctx)!;
	if (consume(ctx, COLON)!)
	{
		ct_assert_stmt.msg_expr.set(parse_constant_expr(ctx)!);
	}

	expect(ctx, EOS)!;

	return node;
}

<*
 ct_error_stmt ::= '$error' constant_expression ";"
*>
fn Node*? parse_ct_error_stmt(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	@expect_else(ctx, CT_ERROR ; err)
	{
		return err;
	}!;

	Node* node                 = ctx.ast.alloc_node(CT_ERROR_STMT, start_pos);
	CtErrorStmt* ct_error_stmt = node.as(CT_ERROR_STMT);
	defer node.end_token = ctx.peek(0).pos;

	ct_error_stmt.expr = parse_constant_expr(ctx)!;

	@expect_else(ctx, EOS ; err)
	{
		return err;
	}!;

	return node;
}

<*
 ct_echo_stmt ::= '$echo' constant_expression ";"
*>
fn Node*? parse_ct_echo_stmt(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	@expect_else(ctx, CT_ECHO ; err)
	{
		return err;
	}!;

	Node* node               = ctx.ast.alloc_node(CT_ECHO_STMT, start_pos);
	CtEchoStmt* ct_echo_stmt = node.as(CT_ECHO_STMT);
	defer node.end_token = ctx.peek(0).pos;

	ct_echo_stmt.expr = parse_constant_expr(ctx)!;

	@expect_else(ctx, EOS ; err)
	{
		return err;
	}!;

	return node;
}
