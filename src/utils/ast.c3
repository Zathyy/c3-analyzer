module utils::ast;

import c3_parser::ast;
import c3_parser::common;
import string_pool;

import std::io;
import std::collections::list;
import std::collections::maybe;

fn void dump(Ast* ast, StringPool* pool)
{
	foreach (i, node : ast.kinds)
	{
		io::printf("dump - %s\n", node);
		print_node(ast, pool, (Node)i, 0);
	}
}

fn void print_node(Ast* ast, StringPool* pool, Node handle, int indent)
{
    NodeKind kind = ast::get_kind(ast, handle);
    for (int i = 0; i < indent; i++) io::print("  ");

    switch (kind)
    {
		case NodeKind.PATH:
			PathView v = (PathView){ ast, handle };
			io::print("Path: ");
			for (uint i = 0; i < v.len(); i++)
			{
				uint sh = v.get_string_handle(i);
				io::print(pool.get(sh)); 
				
				if (i < v.len() - 1) io::print("::");
			}
			io::printn();
			break;
        case NodeKind.FOR_STMT:
            io::printn("FOR_LOOP");
            ForView v = (ForView){ ast, handle };
            print_node(ast, pool, v.init(), indent + 1);
            print_node(ast, pool, v.cond(), indent + 1);
            print_node(ast, pool, v.inc(),  indent + 1);
            print_node(ast, pool, v.body(), indent + 1);

        case NodeKind.COMPOUND_STMT:
            io::printn("Compound {");
            CompoundView v = (CompoundView){ ast, handle };
            for (uint i = 0; i < v.len(); i++)
            {
                print_node(ast, pool, v.get(i), indent + 1);
            }
            io::printn("}");

        case NodeKind.RETURN_STMT:
            // For simple nodes with 1 child, we can just use a helper
            Node expr = (Node)ast.extra_data[ast.extra_indices[(usz)handle]];
            io::print("RETURN ");
            print_node(ast, pool, expr, 0); 
            io::printn("");

        default:
            io::printfn("<Node:%s>", kind);
    }
}