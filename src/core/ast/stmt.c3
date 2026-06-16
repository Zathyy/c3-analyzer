module analyzer::core::ast;

import std::collections::list;
import analyzer::core::string_pool;

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
	NullableNode init;
	NullableNode cond;
	NullableNode incr;
	Node* body;
	StringID label;
}

struct WhileStmt
{
	Node* cond;
	Node* body;
	StringID label;
}

struct DoWhileStmt
{
	StringID label;
	Node* body;
	NullableNode cond;
}

struct ForeachStmt
{
	bool is_reverse;
	StringID label;
	bool index_by_ref;
	bool value_by_ref;
	Node* index;
	Node* variable;
	Node* enumeration;
	Node* body;
}

struct CtAssertStmt
{
	Node* expr;
	NullableNode msg_expr;
}

struct CtErrorStmt
{
	Node* expr;
}

struct CtEchoStmt
{
	Node* expr;
}

struct DeferStmt
{
	DeferKind kind;
	Node* ident;
	Node* body;
}

struct AssertStmt
{
	Node* expr;
	Node* message;
	NodeArray args;
}

struct CtExpandStmt
{
	Node* expr;
}
