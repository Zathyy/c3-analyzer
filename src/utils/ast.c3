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
            io::printf("<INVALID> : %s\n", diagnostics::get_string(decl.span));
			break;
		}
        case FUNC:
        {
            (void)io::printf("FuncDecl: %s\n", decl.name);

            String child_prefix = make_child_prefix(prefix, is_last);
            print_func_decl(decl, child_prefix);
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
		case VAR:
		{
			(void)io::print("VarDecl: ");
			print_type(decl.var_decl.type_info);
            io::printfn(" %s", decl.name);

			if (decl.var_decl.init_expr)
			{
				String child_prefix = make_child_prefix(prefix, is_last);
				print_expr(decl.var_decl.init_expr, child_prefix, false);
			}

            break;
		}
		case ALIAS:
		{
			(void)io::printf("AliasDecl: %s = ", decl.name);

			switch (decl.alias_decl.kind)
			{
				case AliasKind.DEFINE:
					break;
				case AliasKind.FUNC:
					break;
				case AliasKind.MODULE:
					break;			
				case AliasKind.TYPE:
					print_type(decl.alias_decl.type.type_info);
					break;
			}

			io::print("\n");

            break;
		}
		case TYPEDEF:
		{
			(void)io::printf("TypedefDecl: %s = ", decl.name);
			print_type(decl.typedef_decl.type);
			io::printn();
            break;
		}
		default:
			unreachable("missing print_decl case: %s", decl.kind);
    }
}

fn void print_func_decl(Decl* decl, String prefix)
{
    print_prefix(prefix, false);
    io::print("RetType: ");
    print_type(decl.func.ret_type);
    io::printn("");

    print_prefix(prefix, false);
    io::print("Args:\n");

    String arg_prefix = make_child_prefix(prefix, false);

    if (decl.func.params.len() == 0)
    {
        print_prefix(arg_prefix, true);
        io::print("<none>\n");
    }
    else
    {
        for (usz i = 0; i < decl.func.params.len(); i++)
        {
            bool is_last_param = (i == decl.func.params.len() - 1);
            Decl* param = decl.func.params[i];

            print_prefix(arg_prefix, is_last_param);
            io::printf("Param: %s (Type: ", param.name);
            print_type(param.var_decl.type_info);
            io::print(")\n");
        }
    }

    if (decl.func.compound != null)
    {
        print_stmt(decl.func.compound, prefix, true);
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

            if (stmt.return_stmt.expr != null)
            {
                String child_prefix = make_child_prefix(prefix, is_last);
                print_expr(stmt.return_stmt.expr, child_prefix, true);
            }
            break;
        }
		case DEFER: 
		{
            io::printfn("DeferStmt: is_catch = %s", stmt.defer_stmt.is_catch);
			
			if (stmt.defer_stmt.stmt)
			{
                String child_prefix = make_child_prefix(prefix, is_last);
				print_stmt(stmt.defer_stmt.stmt, child_prefix, true);
			}
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
			String child_prefix = make_child_prefix(prefix, true);
       		print_decl(stmt.decl_stmt.decl, child_prefix, true);
			break;
		}
		case EXPR:
		{
			io::printn("ExprStmt");
			String child_prefix = make_child_prefix(prefix, true);
       		print_expr(stmt.expr_stmt.expr, child_prefix, true);
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
        case ExprKind.INTEGER:
            io::printf("Literal (Int): %s\n", expr.value);
            break;
        case ExprKind.STRING:
            io::printf("Literal (Int): %s\n", expr.value);
            break;
        case ExprKind.IDENTIFIER:
            io::printf("IdentExpr: %s\n", expr.value);
            break;

        case ExprKind.TYPE:
        {
            io::print("TypeExpr: ");
            print_type(expr.type_expr.type); 
            io::print("\n");
            break;
        }

        case ExprKind.BINARY:
        {
            io::printf("BinaryExpr (%s)\n", expr.binary_expr.op);
            String child_prefix = make_child_prefix(prefix, is_last);
            print_expr(expr.binary_expr.left, child_prefix, false);
            print_expr(expr.binary_expr.right, child_prefix, true);
            break;
        }

        case ExprKind.CALL:
        {
            io::print("CallExpr\n");
            String child_prefix = make_child_prefix(prefix, true);
            
            print_expr(expr.call_expr.callee, child_prefix, expr.call_expr.args.len() == 0);
            
            for (usz i = 0; i < expr.call_expr.args.len(); i++)
            {
                bool arg_is_last = (i == expr.call_expr.args.len() - 1);
                print_expr(expr.call_expr.args[i], child_prefix, arg_is_last);
            }
            break;
        }
		case ExprKind.UNARY:
		{
			io::printf("UnaryExpr (%s)\n", expr.unary_expr.op);
			
			String child_prefix = make_child_prefix(prefix, is_last);
			print_expr(expr.unary_expr.rhs, child_prefix, true); 
			break;
		}

        default:
            io::printf("Missing case for: Expr (Kind: %s)\n", expr.kind);
            break;
    }
}

fn void print_expr_inline(Expr* expr)
{
    switch (expr.kind)
    {
        case INTEGER:
            io::printf("%s", expr.value);
            break;
        case IDENTIFIER:
            io::printf("%s", expr.value);
            break;
        case TYPE:
            print_type(expr.type_expr.type);
            break;
        default:
            io::print("<expr>");
            break;
    }
}

fn void print_type(TypeInfo* info)
{
    if (info == null) 
	{
        io::print("null");
        return;
    }

    switch (info.kind)
    {
        case TypeInfoKind.IDENTIFIER:
            TypeInfoIdent* d = (TypeInfoIdent*)info.data;
            io::printf("%s", d.name);
            break;

        case TypeInfoKind.POINTER:
            TypeInfoPtr* d = (TypeInfoPtr*)info.data;
            print_type(d.base);
            io::print("*");
            break;

        case TypeInfoKind.ARRAY:
            TypeInfoArray* d = (TypeInfoArray*)info.data;
            print_type(d.base);
            io::print("[");
            if (d.length_expr) print_expr(d.length_expr, "", true); // Print the 10+5
            io::print("]");
            break;

        case TypeInfoKind.GENERIC:
            TypeInfoGeneric* d = (TypeInfoGeneric*)info.data;
            print_type(d.base); // The "Foo"
            io::print("{");
	
			foreach (param : d.params)
			{
				print_expr_inline(param);
			}

            io::print("}");
            break;
            
        case TypeInfoKind.FUNCTION:
            TypeInfoFunc* d = (TypeInfoFunc*)info.data;
            io::print("fn ");
            print_type(d.return_info);
            io::print("(");
            // Loop through param_types...
            io::print(")");
            break;
		default:
			return;
    }
    
    if (info.is_optional) io::print("?");
}