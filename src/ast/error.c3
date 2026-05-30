module parser::ast;
import lexer;

import std::collections::list;

struct ErrorNode
{
	NodeArray inner;
}