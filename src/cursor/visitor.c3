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
    return true;
}