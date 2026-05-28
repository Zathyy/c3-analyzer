module parser::parser;
import parser::ast;
import lexer;

import parser::common;
import parser::constants;
import std::collections::list;
import parser::workspace @norecurse;
import std::io;

<*
	module_decl ::= module path_expr ';' attributes?
*>
fn Node*? parse_module_decl(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;
	if (!expect(ctx, MODULE)!)
	{
		return ctx.ast.alloc_node(ERROR, start_pos);
	}

	log::debug("parse_mod");


	Node* node = ctx.ast.alloc_node(MODULE_DECL, start_pos);
	ModuleDecl* mod = node.as(MODULE_DECL);
	defer node.end_token = ctx.peek(0).pos;

	mod.path = parse_path_expr(ctx, false)!;
	if (!expect(ctx, EOS)!)
    {
        node.kind = MISSING;
    }

	if (ctx.is(AT_IDENT)) 
    {
		//TODO:
        //mod.attributes = parse_attributes(ctx)!;
    }

	return node;
}

<*
	import_decl ::= import path_expr (',' path_expr)* ';' attributes?
*>
fn Node*? parse_import_decl(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.peek(0).pos;
	if (!expect(ctx, IMPORT)!)
	{
		return ctx.ast.alloc_node(ERROR, start_pos);
	}

	Node* node = ctx.ast.alloc_node(IMPORT_DECL, start_pos);
	ImportDecl* imp = node.as(IMPORT_DECL);
	defer node.end_token = ctx.peek(0).pos;

	List{Node*} temp_paths;
    temp_paths.init(tmem, 4);

	while (true)
    {
        Node* path_node = parse_path_expr(ctx, false)!;
        temp_paths.push(path_node);

        if (!consume(ctx, COMMA)!) break;
        if (ctx.is(EOS))
        {
            ctx.error("Expected an import path after ','");
            temp_paths.push(ctx.ast.alloc_node(MISSING, ctx.peek(0).pos));
            break;
        }
    }

	imp.paths = alloc::clone_slice(ctx.arena, temp_paths.array_view());

	if (!expect(ctx, EOS)!)
    {
        node.kind = MISSING;
    }

	if (ctx.is(AT_IDENT)) 
    {
		//TODO:
        //mod.attributes = parse_attributes(ctx)!;
    }

	return node;
}

<*
	fn_decl ::= fn type_expr (type_expr '.')? ident '(' parameter_list? ')' attributes?
	fn_body ::= ('=>' short_body) | compound_stmt
*>
fn Node*? parse_fn_decl(ParseContext* ctx, ParseFlags flags = {})
{
	int start_pos = ctx.peek(0).pos;
	if (!expect(ctx, FN)!)
	{
		return ctx.ast.alloc_node(ERROR, start_pos);
	}

	log::debug("parse_fn");

	Node* node = ctx.ast.alloc_node(FN_DECL, start_pos);
	FnDecl* func = node.as(FN_DECL);
	defer node.end_token = ctx.peek(0).pos;

	func.ret_type = parse_type_expr(ctx)!;

	if (is_type(ctx))
    {
        func.associated_type = parse_type_expr(ctx)!;
        
        if (!expect(ctx, DOT)!)
        {
            node.kind = MISSING;
        }

        if (!ctx.is(IDENT))
        {
            ctx.error("Expected member function name identifier");
            func.name = -1;
            return ctx.ast.alloc_node(ERROR, start_pos);
        }

        Token t = ctx.peek(0);
        func.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
        advance(ctx)!;
    }
    else
    {
        // Standalone Function: No associated type prefix
        func.associated_type = null;

        if (!ctx.is(IDENT))
        {
            ctx.error("Expected function name identifier");
            return ctx.ast.alloc_node(ERROR, start_pos);
        }

        Token t = ctx.peek(0);
        func.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
        advance(ctx)!;
    }
	
	func.params = parse_parameter_list(ctx)!;

	if (ctx.is(LBRACE))
    {
        if (flags.is_extern)
        {
            ctx.error("Extern functions cannot have a structural block body");
            return ctx.ast.alloc_node(ERROR, start_pos);
        }
        func.body = parse_compound_stmt(ctx)!;
    }
    else if (consume(ctx, IMPLIES)!)
    {
        if (flags.is_extern)
        {
            ctx.error("Extern functions cannot have an expression body");
            return ctx.ast.alloc_node(ERROR, start_pos);
        }

        func.body = parse_expr(ctx)!;

        // Clean statement ending validation
        if (!node_ends_with_block(ctx, func.body))
        {
            if (!expect(ctx, EOS)!) 
            {
                node.kind = MISSING;
            }
        }
    }
    else
    {
        // No body provided
        if (!expect(ctx, EOS)!)
        {
            node.kind = MISSING;
        }
    }

	return node;
}

<*
    param_decl ::= type_expr ELLIPSIS? (non_type_ident ('=' expr))?
                | ELLIPSIS (CT_TYPE_IDENT | non_type_ident ('=' expr)?)?
    @param [&inout] ctx
*>
fn Node*? parse_param_decl(ParseContext* ctx)
{
    int start_pos = ctx.peek(0).pos;

    Node* node = ctx.ast.alloc_node(PARAM_DECL, start_pos);
    ParamDecl* param = node.as(PARAM_DECL);
    defer node.end_token = ctx.peek(0).pos;

    param.type = parse_type_expr(ctx)!;

	if (consume(ctx, ELLIPSIS)!)
    {
        param.is_variadic = true;

        // Check if a compile-time type or identifier follows: (CT_TYPE_IDENT | non_type_ident)
        if (ctx.is(CT_TYPE_IDENT) || is_non_type_ident(ctx.current().kind))
        {
            Token t = ctx.peek(0);
            param.ident_kind = t.kind;
            param.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
            advance(ctx)!;

            // Handle optional default value assignment ('=' expr)
            if (consume(ctx, EQ)!)
            {
                param.default_value = parse_expr(ctx)!;
            }
        }

        return node;
    }

	param.type = parse_type_expr(ctx)!;

	// Check for optional trailing ellipsis (e.g., "int... values")
    if (consume(ctx, ELLIPSIS)!)
    {
        param.is_variadic = true;
    }
 
    if (is_non_type_ident(ctx.current().kind))
    {
        Token t = ctx.peek(0);
        param.ident_kind = t.kind;
        param.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
        advance(ctx)!;

        // Handle optional default value assignment ('=' expr)
        if (consume(ctx, EQ)!)
        {
            param.default_value = parse_expr(ctx)!;
        }
    }

    return node;
}
