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

fn Node? View.get_attribute(self, uint attr_field_offset, AttributeKind kind)
{
    uint list_offset = self.get_uint(attr_field_offset);
    if (list_offset == 0) return ATTRIBUTE_NOT_PRESENT~;

    AttributeListView list = { self.ast, (Node)list_offset };
    for (uint i = 0; i < list.count(); i++)
    {
        Node attr_node = list.get_attr(i);
        AttributeView attr = { self.ast, attr_node };
        if (attr.kind() == kind) return attr_node;
    }
    
    return ATTRIBUTE_NOT_PRESENT~;
}

fn bool View.has_attribute(self, uint attr_field_offset, AttributeKind kind)
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

fn AttributeView? View.get_attribute_view(self, uint attr_field_offset, AttributeKind kind)
{
    Node attr_node = self.get_attribute(attr_field_offset, kind)!;
    if (!attr_node.is_valid()) return ATTRIBUTE_NOT_PRESENT~;
    return (AttributeView){ self.ast, attr_node };
}

fn Node? View.get_attr_arg(self, uint attr_field_offset, AttributeKind kind, uint arg_index)
{
    AttributeView attr = self.get_attribute_view(attr_field_offset, kind)!;
    if (arg_index >= attr.arg_count()) return ATTRIBUTE_ARG_NOT_PRESENT~;
    return attr.get_arg(arg_index);
}