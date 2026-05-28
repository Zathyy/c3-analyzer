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
	import_decl ::= import path_expr ';' attributes?
*>
fn Node*? parse_import_decl(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;
	if (!expect(ctx, IMPORT)!)
	{
		return ctx.ast.alloc_node(ERROR, start_pos);
	}

	Node* node = ctx.ast.alloc_node(IMPORT_DECL, start_pos);
	ImportDecl* imp = node.as_import();
	defer node.end_token = ctx.peek(0).pos;

	imp.path = parse_path_expr(ctx, false)!;
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