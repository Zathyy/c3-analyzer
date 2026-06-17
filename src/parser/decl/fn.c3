module analyzer::parser::decl;

import analyzer::core;

<*
 fn_decl ::= fn type_expr (type_expr '.')? ident '(' parameter_list? ')' attributes?
 fn_body ::= ('=>' short_body) | compound_stmt
*>
fn Node*? parse_fn_decl(ContextScope scope)
{
	int start_pos = scope.ctx.current_pos();
	ParseContext* ctx = scope.ctx;

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
		func.attributes = parse_attributes(ctx, node)!;
	}

	if (catch parse_fn_body(scope, func))
	{
		ctx.skip_until({ RBRACE, EOS })!;
	}

	return node;
}

fn void? parse_fn_name_and_type(ContextScope scope, FnDecl* func) @local 
{
	func.ret_type = parse_type_expr(ctx)!;
	ParseContext* ctx = scope.ctx;

	if IS_TYPE: (is_type(ctx))
	{
		if (flags.is_interface)
		{
			unexpected(ctx, "Interfaces cant be methods");
			return UNEXPECTED_TOKEN~;			
		}

		plog::debug("parse_fn - set associated: %s", ctx.token_text(ctx.current()));

		func.associated_type = parse_type_expr(ctx)!;

		expect(ctx, DOT)!;

		Token t = @expect_else(ctx, IDENT)
		{
			return UNEXPECTED_TOKEN~;
		};

		func.name = parse_identifier(ctx, t);
	}
	else
	{
		Token t = @expect_else(ctx, IDENT)
		{
			return UNEXPECTED_TOKEN~;
		};

		func.name = parse_identifier(ctx, t);
	}
}

fn void? parse_fn_body(ContextScope scope, FnDecl* func) @local
{
	if (scope.ctx.is(LBRACE))
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
}
