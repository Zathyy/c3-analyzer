module analyzer::parser::decl;

<*
 fn_decl ::= fn type_expr (type_expr '.')? ident '(' parameter_list? ')' attributes?
 fn_body ::= ('=>' short_body) | compound_stmt
*>
fn Node*? parse_fn_decl(ContextScope scope)
{
	int start_pos = ctx.current().pos;

	expect(ctx, FN)!;

	plog::debug("parse_fn");

	Node* node   = ctx.ast.alloc_node(FN_DECL, start_pos);
	FnDecl* func = node.as(FN_DECL);

	func.ret_type = parse_type_expr(ctx)!;

	if IS_TYPE: (is_type(ctx))
	{
		if (flags.is_interface)
		{
			unexpected(ctx, "Interfaces cant be methods");
			advance(ctx)!;
			break IS_TYPE;
		}

		plog::error("parse_fn - set associated: %s", ctx.token_text(ctx.current()));

		func.associated_type = parse_type_expr(ctx)!;

		expect(ctx, DOT)!;

		Token t = @expect_else_skip(ctx, IDENT, { EOS, LPAREN } ; err)
		{
			ctx.error("Expected member function name identifier");
			func.name = string_pool::EMPTY_STR;
			break IS_TYPE;
		}!;
		func.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}
	else
	{
		// Standalone Function: No associated type prefix
		Token t = @expect_else_skip(ctx, IDENT, { EOS, LPAREN } ; err)
		{
			ctx.error("Expected function name identifier");
			func.name = string_pool::EMPTY_STR;
			break IS_TYPE;
		}!;
		func.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
	}

	func.params = parse_parameter_list(ctx)!;

	if (ctx.is(AT_IDENT))
	{
		func.attributes = parse_attributes(ctx, node)!;
	}

	if (ctx.is(LBRACE))
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have a structural block body");
			return ctx.ast.error(start_pos);
		}

		if (flags.is_interface)
		{
			ctx.error("Interface methods cannot have a body");
			return ctx.ast.error(start_pos);
		}

		func.body = parse_compound_stmt(ctx)!;
		node.offset.end = func.body.offset.end;
	}
	else if (consume(ctx, IMPLIES)!)
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have an expression body");
			return ctx.ast.error(start_pos);
		}

		func.body = parse_short_body(ctx, true)!;
		node.offset.end = func.body.offset.end;
	}
	else
	{
		// No body provided
		node.offset.end = ctx.current().pos;
		expect(ctx, EOS)!;
	}

	return node;
}