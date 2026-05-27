module parser::ast;
import lexer;

import std::collections::list;

const sz ARENA_PAGE_SIZE = 4096;

struct Node
{
    NodeKind kind;
    int start_token;
    int end_token;
}

struct IntLiteral
{
    inline Node base;
    long value;
}

struct BinaryExpr
{
    inline Node base;
    Node* left;
    Node* right;
    OperatorKind op;
}

struct Ast
{
    DynamicArenaAllocator arena;
    Allocator allocator;
    List{Node*} top_level_nodes; 
}

fn void Ast.init(&self, Allocator backing_allocator = mem)
{
    self.arena.init(backing_allocator, ARENA_PAGE_SIZE);
    self.allocator = &self.arena;
    self.top_level_nodes.init(self.allocator, 32);
}

fn void Ast.clear(&self)
{
    self.arena.reset();
    self.top_level_nodes.clear();
}

fn void Ast.free(&self)
{
    self.top_level_nodes.free();
    self.arena.free();
}