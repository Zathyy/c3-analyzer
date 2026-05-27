module parser::ast;
import lexer;

import std::collections::list;

struct ImportDecl
{
	String path;
	Node* attributes;
}