module analyzer::sema::decl @if($feature(SEMA));

import analyzer::core;
import analyzer::cursor;

import std::collections::list;

<*
 @param [&in] ctx
 @param [&in] node : "the node to resolve for"
 @param [&out] out_expr : "The expr in '@if(expr)'"
*>
fn bool node_has_if_attribute(SemaContext* ctx, Node* node, Node** out_expr)
{
	Cursor cursor = { ctx.section, node };
	Node* attr_node = null;

	if (cursor.has_attribute(AttributeKind.IF, &attr_node))
	{
		AttributeDecl* attr_decl = attr_node.as(ATTRIBUTE_DECL);
		
		if (attr_decl.exprs.len > 0)
		{
			if (out_expr != null)
			{
				*out_expr = attr_decl.exprs[0];
			}
			return true;
		}
	}

	return false;
}