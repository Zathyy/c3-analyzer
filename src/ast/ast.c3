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

	TYPE,
	TYPE_DECL,

    INT_LITERAL,
    FLOAT_LITERAL,
    STRING_LITERAL,

    FN_DECL,
    PARAM_DECL,
    VAR_DECL, // 
    STRUCT_DECL, // struct
    ALIAS_DECL,
    GLOBAL_DECL,
    TYPEDEF_DECL,
	MODULE_DECL,
    IMPORT_DECL,

	TYPE_EXPR,
	IDENT_EXPR,
    UNARY_EXPR,
    BINARY_EXPR,
    TERNARY_EXPR,
    CALL_EXPR,

	FOR_STMT,
    COMPOUND_STMT, // { ... }
    RETURN_STMT, // return
    VAR_DECL_STMT,
    EXPR_STMT,
    IF_STMT,
    DEFER_STMT,
}

struct Ast 
{
    List{NodeKind} kinds;
    List{uint}     tokens;
    List{uint}     extra_indices;
    List{uint}     extra_data;
    List{uint}     top_level_nodes; // to track what nodes are "top-level" its really hard without it
}

fn void init(Ast* ast, usz estimated_size)
{
    ast.kinds.tinit(estimated_size);
    ast.tokens.tinit(estimated_size);
    ast.extra_indices.tinit(estimated_size);
    ast.extra_data.tinit(estimated_size * 2); // Usually more extra data than nodes
    ast.top_level_nodes.tinit(estimated_size / 4);

	// push null state at index 0
	ast.kinds.push(INVALID);
	ast.tokens.push(0);
	ast.extra_indices.push(0);
}

fn void free(Ast* ast)
{
	ast.kinds.free();
	ast.tokens.free();
	ast.extra_indices.free();
	ast.extra_data.free();
    ast.top_level_nodes.free();
}

fn uint Ast.push_extra(&self, uint value = 0) @inline
{
    uint idx = (uint)self.extra_data.len();
    self.extra_data.push(value);
    return idx;
}

fn void Ast.set_extra(&self, uint index, uint value) @inline 
{
    self.extra_data[(usz)index] = value;
}

fn Node add_node(Ast* ast, NodeKind kind, uint tok, uint extra_idx)
{
	Node handle = (Node)ast.kinds.len();
	ast.kinds.push(kind);
    ast.tokens.push(tok);
    ast.extra_indices.push(extra_idx);
	return handle;
}

fn NodeView get_node(Ast* ast, Node handle)
{
    assert((usz)handle < ast.kinds.len());

    return (NodeView){
        .kind = ast.kinds[(usz)handle],
        .token_idx = ast.tokens[(usz)handle],
        .extra_idx = ast.extra_indices[(usz)handle]
    };
}

fn void free_node(Ast* ast, Node handle)
{
    ast.kinds[(usz)handle] = NodeKind.INVALID;
}

fn uint get_extra(Ast* ast, uint index)
{
    return ast.extra_data[index];
}

fn NodeKind get_kind(Ast* ast, Node handle)
{
	return ast.kinds[(usz)handle];
}

fn uint get_token(Ast* ast, Node handle)
{
	return ast.tokens[(usz)handle];
}

/*
 * Reserves a contiguous block in the extra_data pool.
 * Returns the starting index.
 */
fn uint reserve_extra(Ast* ast, uint size)
{
    uint start = (uint)ast.extra_data.len();
	for (uint i = 0; i < size; i++)
	{
    	ast.extra_data.push(0);
	}
    return start;
}

/*
 * Helper to write a slice of values directly into the extra pool.
 */
fn uint push_extra_block(Ast* ast, uint[] data)
{
    uint start = (uint)ast.extra_data.len();
    ast.extra_data.push_all(data);
    return start;
}

