module c3_parser::ast::views;

import string_pool;
import c3_parser::common;
import lexer;

faultdef
    ATTRIBUTE_NOT_PRESENT,
    ATTRIBUTE_ARG_NOT_PRESENT;

struct NodeView
{
	NodeKind kind;
	uint start_token_idx;
	uint end_token_idx;
	uint extra_idx;
}

struct View
{
	Ast* ast;
	Node handle;
}

fn bool View.is_valid(self) @inline
{
	return self.ast != null && self.handle.is_valid();
}

<*
	Creates a safe data array based on a view field const def
	@require $vaarg.len % 2 == 0
	@require ViewType::kind == CONSTDEF
	@require $vaarg.len == ViewType::len * 2 : "all fields must have a value"
*>
macro @data(...) <ViewType>
{
	uint[ViewType::len] data;
	$for var $i = 0; $i < $vaarg.len; $i += 2:
		var $name = $stringify($vaarg[$i]);
		data[ViewType.$name] = (uint) $vaarg[$i + 1];
	$endfor

	return data;
}

fn Node View.get_extra_index(self) => (Node)self.ast.extra_indices[(Size)self.handle];

macro View.get(self, $offset)
{
	return (Node)self.ast.extra_data[(Size)self.ast.extra_indices[(Size)self.handle] + $offset];
}

fn uint View.get_uint(self, uint offset)
{
	return (uint)self.ast.extra_data[(Size)self.ast.extra_indices[(Size)self.handle] + offset];
}

macro View.get_at(self, $base_offset, index)
{
	Size pos = (Size)self.ast.extra_indices[(Size)self.handle] + $base_offset + index;
	return (Node)self.ast.extra_data[pos];
}

fn uint View.get_list_count(self, uint offset) 
{
    uint list_ptr = self.get_uint(offset);
    return self.ast.extra_data[(Size)list_ptr];
}

fn Node View.get_list_item(self, uint offset, uint index)
{
    uint list_ptr = self.get_uint(offset);
    return (Node)self.ast.extra_data[(Size)list_ptr + 1 + index];
}
