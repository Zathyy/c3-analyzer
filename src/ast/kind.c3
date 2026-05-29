module parser::ast;
import lexer;

import std::collections::list;

enum NodeKind : char
{
	ERROR,
	MISSING,
	INT_LITERAL,
	
	CONTRACT_DECL,
	VAR_DECL,
	MODULE_DECL,
	IMPORT_DECL,
	FN_DECL,
	PARAM_DECL,

	COMPOUND_STMT,
	IF_STMT,
	CALL_EXPR,

	BINARY_EXPR,
	IDENT_EXPR,
	TYPE_EXPR,
	PATH_EXPR,
}