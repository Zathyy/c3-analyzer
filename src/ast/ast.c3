module c3_parser::ast;
import lexer;

import c3_parser::common;
import std::collections::list;

typedef Node = uint;

fn bool Node.is_valid(self) @inline
{
	return (uint)self != 0;
}

enum NodeKind : char
{
	INVALID,
	PATH,
	ATTRIBUTE,
	ATTRIBUTED_EXPR,
	OP_OVERLOAD,
	BLOCK,
	// a collection of statements
	INITIALIZER_LIST,
	DESIGNATED_INITIALIZER_LIST,
	FOREACH_VAR,
	INTERFACE_IMPL,
	INTERFACE_METHOD,
	INTERFACE_PARENT,
	GENERIC_PARAM,
	ENUM_MEMBER,

	TYPE,
	TYPE_DECL,
	TYPE_FUNCTION,

	INT_LITERAL,
	FLOAT_LITERAL,
	STRING_LITERAL,
	BOOL_LITERAL,
	NULL_LITERAL,

	FN_DECL,
	ENUM_DECL,
	PARAM_DECL,
	VAR_DECL,
	// 
	STRUCT_DECL,
	// struct
	FIELD_DECL,
	ALIAS_DECL,
	TYPE_ALIAS_DECL,
	PATH_ALIAS_DECL,
	INTERFACE_DECL,
	MACRO_DECL,
	TYPEDEF_DECL,
	MODULE_DECL,
	IMPORT_DECL,
	LOCAL_DECL,
	CONTRACT_DECL,

	REQUIRE_EXPR,
	ENSURE_EXPR,
	TYPE_EXPR,
	IDENT_EXPR,
	UNARY_EXPR,
	BINARY_EXPR,
	TERNARY_EXPR,
	CALL_EXPR,
	CAST_EXPR,
	BUILTIN_EXPR,
	COMPILER_CONST_EXPR,
	DEREF_SUBSCRIPT_EXPR,
	ACCESS_EXPR,
	OPTIONAL_EXPR,
	OPERATOR_CHARS_EXPR,
	INDEX_EXPR,
	SLICE_EXPR,
	POST_UNARY_EXPR,
	PRE_UNARY_EXPR,
	PREFIX_EXPR,
	NAMED_ARG_EXPR,
	MAYBE_DEREF_EXPR,
	SUBSCRIPT_EXPR,
	EXPR_LIST,

	FOR_STMT,
	COMPOUND_STMT,
	RETURN_STMT,
	EXPR_STMT,
	IF_STMT,
	DEFER_STMT,
	DO_WHILE_STMT,
	SWITCH_STMT,
	CASE_STMT,
	BREAK_STMT,
	DEFAULT_STMT,
	CONTINUE_STMT,
	ASSERT_STMT,
	NEXTCASE_STMT,
	FOREACH_STMT,
	FOREACH_R_STMT,
	WHILE_STMT,

	CT_IF_STMT,
	CT_SWITCH_STMT,
	CT_CASE_STMT,
	CT_VAR_DECL,
	CT_FOR_STMT,
}

struct Ast
{
	List{NodeKind} kinds;
	List{uint} start_tokens;
	List{uint} end_tokens;
	List{uint} extra_indices;
	List{uint} extra_data;
	List{uint} top_level_nodes; // to track what nodes are "top-level" its really hard without it
}

fn void init(Ast* ast, Size estimated_size)
{
	ast.kinds.tinit(estimated_size);
	ast.start_tokens.tinit(estimated_size);
	ast.end_tokens.tinit(estimated_size);
	ast.extra_indices.tinit(estimated_size);
	ast.extra_data.tinit(estimated_size * 2); // Usually more extra data than nodes
	ast.top_level_nodes.tinit(estimated_size / 4);

	// push null state at index 0
	ast.kinds.push(INVALID);
	ast.start_tokens.push(0);
	ast.end_tokens.push(0);
	ast.extra_indices.push(0);
}


fn void free(Ast* ast)
{
	ast.kinds.free();
	ast.start_tokens.free();
	ast.end_tokens.free();
	ast.extra_indices.free();
	ast.extra_data.free();
	ast.top_level_nodes.free();
}

fn void Ast.clear(&self)
{
	self.kinds.clear();
	self.start_tokens.clear();
	self.end_tokens.clear();
	self.extra_indices.clear();
	self.extra_data.clear();
	self.top_level_nodes.clear();

	self.kinds.push(INVALID);
	self.start_tokens.push(0);
	self.end_tokens.push(0);
	self.extra_indices.push(0);
}

fn uint Ast.len(&self)
{
	return (uint)self.kinds.len();
}

fn uint Ast.push_extra(&self, uint value = 0) @inline
{
	uint idx = (uint)self.extra_data.len();
	self.extra_data.push(value);
	return idx;
}

fn void Ast.set_extra(&self, uint index, uint value) @inline
{
	self.extra_data[(Size)index] = value;
}

<*
	@require end_tok >= start_tok : "start needs to be less than end"
*>
fn Node add_node(Ast* ast, NodeKind kind, uint start_tok, uint end_tok, uint extra_idx)
{
	Node handle = (Node)ast.kinds.len();
	ast.kinds.push(kind);
	ast.start_tokens.push(start_tok);
	ast.end_tokens.push(end_tok);
	ast.extra_indices.push(extra_idx);
	return handle;
}

fn void Ast.update_node(&self, Node handle, uint start_tok, uint end_tok, uint new_extra_idx)
{
	assert ((Size)handle < self.kinds.len());

	self.start_tokens[(Size)handle] = start_tok;
	self.end_tokens[(Size)handle] = end_tok;
	self.extra_indices[(Size)handle] = new_extra_idx;
}

fn NodeView get_node(Ast* ast, Node handle)
{
	assert ((Size)handle < ast.kinds.len());

	return (NodeView) {
		.kind = get_kind(ast, handle),
		.start_token_idx = get_start_token(ast, handle),
		.end_token_idx = get_end_token(ast, handle),
		.extra_idx = ast.extra_indices[(Size)handle]
	};
}

fn void free_node(Ast* ast, Node handle)
{
	ast.kinds[(Size)handle] = INVALID;
}

fn uint get_extra(Ast* ast, uint index) @inline
{
	return ast.extra_data[(Size)index];
}

fn NodeKind get_kind(Ast* ast, Node handle) @inline
{
	return ast.kinds[(Size)handle];
}

fn uint get_start_token(Ast* ast, Node handle) @inline
{
	return ast.start_tokens[(Size)handle];
}

fn uint get_end_token(Ast* ast, Node handle) @inline
{
	return ast.end_tokens[(Size)handle];
}

/* * Reserves a contiguous block in the extra_data pool.
 * Returns the starting index. */
fn uint reserve_extra(Ast* ast, uint size)
{
	uint start = (uint)ast.extra_data.len();
	for (uint i = 0; i < size; i++)
	{
		ast.extra_data.push(0);
	}
	return start;
}

/* * Helper to write a slice of values directly into the extra pool. */
fn uint push_extra_list(Ast* ast, uint[] data)
{
	uint start = (uint)ast.extra_data.len();
	ast.extra_data.push_all(data);
	return start;
}
