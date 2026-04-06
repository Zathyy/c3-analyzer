module utils::ast;

import c3_parser::ast;
import lexer;
import std::io;
import string_pool;
import c3_parser::common;
import c3_parser::workspace;
import c3_parser::cursor;

StringPool* pool @local;

fn void print_prefix(String prefix, bool is_last)
{
    io::print(prefix);
    if (is_last) 
	{
		io::print("└─ ");
	}
    else        
	{
		io::print("├─ ");
	}
}

fn String make_child_prefix(String prefix, bool is_last)
{
    if (is_last) 
	{
		return prefix.tconcat("   ");
	}
    else         
	{
		return prefix.tconcat("│  ");
	}
}

struct PrintContext
{
    uint depth;
	String prefix;
    StringPool* strings;
}

fn ChildVisitResult printer_callback(Cursor c, Cursor p, void* data, bool is_last)
{
  	PrintContext* ctx = (PrintContext*)data;

    print_prefix(ctx.prefix, is_last);

    NodeView v = ast::get_node(&c.mod.ast, c.node);
    String name = cursor::spelling(&c) ?? "";
    io::printfn("%s: %s : Idx = %s", v.kind.nameof, name, c.node);

    String old_prefix = ctx.prefix;

    ctx.prefix = make_child_prefix(old_prefix, is_last);
    switch (v.kind)
	{
		case NodeKind.INT_LITERAL:
		case NodeKind.FLOAT_LITERAL:
		case NodeKind.IDENT_EXPR:
			return ChildVisitResult.CONTINUE; 

		default:
			cursor::visit_children(c, (CursorVisitor)&printer_callback, ctx);
	}
	ctx.prefix = old_prefix;

    return ChildVisitResult.CONTINUE;
}

fn void dump_workspace(Workspace* ws)
{
    ws.modules.@each(; name, mod)
    {
        io::printfn("=== Module: %s ===", mod.name);
		io::printfn("=== Num module sections: %s ===", mod.sections.len());
        
        PrintContext ctx = { .depth = 0, .strings = mod.strings };
        
        foreach (i, root_node : mod.ast.top_level_nodes)
        {
			bool is_last = (i == mod.ast.top_level_nodes.len() - 1);
            Cursor c = { mod, (Node)root_node };

			log::debug("Node belongs to: (%s)", cursor::file_path(&c));
			log::debug("Node belongs to module_decl: (%s)", cursor::module_decl(&c));

            printer_callback(c, {null, 0}, &ctx, is_last);
        }
    };
}







