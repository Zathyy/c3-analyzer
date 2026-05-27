module parser::ast;
import lexer;

import std::collections::list;

struct BinaryExpr
{
    Node* left;
    Node* right;
    OperatorKind op;
}