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
	StringPool string_pool;
	List{Node*} top_level_nodes;
	List{Node*} error_nodes;
}

fn Ast new(Allocator backing_allocator = mem)
{
	Ast ast;
	ast.init(backing_allocator);
	return ast;
}

fn void Ast.init(&self, Allocator backing_allocator = mem)
{
	self.arena.init(backing_allocator, ARENA_PAGE_SIZE);
	self.string_pool.init(&self.arena, 128);
	self.top_level_nodes.init(&self.arena, 32);
}

fn sz Ast.next_node_idx(&self) => self.top_level_nodes.len();

fn void Ast.clear(&self)
{
	self.arena.reset();
	self.string_pool.clear();
	self.top_level_nodes.clear();
}

fn void Ast.free(&self)
{
	self.top_level_nodes.free();
	self.string_pool.free();
	self.arena.free();
}

fn StringID Ast.internalize(&self, String s)
{
	if (try idx = self.string_pool.index_of(s))
	{
		return idx;
	}
	String copy_s = s.copy(&self.arena);
	self.string_pool.push(copy_s);
	return self.string_pool.len() - 1;
}

fn String? Ast.get_string(&self, StringID id) => self.string_pool.get(id);

<*
  Allocates and initializes a strongly typed AST node inside the AST arena.
  @param kind  : "The NodeKind enum tag (e.g., IMPORT_DECL, VAR_DECL)"
  @param start : "The starting token index/position"
*>
fn Node* Ast.alloc_node(&self, NodeKind kind, int start, int end)
{
	Node* node = alloc::new(&self.arena, Node);

	node.kind = kind;
	node.start_token = start;
	node.end_token = end;

	return node;
}
