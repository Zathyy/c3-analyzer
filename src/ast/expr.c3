module c3_parser::ast;

import std::io;

import c3_parser::common;

enum ExprType
{
	BAD,
	TYPE_IDENT,
}

struct Expr
{
	ExprType type;
	union
	{
		ExprTypeIdent type_ident;
	}
}

struct ExprTypeIdent
{
	SourceSpan type;
}
