module c3_parser::ast;

import std::io;
import std::collections::list;
import std::collections::maybe;

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
	STRUCT,
	BITSTRUCT,
	UNION,
	ALIAS,
	TYPEDEF,
	VAR,
	LABEL,
	CONTRACT,
}

enum AliasKind
{
	DEFINE,
	MODULE,
	TYPE,
	FUNC,
}

struct Decl (Printable)
{
	List{ Attribute } attributes;
	String name;
	String extname;
	String comment; // comment && docs
	SourceSpan span;
	DeclKind kind;

	union
	{
		FuncDecl func;
		ModuleDecl mod;
		ImportDecl imp;
		VarDecl var_decl;
		AliasDecl alias_decl;
		TypedefDecl typedef_decl;
		ContractDecl contract;
		StructDecl struct_decl;
		// more types go here later
	}
}

struct FuncDecl
{
	TypeInfo* ret_type;
	List{ Decl* } params;
	Maybe{ Stmt* } compound;
}

struct StructDecl 
{
	List{ Decl* } members;
	Decl* parent; // optional
}

<*
	all kind of variables
	see 'VarDeclKind'
*>
struct VarDecl
{
	union
	{
		Expr* init_expr;
		Decl* alias_decl;
	}

	TypeInfo* type_info;
	VarDeclKind kind;

	bool no_init;
	bool is_threadlocal;
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
	union 
	{
		// AliasKind.TYPE -> type alias
		// AliasKind.FUNC -> fn pointer
		struct type
		{
			Decl* decl;
			TypeInfo* type_info;
		}

		// AliasKind.DEFINE
		struct def
		{
			Decl* decl;
			Expr* expr;
		}

		// AliasKind.MODULE
		struct mod
		{
			CPath* path;
			Module* mod;
		}
	}

	AliasKind kind;
}

struct TypedefDecl
{
	TypeInfo* type;
}

struct ContractDecl
{
	List{ Expr* } requires;
	List{ Expr* } ensures;
	List{ ContractParam } params;

	union returns
	{
		List{ Expr* } unresolved;
		List{ Expr* } resolved;
	}

	bool pure;
}