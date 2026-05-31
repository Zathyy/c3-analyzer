module parser::ast;
import lexer;

import std::collections::list;

struct IfStmt
{
	Node* condition;
	Node* then_body;
	Node* else_body;
	StringID label;
}

struct CtIfStmt
{
	Node* expr;
	NodeArray then_stmts;
	NodeArray else_stmts;
}

struct CompoundStmt
{
	NodeArray statements;
}

struct SwitchStmt
{
	NodeArray cases;
	Node* cond;
	StringID label;
}

<*
 - expr: 
 - to_expr: 
 - body: compound_stmt
*>
struct CaseStmt
{
	Node* expr;
	Node* to_expr;
	Node* body;
}

<*
 -body: compound_stmt
*>
struct DefaultStmt
{
	Node* body;
}

struct NextcaseStmt
{
	Node* expr;
	StringID label;
	bool is_default;
}

struct ContinueBreakStmt
{
	StringID label;
	bool is_continue;
}

struct ReturnStmt
{
	Node* expr;
}

struct CtSwitchStmt
{
	Node* cond;
	NodeArray cases;
}

struct ExprStmt
{
	Node* expr_stmt;
}

<*
 - init: expr_list?
 - cond: cond_expr?
 - incr: cond_ist?
 - body: stmt
 - label: optional label
*>
struct ForStmt
{
	Node* init;
	Node* cond;
	Node* incr;
	Node* body;
	StringID label;
}
