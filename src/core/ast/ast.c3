module analyzer::core::ast;

import analyzer::core::plog;
import analyzer::core::string_pool;

import std::collections::list;
import std::collections::nullable;

const sz ARENA_PAGE_SIZE = 4096;

alias NodeArray = Node*[];
alias NullableNode = Nullable{Node};

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
	ByteOffset offset;

	union
	{
		ErrorNode error;

		// DECL
		StructDecl struct_decl;
		EnumDecl enum_decl;
		VarDecl var_decl;
		AttrdefDecl attrdef_decl;
		AttributeDecl attribute_decl;
		ContractDecl contract_decl;
		ModuleDecl module_decl;
		ImportDecl import_decl;
		AliasDecl alias_decl;
		TypedefDecl typedef_decl;
		FnDecl fn_decl;
		MacroDecl macro_decl;
		FaultdefDecl faultdef_decl;
		FaultDecl fault_decl;
		GenericDecl generic_decl;
		InterfaceDecl interface_decl;
		CtExpandDecl ct_expand_decl;
		CtAssertDecl ct_assert_decl;

		// STMT
		IfStmt if_stmt;
		CtIfStmt ct_if_stmt;
		SwitchStmt switch_stmt;
		CtSwitchStmt ct_switch_stmt;
		CaseStmt case_stmt;
		DefaultStmt default_stmt;
		ContinueBreakStmt continue_break_stmt;
		NextcaseStmt nextcase_stmt;
		CompoundStmt compound_stmt;
		ReturnStmt return_stmt;
		ForStmt for_stmt;
		CtForStmt ct_for_stmt;
		WhileStmt while_stmt;
		DoWhileStmt do_while_stmt;
		ForeachStmt foreach_stmt;
		CtForeachStmt ct_foreach_stmt;
		ExprStmt expr_stmt;
		CtAssertStmt ct_assert_stmt;
		CtErrorStmt ct_error_stmt;
		CtEchoStmt ct_echo_stmt;
		DeferStmt defer_stmt;
		AssertStmt assert_stmt;

		// EXPR
		LiteralExpr literal_expr;
		BinaryExpr binary_expr;
		UnaryExpr unary_expr;
		PostUnaryExpr post_unary_expr;
		CallExpr call_expr;
		IdentExpr ident_expr;
		PathExpr path_expr;
		TypeExpr type_expr;
		ExprList expr_list;
		ContractExpr contract_expr;
		CondExpr cond_expr;
		TryExpr try_expr;
		CatchExpr catch_expr;
		TernaryExpr ternary_expr;
		MacroBodyExpr macro_body_expr;
		BuiltinExpr builtin_expr;
		CompilerConstExpr compiler_const_expr;
		SplatExpr splat_expr;
		VasplatExpr vasplat_expr;
		NamedArgExpr named_arg_expr;
		EvalNamedArgExpr eval_named_arg_expr;
		CtEvalExpr ct_eval_expr;
		LambdaExpr lambda_expr;
		GenericIdentExpr generic_ident_expr;
		GroupExpr group_expr;
		CastExpr cast_expr;
		DesignatorExpr designator_expr;
		DesignatedInitializerExpr designated_initializer_expr;
		InitializerListExpr initializer_list_expr;
		CompoundLiteralExpr compound_literal_expr;
		MaybeDeferExpr maybe_deref_expr;
		AccessExpr access_expr;
		RangeExpr range_expr;
		OptionalExpr optional_expr;
		CtDefinedExpr ct_defined_expr;
		CtFeatureExpr ct_feature_expr;
		BodyParamDecl body_param_decl;
		LengthofExpr lengthof_expr;
		CtExpandStmt ct_expand_stmt;

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
	self.error_nodes.init(&self.arena);
}

macro Node* Ast.error(&self, int start, int end = -1)
{
	Node* node = self.alloc_node(ERROR, start, end);
	self.error_nodes.push(node);

	$if !$feature(ANALYZER_LIB):
		plog::error("Error happened here");
	$endif

	return node;
}

macro Node* Ast.missing(&self, int start, int end = -1)
{
	Node* node = self.alloc_node(MISSING, start, end);
	self.error_nodes.push(node);

	$if !$feature(ANALYZER_LIB):
		plog::error("Error happened here");
	$endif

	return node;
}

fn sz Ast.next_node_idx(&self) => self.top_level_nodes.len();

fn void Ast.clear(&self)
{
	self.arena.reset();
	self.string_pool = { };
	self.top_level_nodes = { };
	self.error_nodes = { };

	self.string_pool.init(&self.arena, 128);
	self.top_level_nodes.init(&self.arena, 32);
	self.error_nodes.init(&self.arena);
}

fn void Ast.free(&self)
{
	self.top_level_nodes.clear();
	self.string_pool.clear();
	self.error_nodes.clear();
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
	node.offset.start = start;
	node.offset.end = end == -1 ? node.offset.start : end;

	return node;
}
