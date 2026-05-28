module parser::ast;
import lexer;

import std::collections::list;

struct IfStmt
{
	Node* condition;
	Node* then_block;
	Node* else_block;
}

struct CompoundStmt
{
	NodeArray statements;
}

<* @require self.kind == COMPOUND_STMT *>
fn CompoundStmt* Node.as_compound(&self) @inline 
{ 
	return &self.compound_stmt;
}