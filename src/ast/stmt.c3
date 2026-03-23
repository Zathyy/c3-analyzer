module c3_parser::ast;

import std::io;
import std::collections::list;
import std::collections::maybe;

import c3_parser::common;

fn bool stmt_ok(Stmt* stmt)
{
	return stmt != null && stmt.kind != StmtKind.INVALID;
}

enum StmtKind
{
	INVALID,
	COMPOUND, // the body of a function
	RETURN,
	DECL,
	DEFER,
	EXPR,
	IF,
	TRY,
}

struct Stmt
{
	StmtKind kind;
	SourceSpan span;

	union
	{
		CompoundStmt compound;
		ReturnStmt return_stmt;
		DeclStmt decl_stmt;
		DeferStmt defer_stmt;
		ExprStmt expr_stmt;
		IfStmt if_stmt;
	}
}

struct CompoundStmt
{
	List{ Stmt* } stmts;
}

<*
	// a Decleration which is inside a Compound
	{ 
		int my_var = 1; <- DeclStmt
	}
*>
struct DeclStmt
{	
	// only going to be a VarDecl
	Decl* decl;
}

struct ExprStmt 
{
	Expr* expr;
}

struct ReturnStmt
{
	Expr* expr;
}

struct IfStmt
{
	List{ Expr* } conditions;
    Stmt* then_stmt;
    Stmt* else_stmt;
	Maybe{ Decl* } label;
}

struct DeferStmt 
{
	Stmt* stmt; //compound or normal stmt
	bool is_try;
	bool is_catch;
}

struct ForEachStmt 
{
	Stmt* block;
	bool iterator;
	bool is_reverse;
	bool index_by_ref;
	bool value_by_ref;
}
