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

	Node* node = ctx.ast.alloc_node(MODULE_DECL, start_pos);
	ModuleDecl* mod = node.as_module();
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
	ImportDecl* imp = node.as_import();
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