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
	INVALID, // represents an invalid node
	EMPTY, // represents a valid, but empty node
	PATH,
	ATTRIBUTE,
	ATTRIBUTE_LIST,
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
	CONTRACT_ENTRY,
	CONTRACT_PARAM,
	MACRO_PARAMS,
	PARAM_LIST,
	BITSTRUCT_FIELD,
	BITSTRUCT_FIELD_LIST,

	TYPE,
	TYPE_DECL,
	TYPE_FUNCTION,

	CHAR_LITERAL,
	INT_LITERAL,
	FLOAT_LITERAL,
	STRING_LITERAL,
	BOOL_LITERAL,
	NULL_LITERAL,
	BYTES_LITERAL,

	FN_DECL, 
	ENUM_DECL,
	PARAM_DECL,
	VAR_DECL,
	VAR_DECL_LIST,
	STRUCT_DECL,
	UNION_DECL,
	BITSTRUCT_DECL, 
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
	BODY_PARAM_DECL,
	GENERIC_DECL,
	FAULT_DECL,
	FAULTDEF_DECL,
	DECL_STMT_LIST,
	CT_ASSERT_DECL,

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
	CT_DEFINED_EXPR,
	CT_FEATURE_EXPR,
	LENGTHOF_EXPR,
	SPLAT_EXPR,
	NONE_EXPR,
	COND_EXPR,
	TRY_UNWRAP_CHAIN_EXPR,
	TRY_UNWRAP_EXPR,
	CATCH_UNWRAP_EXPR,
	LAMBDA_EXPR,
	ATTR_CALL_EXPR,
	COMPOUND_LITERAL_EXPR,
	DESIGNATOR_PERIOD_EXPR,
	DESIGNATOR_RANGE_EXPR,
	DESIGNATOR_INDEX_EXPR,
	GENERIC_IDENT_EXPR,

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
	CT_ECHO_STMT,
	NOP_STMT,
	ASM_STMT,
	ASM_STMT_LIST,
	ASM_BLOCK_STMT,

	CT_IF_STMT,
	CT_SWITCH_STMT,
	CT_CASE_STMT,
	CT_VAR_DECL,
	CT_FOR_STMT,
	CT_FOREACH_STMT,
	CT_ASSERT_STMT,

	// asm
	ASM_ARG_REG,
	ASM_ARG_REGVAR,
	ASM_ARG_MEMVAR,
	ASM_ARG_ADDR,
	ASM_ARG_IMM,
	ASM_ARG_ADDROF,
	ASM_ARG_EXPR,
	ASM_LABEL,
	ASM_INST,
	ASM_OFFSET,

	DEFAULT_ELLIPSIS,
	DESIGNATED_INITIALIZER,
}

struct Ast
{
	List{NodeKind} kinds;
	List{uint} start_tokens;
	List{uint} end_tokens;
	List{uint} extra_indices;
	List{uint} extra_data;
	List{uint} top_level_nodes; // to track what nodes are "top-level" its really hard without it
	Allocator allocator;
}

fn void Ast.init(&ast, Allocator allocator, Size estimated_size)
{
	ast.allocator = allocator;
	ast.kinds.init(ast.allocator, estimated_size);
	ast.start_tokens.init(ast.allocator, estimated_size);
	ast.end_tokens.init(ast.allocator, estimated_size);
	ast.extra_indices.init(ast.allocator, estimated_size);
	ast.extra_data.init(ast.allocator, estimated_size * 2); // Usually more extra data than nodes
	ast.top_level_nodes.init(ast.allocator, estimated_size / 4);

	// push null state at index 0
	ast.kinds.push(INVALID);
	ast.start_tokens.push(0);
	ast.end_tokens.push(0);
	ast.extra_indices.push(0);
}
fn void Ast.free(&ast)
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
	@require start_tok <= end_tok  : "start needs to be less than end"
*>
fn Node Ast.add_node(&self, NodeKind kind, uint start_tok, uint end_tok, uint extra_idx)
{
	Node handle = (Node)self.kinds.len();
	self.kinds.push(kind);
	self.start_tokens.push(start_tok);
	self.end_tokens.push(end_tok);
	self.extra_indices.push(extra_idx);
	return handle;
}

fn Node Ast.add_empty(&self, uint start_tok, uint end_tok = 0, uint extra_idx = 0)
{
	Node handle = (Node)self.kinds.len();
	self.kinds.push(EMPTY);
	self.start_tokens.push(start_tok);
	self.end_tokens.push(end_tok ?: start_tok);
	self.extra_indices.push(extra_idx);
	return handle;
}

fn void Ast.update_node(&self, Node handle, uint start_tok, uint end_tok, uint new_extra_idx)
{
	assert ((Size)handle < self.kinds.len());

	self.start_tokens[(Size)handle] = start_tok;
	self.end_tokens[(Size)handle] = end_tok;
	self.extra_indices[(Size)handle] = new_extra_idx;
}

fn NodeView Ast.get_node(&self, Node handle)
{
	assert ((Size)handle < self.kinds.len());

	return (NodeView) {
		.kind = self.get_kind(handle),
		.start_token_idx = self.get_start_token(handle),
		.end_token_idx = self.get_end_token(handle),
		.extra_idx = self.extra_indices[(Size)handle]
	};
}

fn void Ast.free_node(&self, Node handle)
{
	self.kinds[(Size)handle] = INVALID;
}

fn uint Ast.get_extra(&self, uint index) @inline
{
	return self.extra_data[(Size)index];
}

fn NodeKind Ast.get_kind(&self, Node handle) @inline
{
	return self.kinds[(Size)handle];
}
// fn NodeKind get_kind(Ast* ast, Node handle) @inline
// {
// 	return ast.kinds[(Size)handle];
// }

fn uint Ast.get_start_token(&self, Node handle) @inline
{
	return self.start_tokens[(Size)handle];
}

fn uint Ast.get_end_token(&self, Node handle) @inline
{
	return self.end_tokens[(Size)handle];
}

/* * Reserves a contiguous block in the extra_data pool.
 * Returns the starting index. */
fn uint Ast.reserve_extra(&self, uint size)
{
	uint start = (uint)self.extra_data.len();
	for (uint i = 0; i < size; i++)
	{
		self.extra_data.push(0);
	}
	return start;
}

<*
	Pushes a list of nodes to extra_data, prepending the count.
	Memory layout: [Count, Node1, Node2, ...]
*>
fn uint Ast.push_extra_list(&self, uint[] data)
{
	uint start = (uint)self.extra_data.len();
	self.extra_data.push((uint)data.len);
	self.extra_data.push_all(data);
	return start;
}

<*
	For fixed-size metadata (Structs/Headers).
	Layout: [Field0, Field1, Field2...]
*>
fn uint Ast.push_extra_block(&self, uint[] data)
{
    uint start = (uint)self.extra_data.len();
    self.extra_data.push_all(data);
    return start;
}
