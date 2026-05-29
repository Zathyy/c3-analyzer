module parser::ast;
import lexer;

import std::collections::list;

struct ContractParam 
{
	StringID name;
	StringID description;
	int start_token;
	int end_token;
	InOutModifier modifier;
	bool by_ref;
}

struct ContractDecl 
{
	NodeArray requires;
	NodeArray ensures;
	NodeArray opt_returns;
	ContractParam[] params;
	StringID comment;
	StringID return_desc;
	bool is_pure;
}

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
	Node* type;
	Node* default_value;
	StringID name;
	TokenKind ident_kind;
	bool is_variadic;
}

struct VarDecl 
{
	VarDeclKind kind;
	VarDeclFlags flags;
	StringID name;
	Node* type;
	Node* init_expr;
	AttributeList attributes;
}
