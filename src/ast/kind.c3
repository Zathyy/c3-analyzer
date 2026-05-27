module parser::ast;
import lexer;

import std::collections::list;

enum NodeKind : char
{
	INVALID,
    BINARY_EXPR,
    IF_STMT,
    INT_LITERAL,
    VAR_DECL,
    COMPOUND_STMT
}