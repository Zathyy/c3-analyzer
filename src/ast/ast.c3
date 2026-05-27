module parser::ast;
import lexer;

import std::collections::list;

const sz ARENA_PAGE_SIZE = 4096;

alias NodeArray = Node*[];

bitstruct NodeFlags : ushort
{
	bool is_const;
	bool is_inline;
	bool is_static;
	bool is_extern;
	bool has_attributes;
}

struct Node 
{
	NodeKind kind;
	Visibility visibility;
	NodeFlags flags;
	int start_token;
	int end_token;

	union
	{
		// DECL
		ModuleDecl module_decl;
		ImportDecl import_decl;
		FnDecl fn_decl;

		// STMT
		IfStmt if_stmt;
		
		// EXPR
		BinaryExpr binary_expr;
		IdentExpr ident_expr;
		PathExpr path_expr;
		// UNIT
		IntLiteral int_lit;
	}
}

<* @require self.kind == INT_LITERAL *>
fn IntLiteral* Node.as_int(&self) @inline 
{ 
	return &self.int_lit; 
}

<* @require self.kind == IF_STMT *>
fn IfStmt* Node.as_if(&self) @inline 
{ 
	return &self.if_stmt; 
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