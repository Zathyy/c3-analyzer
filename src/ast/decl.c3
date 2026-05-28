module parser::ast;
import lexer;

import std::collections::list;

struct ModuleDecl 
{
	Node* path;
	AttributeList attributes;
}

struct ImportDecl
{
	NodeArray paths;
	AttributeList attributes;
}

struct FnDecl 
{
	StringID name;
	Node* associated_type;
	Node* ret_type;
	Node* body;
	NodeArray params;
	AttributeList attributes;
}

struct ParamDecl 
{
	StringID name;
	Node* type;
	Node* default_value;
	bool is_variadic;
	TokenKind ident_kind;
}
