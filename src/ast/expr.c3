module parser::ast;
import lexer;

import std::collections::list;

struct BinaryExpr
{
	Node* left;
	Node* right;
	OperatorKind op;
}

struct IdentExpr 
{
	StringID ident;
}

struct PathExpr
{
    StringID[] segments; // e.g., ["std", "io", "printf"]
}

struct TypeExpr
{
    TypeKind type_kind;
    Node* base_type; // Points to the child Node type being wrapped/modified
    Node* size_expr; // Only used for TYPE_AARRAY (e.g., the "4" in "int[4]")
}

