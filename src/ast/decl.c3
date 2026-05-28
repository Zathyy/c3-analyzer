module parser::ast;
import lexer;

import std::collections::list;

struct ModuleDecl 
{
	Node* path;
	AttributeList attributes;
}

<* @require self.kind == MODULE_DECL *>
fn ModuleDecl* Node.as_module(&self) @inline 
{ 
	return &self.module_decl; 
}

struct ImportDecl
{
	NodeArray paths;
	AttributeList attributes;
}

<* @require self.kind == IMPORT_DECL *>
fn ImportDecl* Node.as_import(&self) @inline 
{ 
	return &self.import_decl; 
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

<* @require self.kind == FN_DECL *>
fn FnDecl* Node.as_fn(&self) @inline 
{ 
	return &self.fn_decl; 
}

struct ParamDecl 
{
	StringID name;
	Node* type;
	Node* default_value;
	bool is_variadic;
	TokenKind ident_kind;
}

<* @require self.kind == PARAM_DECL *>
fn ParamDecl* Node.as_param(&self) @inline 
{ 
	return &self.param_decl; 
}