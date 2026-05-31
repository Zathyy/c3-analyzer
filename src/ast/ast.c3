module parser::ast;
import lexer;

import parser::ast::utils;
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
		ErrorNode error;

		// DECL
		VarDecl var_decl;
		AttributeDecl attribute_decl;
		ContractDecl contract_decl;
		ModuleDecl module_decl;
		ImportDecl import_decl;
		AliasDecl alias_decl;
		TypedefDecl typedef_decl;
		FnDecl fn_decl;
		ParamDecl param_decl;
		CtExpandDecl ct_expand_decl;

		// STMT
		IfStmt if_stmt;
		SwitchStmt switch_stmt;
		CtSwitchStmt ct_switch_stmt;
		CaseStmt case_stmt;
		DefaultStmt default_stmt;
		ContinueBreakStmt continue_break_stmt;
		NextcaseStmt nextcase_stmt;
		CompoundStmt compound_stmt;
		ReturnStmt return_stmt;
		ExprStmt expr_stmt;

		// EXPR
		LiteralExpr literal_expr;
		BinaryExpr binary_expr;
		UnaryExpr unary_expr;
		CallExpr call_expr;
		IdentExpr ident_expr;
		PathExpr path_expr;
		TypeExpr type_expr;
		ExprList expr_list;
		ContractExpr contract_expr;
		CondExpr cond_expr;
		// UNIT
		ContractParam contract_param;
	}
}

macro Node.as(&self, NodeKind $kind)
{
	assert(self.kind == $kind, "Invalid kind current: \"%s\" expected: \"%s\"", self.kind, $kind);
	return &self.$eval(utils::@str_to_lower($kind.description));
}

struct Ast
{
	DynamicArenaAllocator arena;
	StringPool string_pool;
	List{Node*} top_level_nodes;
	List{Node*} error_nodes;
}

fn void Ast.init(&self, Allocator backing_allocator = mem)
{
	self.arena.init(backing_allocator, ARENA_PAGE_SIZE);
	self.string_pool.init(&self.arena, 128);
	self.top_level_nodes.init(&self.arena, 32);
}

macro Node* Ast.error(&self, int start, int end = -1)
{
	Node* node = self.alloc_node(ERROR, start, end);
	self.error_nodes.push(node);

	$if !$feature(PARSER_LIB):
		log::error("Error happened here");
	$endif

	return node;
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
	self.top_level_nodes.clear();
	self.string_pool.clear();
	self.arena.free();
}

<*
 Allocates and initializes a strongly typed AST node inside the AST arena.
 @param kind : "The NodeKind enum tag (e.g., IMPORT_DECL, VAR_DECL)"
 @param start : "The starting token index/position"
*>
fn Node* Ast.alloc_node(&self, NodeKind kind, int start, int end = -1)
{
	Node* node = alloc::new(&self.arena, Node);

	node.kind = kind;
	node.start_token = start;
	node.end_token = end == -1 ? node.start_token : end;

	return node;
}
