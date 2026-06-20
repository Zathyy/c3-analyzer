module analyzer::parser;

import analyzer::core;

<*
 fn_decl ::= fn type_expr (type_expr '.')? ident '(' parameter_list? ')' attributes?
 fn_body ::= ('=>' short_body) | compound_stmt
*>
fn Node*? parse_fn_decl(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	int start_pos = ctx.current_pos();

	expect(ctx, FN)!;

	plog::debug("parse_fn");

	Node* node = scope.ctx.ast.alloc_node(FN_DECL, start_pos);
	FnDecl* func = node.as(FN_DECL);

	if (catch parse_fn_name_and_type(scope, func))
	{
		ctx.skip_until({ LPAREN, LBRACE, RBRACE, EOS })!;
	}

	func.params = parse_parameter_list(scope.with_flags({ .is_function = true }))!;

	if (ctx.is(AT_IDENT))
	{
		func.attributes = parse_attributes(scope, node)!;
	}

	if (catch parse_fn_body(scope, func, node))
	{
		ctx.skip_until({ RBRACE, EOS })!;
	}

	return node;
}

fn void? parse_fn_name_and_type(ContextScope scope, FnDecl* func) @local 
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	func.ret_type = parse_type_expr(scope)!;

	if IS_TYPE: (is_type(ctx))
	{
		if (flags.is_interface)
		{
			unexpected(ctx, "Interfaces cant be methods");
			return UNEXPECTED_TOKEN~;			
		}

		plog::debug("parse_fn - set associated: %s", ctx.token_text(ctx.current()));

		func.associated_type = parse_type_expr(scope)!;

		expect(ctx, DOT)!;

		Token t = @expect_else(ctx, IDENT ; err)
		{
			return UNEXPECTED_TOKEN~;
		}!;

		func.name = parse_identifier(scope, t);
	}
	else
	{
		Token t = @expect_else(ctx, IDENT ; err)
		{
			return UNEXPECTED_TOKEN~;
		}!;

		func.name = parse_identifier(scope, t);
	}
}

fn void? parse_fn_body(ContextScope scope, FnDecl* func, Node* node) @local
{
	ParseContext* ctx = scope.ctx;
	ParseFlags flags = scope.flags;

	int start_pos = ctx.current_pos();
	if (scope.ctx.is(LBRACE))
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have a structural block body");
			ctx.ast.error(start_pos);
			return UNEXPECTED_TOKEN~;			
		}

		if (flags.is_interface)
		{
			ctx.error("Interface methods cannot have a body");
			ctx.ast.error(start_pos);
			return UNEXPECTED_TOKEN~;			
		}

		func.body = parse_compound_stmt(scope)!;
		node.offset.end = func.body.offset.end;
	}
	else if (consume(ctx, IMPLIES)!)
	{
		if (flags.is_extern)
		{
			ctx.error("Extern functions cannot have an expression body");
			ctx.ast.error(start_pos);
			return UNEXPECTED_TOKEN~;			
		}

		func.body = parse_short_body(scope, true)!;
		node.offset.end = func.body.offset.end;
	}
	else
	{
		// No body provided
		node.offset.end = ctx.current().pos;
		expect(ctx, EOS)!;
	}
}
