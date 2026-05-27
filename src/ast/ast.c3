module parser::ast;
import lexer;

import std::collections::list;

const sz ARENA_PAGE_SIZE = 4096;

struct Node 
{
    NodeKind kind;
    Visibility visibility;
    int start_token;
    int end_token;
    
    union
    {
        ImportDecl import_decl;
        IntLiteral int_lit;
        BinaryExpr binary;
        IfStmt if_stmt;
    }
}

<* @require self.kind == INT_LITERAL *>
fn IntLiteral* Node.as_int(&self) @inline 
{ 
    return &self.int_lit; 
}

<* @require self.kind == BINARY_EXPR *>
fn BinaryExpr* Node.as_binary(&self) @inline 
{ 
    return &self.binary; 
}

<* @require self.kind == IF_STMT *>
fn IfStmt* Node.as_if(&self) @inline 
{ 
    return &self.if_stmt; 
}

<* @require self.kind == IMPORT_DECL *>
fn ImportDecl* Node.as_import(&self) @inline 
{ 
    return &self.import_decl; 
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