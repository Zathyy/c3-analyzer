module c3_parser::ast::views;

import string_pool;
import c3_parser::common;
import lexer;

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

fn Node View.get_extra_index(self) => (Node)self.ast.extra_indices[(Size)self.handle];

macro View.get(self, $offset)
{
	return (Node)self.ast.extra_data[(Size)self.ast.extra_indices[(Size)self.handle] + $offset];
}

macro View.get_uint(self, $offset)
{
	return (uint)self.ast.extra_data[(Size)self.ast.extra_indices[(Size)self.handle] + $offset];
}

macro View.get_at(self, $base_offset, index)
{
	Size pos = (Size)self.ast.extra_indices[(Size)self.handle] + $base_offset + index;
	return (Node)self.ast.extra_data[pos];
}

macro uint View.get_list_count(self, $offset) 
{
    uint list_ptr = self.get_uint($offset);
    return self.ast.extra_data[(Size)list_ptr];
}

macro Node View.get_list_item(self, $offset, uint index)
{
    uint list_ptr = self.get_uint($offset);
    return (Node)self.ast.extra_data[(Size)list_ptr + 1 + index];
}

macro Node? View.get_attribute(self, $attr_field_offset, AttributeKind kind)
{
    uint list_offset = self.get_uint($attr_field_offset);
    if (list_offset == 0) return (Node)0;

    AttributeListView list = { self.ast, (Node)list_offset };
    for (uint i = 0; i < list.count(); i++)
    {
        Node attr_node = list.get_attr(i);
        AttributeView attr = { self.ast, attr_node };
        if (attr.kind() == kind) return attr_node;
    }
    return (Node)0;
}

macro bool View.has_attribute(self, uint attr_field_offset, AttributeKind kind)
{
    uint list_offset = self.get_uint(attr_field_offset);
    if (list_offset == 0) return false;

    AttributeListView list = { self.ast, (Node)list_offset };
    for (uint i = 0; i < list.count(); i++)
    {
        AttributeView attr = { self.ast, list.get_attr(i) };
        if (attr.kind() == kind) return true;
    }
    return false;
}