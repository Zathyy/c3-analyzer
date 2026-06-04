module parser_tests;

import parser::workspace;
import parser::ast;

import std::io;
import std::collections::list;

macro AttributeDecl* @attr(self, int idx)
{
	return self.attributes[idx].as(ATTRIBUTE_DECL) @inline;
}

<*
 Count how many top-level nodes inside this specific ModuleSection match a given kind.
*>
fn int count_kind(ModuleSection* s, NodeKind kind)
{
	int n = 0;

	foreach (node_ptr : s.nodes)
	{
		if (node_ptr == null) continue;

		// Directly check the node's kind field
		if (node_ptr.kind == kind)
		{
			n++;
		}
	}
	return n;
}
