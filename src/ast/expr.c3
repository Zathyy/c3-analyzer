module c3_parser::ast;

//temp!
import c3::lexer;

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
	IDENTIFIER,
	INTEGER,
	STRING,
	REAL,
	BOOL,
	BINARY,
	UNARY,
	TERNARY,
	BUILTIN,
	TYPE,
	CALL,
	CAST,
	CATCH,
	SWIZZLE,
}

struct Expr
{
	ExprKind kind;
	SourceSpan span;
	
	union
	{
		String value; // literal [String, Integer, Real, Bool]
		TypeExpr type_expr;
		BinaryExpr binary_expr;
		UnaryExpr unary_expr;
		TernaryExpr ternary_expr;
		TryExpr try_expr;
		CatchExpr catch_expr;
		CallExpr call_expr;
		SwizzleExpr swizzle_expr;
		CastExpr cast_expr;
		BuiltinExpr builtin_expr;
	}
}

struct TypeExpr 
{
	TypeInfo* type;
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

struct CastExpr
{
	Expr* expr;
	TypeInfo* type_info;
}

struct UnaryExpr 
{
    TokenType op;
    Expr* rhs;
}

struct BinaryExpr 
{
    Expr* left;
    TokenType op;
    Expr* right;
}

struct TernaryExpr
{
    Expr* cond;
    Expr* true_expr;
    Expr* false_expr;
}

struct CallExpr 
{
    Expr* callee;
    List{Expr*} args;
}