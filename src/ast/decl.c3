module c3_parser::ast;

import std::io;
import std::collections::list;

import c3_parser::common;

fn bool decl_ok(Decl* decl)
{
	return decl != null && decl.kind != DeclKind.INVALID;
}

enum DeclKind
{
	INVALID,
	MODULE,
	IMPORT,
	FUNC,
	ALIAS,
	TYPEDEF,
	VAR,
}

struct Decl (Printable)
{
	SourceSpan[] attributes;
	String name;
	String extname;
	String comment;
	SourceSpan span;
	DeclKind kind;

	union
	{
		FuncDecl func;
		ModuleDecl mod;
		ImportDecl imp;
		VarDecl var_decl;
		// more types go here later
	}
}

struct FuncDecl
{
	//TODO: string for now
	String ret_type;
	// range of whole args definition of function (includes parentheses)
	// TODO: turn this into a slice of AST node variables
	String args;
	Stmt* compound;
}

<*
	all kind of variables
	see 'VarDeclKind'
*>
struct VarDecl
{
	VarDeclKind kind;
	bool no_init;
	bool is_threadlocal;

	union 
	{
		Expr* init_expr;
		Decl* alis;
	}
}

struct EnumDecl
{
	List{ Decl* } values;
	List{ Decl* } parameters;
}

struct ModuleDecl 
{
	CPath* path;
}

struct ImportDecl 
{
	CPath* path;
}

struct AliasDecl 
{
	Decl* decl;
	bool is_func;
	bool is_redef;
}

struct TypedefDecl
{
	Decl* decl;
}

struct ContractDecl
{
	List{ Expr* } requires;
	List{ Expr* } ensures;
	bool pure;
}