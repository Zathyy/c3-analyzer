module parser::ast;
import lexer;

import std::collections::list;

struct BinaryExpr
{
	Node* left;
	Node* right;
	OperatorKind op;
}

<* @require self.kind == BINARY_EXPR *>
fn BinaryExpr* Node.as_binary(&self) @inline 
{ 
	return &self.binary_expr;
}

struct IdentExpr 
{
	String ident;
}

<* @require self.kind == IDENT_EXPR *>
fn IdentExpr* Node.as_ident(&self) @inline 
{ 
	return &self.ident_expr;
}

struct PathExpr
{
    StringID[] segments; // e.g., ["std", "io", "printf"]
}

<* @require self.kind == PATH_EXPR *>
fn PathExpr* Node.as_path(&self) @inline 
{ 
    return &self.path_expr; 
}

struct TypeExpr
{
    TypeKind type_kind;
    Node* base_type; // Points to the child Node type being wrapped/modified
    Node* size_expr; // Only used for TYPE_AARRAY (e.g., the "4" in "int[4]")
}

