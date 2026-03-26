module c3_parser::ast;
import lexer;

import c3_parser::common;
import std::collections::list;

typedef Node = uint;

enum NodeKind : char 
{
    INVALID,
	PATH,
    FUNC_DECL,
    VAR_DECL, // 
	FOR_STMT,
    STRUCT_DECL, // struct
    COMPOUND_STMT, // { ... }
    RETURN_STMT, // return
	IDENT_EXPR,
	MODULE_DECL,
    IMPORT_DECL,
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
}

fn void free(Ast* ast)
{
	ast.kinds.free();
	ast.tokens.free();
	ast.extra_indices.free();
	ast.extra_data.free();
    ast.top_level_nodes.free();
}

fn Node add_node(Ast* ast, NodeKind kind, uint tok, uint extra_idx)
{
	Node handle = (Node)ast.kinds.len();
	ast.kinds.push(kind);
    ast.tokens.push(tok);
    ast.extra_indices.push(extra_idx);
	return handle;
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

