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

fn void print_node(Ast* ast, StringPool* pool, Node handle, String prefix, bool is_last, bool is_inline = false)
{
	if (!handle.is_valid())
	{
		io::printn("<null>");
        return;
	}

	NodeView node_view = ast::get_node(ast, handle);
    NodeKind kind = node_view.kind;

	if (!is_inline)
	{
		io::print(prefix);
		io::print(is_last ? "└── " : "├── ");
	}

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
		case NodeKind.FN_DECL:
			FnView fv = (FnView){ ast, handle };
            String name = fv.name(pool);
            io::printfn("FnDecl: %s", name);

            io::print(new_prefix);
            io::print("├── Return: ");
            print_node(ast, pool, fv.return_type(), new_prefix, false, true);
            io::printn();

            uint p_count = fv.param_count();
            for (uint i = 0; i < p_count; i++)
            {
                io::print(new_prefix);
                io::print("├── Param: ");
                print_node(ast, pool, fv.get_param(i), new_prefix, false, true);
                io::printn();
            }

            print_node(ast, pool, fv.body(), new_prefix, true);
            break;
        case NodeKind.FOR_STMT:
            io::printn("ForStmt");
            ForView v = (ForView){ ast, handle };
            print_node(ast, pool, v.init(), new_prefix, is_last);
            print_node(ast, pool, v.cond(), new_prefix, is_last);
            print_node(ast, pool, v.inc(), new_prefix, is_last);
            print_node(ast, pool, v.body(), new_prefix, is_last);
			break;
        case NodeKind.COMPOUND_STMT:
            io::printn("CompoundStmt");
            CompoundView v = (CompoundView){ ast, handle };
            for (uint i = 0; i < v.len(); i++)
            {
                print_node(ast, pool, v.get(i), new_prefix, is_last);
            }
			break;
        case NodeKind.RETURN_STMT:
            Node expr = (Node)ast.extra_data[ast.extra_indices[(usz)handle]];
            io::print("RETURN ");
            print_node(ast, pool, expr, new_prefix, is_last); 
            io::printn("");
			break;
		case NodeKind.TYPE:
            TypeView tv = (TypeView){ ast, handle };
			if (!is_inline)
			{
            	io::print("Type: ");
			}
            io::print(tv.name(pool));

            // Print pointers (e.g., **)
            for (uint i = 0; i < tv.ptr_count(); i++) io::print("*");

            // Print array size if it exists
            Node array_expr = tv.array_size();
            if (array_expr.is_valid()) 
            {
                io::print("[");
				if (tv.is_vector()) io::print("<");
                print_node(ast, pool, array_expr, new_prefix, false);
				if (tv.is_vector()) io::print(">");
                io::print("]");
            }

            // Print generics if any: {T, U}
            uint g_count = tv.gen_count();
            if (g_count > 0)
            {
                io::print("{");
                for (uint i = 0; i < g_count; i++)
                {
                    print_node(ast, pool, tv.get_gen_arg(i), new_prefix, false);
                    if (i < g_count - 1) io::print(", ");
                }
                io::print("}");
            }
			if (!is_inline)
			{
            	io::printn();
			}
            break;

        case NodeKind.PARAM_DECL:
            ParamView pv = (ParamView){ ast, handle };
            print_node(ast, pool, pv.get_type(), " ", true, true);
			if (is_inline)
			{
            	io::printf(" %s", pv.get_name(pool));
			}
			else
			{
            	io::printf("Param: %s : ", pv.get_name(pool));
			}
            break;
		case NodeKind.ALIAS_DECL:
			AliasView av = (AliasView){ ast, handle };
			io::printfn("Alias: %s", av.name(pool));
			io::print(new_prefix);
			io::print("└── Target: ");
			print_node(ast, pool, av.target_type(), new_prefix, true, true);
			io::printn();
			break;
		case NodeKind.TYPEDEF_DECL:
			TypedefView tv = (TypedefView){ ast, handle };
			io::printfn("Typedef (Distinct): %s", tv.name(pool));
			io::print(new_prefix);
			io::print("└── Base: ");
			print_node(ast, pool, tv.base_type(), new_prefix, true, true);
			io::printn();
			break;
		case NodeKind.GLOBAL_DECL:
            GlobalView gv = (GlobalView){ ast, handle };
            GlobalFlags gf = gv.flags();

			io::print("Global: ");

            if (gf.is_extern) io::print("extern ");
            if (gf.is_const)  io::print("const ");
            if (gf.is_thread_local)  io::print("tlocal ");
            print_node(ast, pool, gv.type_node(), "", true, true);
            io::printf(" %s", gv.name(pool));
            
            Node init = gv.init_expr();
            if (init.is_valid())
            {
                io::print(" = ");
                print_node(ast, pool, init, "", true, true);
            }
            io::printn();
            break;
		default:
            io::printfn("<Node:%s>", kind);
    }
}