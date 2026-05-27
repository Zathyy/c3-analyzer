module parser::ast;
import lexer;

import std::collections::list;

struct IntLiteral
{
    long value;
}

struct StringLiteral
{
    String value;
}

