module parser::ast;
import lexer;

import std::collections::list;

struct ModuleDecl 
{
	String path;
	AttributeList attributes;
}

<* @require self.kind == MODULE_DECL *>
fn ModuleDecl* Node.as_module(&self) @inline 
{ 
	return &self.module_decl; 
}

struct ImportDecl
{
	String path;
	AttributeList attributes;
}

<* @require self.kind == IMPORT_DECL *>
fn ImportDecl* Node.as_import(&self) @inline 
{ 
	return &self.import_decl; 
}

struct FnDecl 
{
	String name;
	Node* type;
	Node* body;
	NodeArray params;
	AttributeList attributes;
}

<* @require self.kind == FN_DECL *>
fn FnDecl* Node.as_fn(&self) @inline 
{ 
	return &self.fn_decl; 
}