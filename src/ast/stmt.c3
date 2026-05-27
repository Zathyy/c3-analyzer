module parser::ast;
import lexer;

import std::collections::list;

struct IfStmt
{
    inline Node base;
    Node* condition;
    Node* then_block;
    Node* else_block;
}

struct CompoundStmt
{
    inline Node base;
    Node*[] statements;
}