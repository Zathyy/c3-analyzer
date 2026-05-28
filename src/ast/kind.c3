module parser::ast;
import lexer;

import std::collections::list;

enum NodeKind : char
{
	ERROR,
	MISSING,
	INT_LITERAL,
	
	VAR_DECL,
	MODULE_DECL,
	IMPORT_DECL,
	FN_DECL,
	PARAM_DECL,

	COMPOUND_STMT,
	IF_STMT,

	BINARY_EXPR,
	IDENT_EXPR,
	TYPE_EXPR,
	PATH_EXPR,
}