module parser::ast;
import lexer;

import std::collections::list;

struct ContractParam 
{
	Node* name;
	StringID description;
	InOutModifier modifier;
	bool by_ref;
}

struct ContractDecl 
{
	NodeArray requires;
	NodeArray ensures;
	NodeArray returns;
	NodeArray params; // ContractParam
	StringID comment;
	Node* return_desc; // ident_expr
	Node* deprecated;
	bool is_pure;
}

fn String? ContractDecl.get_comment(&self, StringPool* pool) => pool.get(self.comment);

struct ModuleDecl 
{
	Node* path;
	NodeArray attributes;
}

struct ImportDecl
{
	NodeArray paths;
	NodeArray attributes;
}

struct FnDecl 
{
	StringID name;
	Node* associated_type;
	Node* ret_type;
	Node* body;
	NodeArray params;
	NodeArray attributes;
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
	NodeArray attributes;
	Node* next; // next Var_decl if chained (e.g. int a, b, c; )
}

struct AttributeDecl
{
	Node* path;
	String name;
	NodeArray exprs;
	AttributeKind kind;
	bool is_custom;
}