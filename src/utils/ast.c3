module utils::ast;

import c3_parser::ast;
import c3_parser::common;
import c3_parser::diagnostics;

import std::io;
import std::collections::list;

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

fn void indent(int depth) @private
{
    for (int i = 0; i < depth; i++)
    {
        io::print("  ");
    }
}

fn void dump(Ast* ast) => @pool()
{
	int count = (int)ast.decls.len();

   	for (int i = 0; i < count; i++)
    {
        bool is_last = (i == count - 1);
        print_decl(ast.decls[i], "", is_last);
    }
}

fn void print_decl(Decl* decl, String prefix, bool is_last)
{
    print_prefix(prefix, is_last);

    switch (decl.kind)
    {
		case INVALID:
		{
            io::print("<INVALID>\n");
			String child_prefix = make_child_prefix(prefix, false);
			(void)io::printf("%s", child_prefix);
			break;
		}
        case FUNC:
        {
            (void)io::printf("FuncDecl: %s\n", decl.name);

            String child_prefix = make_child_prefix(prefix, is_last);
            print_func_decl(&decl.func, child_prefix);
            break;
        }
        case MODULE:
        {
            (void)io::printf("ModuleDecl: %s\n", decl.mod.path.name);
            break;
        }
        case IMPORT:
        {

            (void)io::printf("ImportDecl: %s\n", decl.imp.path.name);
            break;
        }
		default:
			unreachable("missing print_decl case: %s", decl.kind);
    }
}

fn void print_func_decl(FuncDecl* decl, String prefix)
{
    int child_count = FuncDecl.membersof.len;

    // --- Return Type ---
    print_prefix(prefix, false);
    (void)io::printfn("RetType: %s", decl.ret_type);

    // --- Args ---
    print_prefix(prefix, false);
    (void)io::printfn("Args: %s", decl.args);

    if (decl.compound != null)
    {
		print_stmt(decl.compound, prefix, true);
    }
}

fn void print_stmt(Stmt* stmt, String prefix, bool is_last)
{
    print_prefix(prefix, is_last);

    switch (stmt.kind)
    {
		case INVALID:
		{
            io::printf("<INVALID> : %s\n", diagnostics::get_string(stmt.span));
			break;
		}
        case RETURN:
        {
            io::print("ReturnStmt\n");

			String child_prefix = make_child_prefix(prefix, is_last);
			(void)io::printf("%s", child_prefix);
		
            break;
        }
		case COMPOUND:
		{   
			io::print("CompoundStmt\n");

			usz len = stmt.compound.stmts.len();
			String child_prefix = make_child_prefix(prefix, is_last);

			for (usz i = 0; i < len; i++)
			{
				bool stmt_is_last = i == len - 1;
				print_stmt(stmt.compound.stmts[i], child_prefix, stmt_is_last);
			}
			break;
		}
		case DECL:
		{
			io::printn("DeclStmt");
			String child_prefix = make_child_prefix(prefix, false);
       		(void)io::printf("%s", child_prefix);
			
			io::printf("%s", stmt.decl_stmt.decl.name);

			break;
		}
        default:
            io::print("Stmt\n");
            break;
    }
}

fn void print_expr(Expr* expr, String prefix, bool is_last)
{
    print_prefix(prefix, is_last);

    switch (expr.kind)
    {
        default:
            io::print("Expr\n");
            break;
    }
}