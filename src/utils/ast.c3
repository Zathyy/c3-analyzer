module utils::ast;

import c3_parser::ast;
import c3_parser::common;
import string_pool;

import std::io;
import std::collections::list;
import std::collections::maybe;

fn void dump(Ast* ast, StringPool* pool)
{
	io::printn("Tree");
	foreach (i, node : ast.top_level_nodes)
	{
		bool is_last = (i == ast.top_level_nodes.len() - 1);		
		print_node(ast, pool, (Node)node, "", is_last);
	}
}

fn void print_node(Ast* ast, StringPool* pool, Node handle, String prefix, bool is_last)
{
    NodeKind kind = ast::get_kind(ast, handle);

    io::print(prefix);
    io::print(is_last ? "└── " : "├── ");
    
    String new_prefix = string::tformat("%s%s", prefix, is_last ? "    " : "│   ");
    defer new_prefix.free(tmem);

    switch (kind)
    {
		case NodeKind.MODULE_DECL:
			io::printn("ModuleDecl");
			ModuleView mv = (ModuleView){ ast, handle };
			print_node(ast, pool, mv.path(), new_prefix, true);
			break;
		case NodeKind.IMPORT_DECL:
			io::printn("ImportDecl");
			ImportView mv = (ImportView){ ast, handle };
			print_node(ast, pool, mv.path(), new_prefix, true);
			break;
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
            io::printn("ForStmt");
            ForView v = (ForView){ ast, handle };
            print_node(ast, pool, v.init(), new_prefix, is_last);
            print_node(ast, pool, v.cond(), new_prefix, is_last);
            print_node(ast, pool, v.inc(), new_prefix, is_last);
            print_node(ast, pool, v.body(), new_prefix, is_last);

        case NodeKind.COMPOUND_STMT:
            io::printn("CompoundStmt");
            CompoundView v = (CompoundView){ ast, handle };
            for (uint i = 0; i < v.len(); i++)
            {
                print_node(ast, pool, v.get(i), new_prefix, is_last);
            }

        case NodeKind.RETURN_STMT:
            // For simple nodes with 1 child, we can just use a helper
            Node expr = (Node)ast.extra_data[ast.extra_indices[(usz)handle]];
            io::print("RETURN ");
            print_node(ast, pool, expr, new_prefix, is_last); 
            io::printn("");

        default:
            io::printfn("<Node:%s>", kind);
    }
}