module utils::ast;

import c3_parser::ast;
import lexer;
import std::io;
import string_pool;
import c3_parser::common;

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

fn void dump(Ast* ast, StringPool* strings_pool) => @pool()
{
	pool = strings_pool;

    if (ast.top_level_nodes.len() == 0)
    {
        io::printn("<empty ast>");
        return;
    }

    for (uint i = 0; i < ast.top_level_nodes.len(); i++)
    {
        bool is_last = (i == ast.top_level_nodes.len() - 1);
        print_node(ast, (Node)ast.top_level_nodes[i], "", is_last);
    }
}

fn void print_node(Ast* ast, Node handle, String prefix, bool is_last)
{
    if (!handle.is_valid()) return;
	assert(pool != null);

    NodeView node = ast::get_node(ast, handle);
    String child_prefix = make_child_prefix(prefix, is_last);

    print_prefix(prefix, is_last);

    switch (node.kind)
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
		case NodeKind.TYPE_EXPR:
            TypeView tv = (TypeView){ ast, handle };
			io::print("Type: ");
            io::print(tv.name(pool));

            // Print pointers (e.g., **)
            for (uint i = 0; i < tv.ptr_count(); i++) io::print("*");

            // Print array size if it exists
            Node array_expr = tv.array_size();
            if (array_expr.is_valid()) 
            {
                io::print("[");
				if (tv.is_vector()) io::print("<");
                print_node(ast, array_expr, child_prefix, false);
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
                    print_node(ast, tv.get_gen_arg(i), child_prefix, false);
                    if (i < g_count - 1) io::print(", ");
                }
                io::print("}");
            }
			io::printn();
            break;

        case NodeKind.MODULE_DECL:
        {
            ModuleView v = { ast, handle };
            io::printn("ModuleDecl");
            print_node(ast, v.path(), child_prefix, true);
            break;
        }

        case NodeKind.IMPORT_DECL:
        {
            ImportView v = { ast, handle };
            io::printn("ImportDecl");
            print_node(ast, v.path(), child_prefix, true);
            break;
        }

       	case NodeKind.FN_DECL:
		{
			FnView v = { ast, handle };
			io::printfn("FnDecl: %s", v.name(pool));

			uint param_count = v.param_count();
			bool has_body = v.body().is_valid();

			print_node(ast, v.return_type(), child_prefix, param_count == 0 && !has_body);

			for (uint i = 0; i < param_count; i++)
			{
				bool is_last_p = (i == param_count - 1) && !has_body;
				print_node(ast, v.get_param(i), child_prefix, is_last_p);
			}

			if (has_body)
			{
				print_node(ast, v.body(), child_prefix, true);
			}
			break;
		}
		case NodeKind.PARAM_DECL:
		{
			ParamView pv = { ast, handle };
			io::printfn("Param: %s", pv.get_name(pool));
			print_node(ast, pv.get_type(), child_prefix, true);
			break;
		}
		case NodeKind.TYPEDEF_DECL:
		{
			TypedefView v = { ast, handle };
			io::printfn("Typedef: %s", v.name(pool));
			print_node(ast, v.base_type(), child_prefix, true);
			break;
		}
		case NodeKind.GLOBAL_DECL:
		{
			GlobalView gv = { ast, handle };
			GlobalFlags gf = gv.flags();

			io::print("Global: ");
			if (gf.is_extern) io::print("extern ");
			if (gf.is_const)  io::print("const ");
			if (gf.is_thread_local) io::print("tlocal ");
			io::printfn("%s", gv.name(pool));

			Node init = gv.init_expr();
			bool has_init = init.is_valid();

			print_node(ast, gv.type_node(), child_prefix, !has_init);
			
			if (has_init)
			{
				print_node(ast, init, child_prefix, true);
			}
			break;
		}
		case NodeKind.ALIAS_DECL:
		{
			AliasView v = { ast, handle };
			io::printfn("Alias: %s", v.name(pool));
			print_node(ast, v.target_type(), child_prefix, true);
			break;
		}
        case NodeKind.INT_LITERAL:
			LiteralView v = { ast, handle };
            io::printfn("Literal (Int): %s", v.value(pool));
            break;

        case NodeKind.FLOAT_LITERAL:
			LiteralView v = { ast, handle };
            io::printfn("Literal (Float): %s", v.value(pool));
            break;

        case NodeKind.STRING_LITERAL:
			LiteralView v = { ast, handle };
            io::printfn("Literal (String): \"%s\"", v.value(pool));
            break;

        case NodeKind.IDENT_EXPR:
			IdentView v = { ast, handle };
            io::printfn("IdentExpr: %s", v.name(pool));
            break;

        case NodeKind.BINARY_EXPR:
        {
            BinaryView v = { ast, handle };
            io::printfn("BinaryExpr (%s)", v.op());
            
            print_node(ast, v.left(), child_prefix, false);
            print_node(ast, v.right(), child_prefix, true);
            break;
        }

        case NodeKind.UNARY_EXPR:
        {
            UnaryView v = { ast, handle };
            io::printfn("UnaryExpr (%s)", v.op());
            print_node(ast, v.rhs(), child_prefix, true);
            break;
        }

        case NodeKind.CALL_EXPR:
        {
            CallView v = { ast, handle };
            uint count = v.arg_count();
            
            io::printn("CallExpr");
            print_node(ast, v.callee(), child_prefix, count == 0);

            for (uint i = 0; i < count; i++)
            {
                bool arg_last = (i == count - 1);
                print_node(ast, v.get_arg(i), child_prefix, arg_last);
            }
            break;
        }

        case NodeKind.TERNARY_EXPR:
        {
            TernaryView v = { ast, handle };
            io::printn("TernaryExpr");
            print_node(ast, v.condition(), child_prefix, false);
            print_node(ast, v.then_expr(), child_prefix, false);
            print_node(ast, v.else_expr(), child_prefix, true);
            break;
        }

        case NodeKind.EXPR_STMT:
        {
            io::printn("ExprStmt");
			ExprStmtView esv = { ast, handle };
            print_node(ast, esv.expr(), child_prefix, true);
            break;
        }

        case NodeKind.RETURN_STMT:
        {
            io::printn("ReturnStmt");
			ReturnView rv = { ast, handle };
            Node expr = rv.expr();
            if (expr.is_valid())
            {
                print_node(ast, expr, child_prefix, true);
            }
            break;
        }

        case NodeKind.IF_STMT:
		{
			IfView v = { ast, handle };
			Node else_blk = v.else_block();
			bool has_else = else_blk.is_valid();

			io::printn("IfStmt");

			print_node(ast, v.condition(), child_prefix, false);
			
			print_prefix(child_prefix, !has_else);
			io::printn("Then:");
			print_node(ast, v.then_block(), make_child_prefix(child_prefix, !has_else), true);

			if (has_else)
			{
				print_prefix(child_prefix, true);
				io::printn("Else:");
				print_node(ast, else_blk, make_child_prefix(child_prefix, true), true);
			}
			break;
		}
        case NodeKind.VAR_DECL_STMT:
        {
            VarDeclView v = { ast, handle };
            io::printfn("VarDeclStmt: %s", v.name(pool));
	
			Node init_expr = v.init_expr();
            print_node(ast, v.type_node(), child_prefix, !init_expr.is_valid());
            
            if (init_expr.is_valid())
            {
                print_node(ast, init_expr, child_prefix, true);
            }
            break;
        }

        case NodeKind.COMPOUND_STMT:
        {
            CompoundView v = { ast, handle };
            uint count = v.len();

            io::printfn("CompoundStmt (%d stmts)", count);
            for (uint i = 0; i < count; i++)
            {
                bool stmt_last = (i == count - 1);
                print_node(ast, v.get(i), child_prefix, stmt_last);
            }
            break;
        }

        default:
            io::printfn("Unknown Node (Kind: %s)", node.kind);
            break;
    }
}