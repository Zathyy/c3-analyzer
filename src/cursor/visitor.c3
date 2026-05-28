module parser::cursor;

import parser::workspace;
import parser::ast;

import std::io;


enum ChildVisitResult : int
{
	BREAK,
	// Terminate the entire walk
	CONTINUE,
	// Continue to the next sibling
	RECURSE
	// Dive into the children of the current node
}

alias CursorVisitor = fn ChildVisitResult(Cursor cursor, Cursor parent, void* user_data, args...);

struct Cursor
{
	ModuleSection* section;
	Node* node;
}

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
	if (parent.node.kind != TYPE_EXPR)
    {
        // TODO: Map out other AST types like PARAM_DECL, FUNCTION_DECL, etc.
        return true; 
    }

    TypeExpr* type_data = parent.node.as(TYPE_EXPR);

    switch (type_data.kind)
    {
        case TYPE_IDENTIFIER:
            // Identifiers are leaf nodes or contain a single path expression node child
            if (type_data.unresolved.path != null)
            {
                Cursor path_child = { .section = parent.section, .node = type_data.unresolved.path };
                if (!visit(path_child, parent, visitor, data)) return false;
            }
            break;

        case TYPE_POINTER:
        case TYPE_SLICE:
            // Dive straight down into the single wrapped modifier base
            Cursor base_child = { .section = parent.section, .node = type_data.modify.base };
            if (!visit(base_child, parent, visitor, data)) return false;
            break;

        case TYPE_ARRAY:
            // Arrays contain two distinct children: the base type and the dimension size expression
            Cursor base_child = { .section = parent.section, .node = type_data.array.base };
            if (!visit(base_child, parent, visitor, data)) return false;

            Cursor len_child = { .section = parent.section, .node = type_data.array.len_expr };
            if (!visit(len_child, parent, visitor, data)) return false;
            break;

        case TYPE_GENERIC:
            // First step down into the core generic template blueprint definition (e.g., List)
            Cursor base_child = { .section = parent.section, .node = type_data.generic.base };
            if (!visit(base_child, parent, visitor, data)) return false;

            // Iterate across the compiled slice parameter expressions list
            for (sz i = 0; i < type_data.generic.params.len; i++)
            {
                Cursor param_child = { .section = parent.section, .node = type_data.generic.params[i] };
                if (!visit(param_child, parent, visitor, data)) return false;
            }
            break;
    }

    return true;
}