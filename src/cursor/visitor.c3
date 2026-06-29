module analyzer::cursor;

import analyzer::workspace;
import analyzer::core;

enum ChildVisitResult : int
{
	BREAK,    // Terminate the entire walk
	CONTINUE, // Continue to the next sibling
	RECURSE   // Dive into the children of the current node
}

alias CursorVisitor = fn ChildVisitResult(Cursor cursor, Cursor parent, void* user_data, args...);

// Helper to visit a node if it's valid
fn bool visit(Cursor child, Cursor parent, CursorVisitor visitor, void* data)
{
	ChildVisitResult res = visitor(child, parent, data);
	if (res == ChildVisitResult.BREAK) return false; // Stop the whole walk

	if (res == ChildVisitResult.RECURSE)
	{
		// Recursively visit the children of this child
		if (!visit_children(child, visitor, data)) return false;
	}

	return true; // Continue to next sibling
}

<*
 Visit children
 returns false if a break was requested
 @require parent.section != null
 @param parent : "The Cursor to visit children on"
 @param visitor : "visitor function that will be invoked for all children of 'parent'"
 @param data : "user data to be passed around"
*>
fn bool visit_children(Cursor parent, CursorVisitor visitor, void* data)
{
	if (!parent.is_valid()) return true;
	Node* node = parent.node;
	ModuleSection* sec = parent.section;

	switch (node.kind)
	{
		case FN_DECL:
		{
			FnDecl* fndecl = node.as(FN_DECL);
			if (fndecl.associated_type && !visit({sec, fndecl.associated_type}, parent, visitor, data)) return false;
			if (fndecl.ret_type && !visit({sec, fndecl.ret_type}, parent, visitor, data)) return false;
			foreach (param : fndecl.params)
			{
				if (!visit({sec, param}, parent, visitor, data)) return false;
			}
			if (fndecl.body && !visit({sec, fndecl.body}, parent, visitor, data)) return false;
			break;
		}
		
		case COMPOUND_STMT:
		{
			CompoundStmt* comp = node.as(COMPOUND_STMT);
			foreach (stmt : comp.statements)
			{
				if (!visit({sec, stmt}, parent, visitor, data)) return false;
			}
			break;
		}

		case EXPR_STMT:
		{
			ExprStmt* expr = node.as(EXPR_STMT);
			if (expr.expr_stmt && !visit({sec, expr.expr_stmt}, parent, visitor, data)) return false;
			break;
		}

		case ACCESS_EXPR:
		{
			AccessExpr* access = node.as(ACCESS_EXPR);
			if (access.left && !visit({sec, access.left}, parent, visitor, data)) return false;
			if (access.member && !visit({sec, access.member}, parent, visitor, data)) return false;
			break;
		}

		case BINARY_EXPR:
		{
			BinaryExpr* bin = node.as(BINARY_EXPR);
			if (bin.left && !visit({sec, bin.left}, parent, visitor, data)) return false;
			if (bin.right && !visit({sec, bin.right}, parent, visitor, data)) return false;
			break;
		}

		case VAR_DECL:
		{
			VarDecl* vardecl = node.as(VAR_DECL);
			if (vardecl.type && !visit({sec, vardecl.type}, parent, visitor, data)) return false;
			if (vardecl.init_expr && !visit({sec, vardecl.init_expr}, parent, visitor, data)) return false;
			break;
		}

		case RETURN_STMT:
		{
			ReturnStmt* stmt = node.as(RETURN_STMT);
			if (stmt.expr && !visit({sec, stmt.expr}, parent, visitor, data)) return false;
			break;
		}

		default:
			break;
	}

	return true;
}
