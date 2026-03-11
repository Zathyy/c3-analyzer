module c3_parser::ast;

import std::io;
import c3_parser::common;

enum StmtType
{
	BAD,
	COMPOUND, // the body of a function
	RETURN,
	DECL,
	VAR,
	DEFER,
}

struct Stmt
{
	StmtType type;

	union
	{
		CompoundStmt compound;
		ReturnStmt return_stmt;
		DeclStmt decl_stmt;
		DeferStmt defer_stmt;
	}
}

struct CompoundStmt
{
	SourceSpan body;
	Stmt*[] stmts;
}

<*
	// a Decleration which is inside a Block
		BlockStmt
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
	SourceSpan ret;
}

struct DeferStmt 
{
	SourceSpan def;
	Stmt* compound;
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
