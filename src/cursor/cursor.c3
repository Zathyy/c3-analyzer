<*
 Cursor is basically a pointer to a specific node
    with the ability to walk and get out data from it.

    represents some Node in the abstract syntax tree for a module
*>
module parser::cursor;

import parser::workspace;
import parser::ast;

import std::io;

faultdef
	INVALID_NODE
;

<*
 Get the spelling/text for the current node
 @require self.node != null
 @require self.section != null
 @require self.section.source_file != null
 @require self.section.source_file.ast != null
*>
fn String? Cursor.spelling(&self, Allocator allocator) => @pool()
{
	StringPool* pool = &self.section.source_file.ast.string_pool;

	switch (self.node.kind)
	{
		case STRUCT_DECL:
			StructDecl* s = self.node.as(STRUCT_DECL);
			return pool.get(s.name)!;
		case VAR_DECL:
			VarDecl* v = self.node.as(VAR_DECL);
			return pool.get(v.name)!;
		case FN_DECL:
			FnDecl* func = self.node.as(FN_DECL);
			return pool.get(func.name)!;
		case MACRO_DECL:
			MacroDecl* mac = self.node.as(MACRO_DECL);
			return pool.get(mac.name)!;
		case TYPE_EXPR:
			TypeExpr* type_data = self.node.as(TYPE_EXPR);
			if (type_data.kind == TYPE_IDENTIFIER)
			{
				String type_name = pool.get(type_data.unresolved.name)!;
				if (type_data.unresolved.path != null)
				{
					PathExpr* prefix_path = type_data.unresolved.path.as(PATH_EXPR);
					String prefix_str     = prefix_path.full_path(pool, tmem)!;
					return prefix_str.tconcat(type_name).copy(allocator);
				}
				return type_name;
			}
			return "";
		default:
			return "";
	}
}

<*
 Checks if cursor has a specific attribute
*>
fn bool Cursor.has_attribute(&self, AttributeKind kind)
{
	NodeArray temp;
	switch (self.node.kind)
	{
		case STRUCT_DECL:
			StructDecl* s = self.node.as(STRUCT_DECL);
			temp = s.attributes;
			break;
		case INTERFACE_DECL:
			InterfaceDecl* inter = self.node.as(INTERFACE_DECL);
			temp = inter.attributes;
			break;
		case FN_DECL:
			FnDecl* func = self.node.as(FN_DECL);
			temp = func.attributes;
			break;
		default:
			return false;
	}

	foreach (attr : temp)
	{
		AttributeDecl* attr_decl = attr.as(ATTRIBUTE_DECL);
		if (attr_decl.kind == kind)
		{
			return true;
		}
	}

	return false;
}

<*
 use a binary-search to find wether any error node has
 the byte offset / byte range of this cursor
 Note: has not yet been tested
*>
fn bool Cursor.has_error(&self)
{
	NodeArray errors = self.section.source_file.ast.error_nodes.array_view();
	sz len           = errors.len;
	if (len == 0) return false;

	sz node_start = self.node.start_token;
	sz node_end   = self.node.end_token;

	sz low  = 0;
	sz high = len - 1;

	while (low <= high)
	{
		sz mid    = low + (high - low) / 2;
		Node* err = errors[mid];

		if (node_start <= err.end_token && err.start_token <= node_end)
		{
			return true;
		}

		if (err.start_token > node_end)
		{
			high = mid - 1;
		}
		else
		{
			low = mid + 1;
		}
	}

	return false;
}
