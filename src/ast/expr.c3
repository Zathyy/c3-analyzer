module c3_parser::ast;

import std::io;
import std::collections::list;

import c3_parser::common;

fn bool expr_ok(Expr* expr)
{
	return expr != null && expr.kind != ExprKind.INVALID;
}

enum ExprKind
{
	INVALID,
	BINARY,
	BUILTIN,
	CALL,
	CAST,
	CATCH,
	UNARY,
	SWIZZLE,
}

struct Expr
{
	ExprKind kind;
	SourceSpan span;
	
	union
	{
		TryExpr try_expr;
		CatchExpr catch_expr;
		CallExpr call_expr;
		SwizzleExpr swizzle_expr;
		CastExpr cast_expr;
		BuiltinExpr builtin_expr;
		List{ Expr* } initializer_list;
	}
}

struct TryExpr
{
	Expr* optional;
	union 
	{
		Decl* decl;
		Expr* lhs;
	}

	bool assign_existing;
}

struct CatchExpr
{
	Decl* decl;
	List{ Expr* } exprs;
}

struct BuiltinExpr
{
	String ident;
	BuiltinFunction builtin;
}

struct SwizzleExpr
{
	Expr* parent;
	String swizzle;
	bool is_overlapping;
}

struct CallExpr
{
	List{ Expr* } args;

	union 
	{
		Expr* function;
		Decl* func_ref;
	}
}

struct CastExpr
{
	Expr* expr;
	TypeInfo* type_info;
}