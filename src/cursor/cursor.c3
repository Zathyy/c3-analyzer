<*
 Cursor is basically a pointer to a specific node
    with the ability to walk and get out data from it.

    represents some Node in the abstract syntax tree for a module
*>
module parser::cursor;

import parser::workspace;
import parser::ast;
import parser::common;

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
		case PARAM_DECL:
			ParamDecl* param = self.node.as(PARAM_DECL);
			return pool.get(param.name)!;
		case FN_DECL:
			FnDecl* func = self.node.as(FN_DECL);
			return pool.get(func.name)!;
		case TYPE_EXPR:
			TypeExpr* type_data = self.node.as(TYPE_EXPR);
			if (type_data.kind == TYPE_IDENTIFIER)
			{
				String type_name = pool.get(type_data.unresolved.name)!;
				if (type_data.unresolved.path != null)
				{
					PathExpr* prefix_path = type_data.unresolved.path.as(PATH_EXPR);
					String prefix_str = prefix_path.full_path(pool, tmem)!;
					return prefix_str.tconcat(type_name).copy(allocator);
				}
				return type_name;
			}
			return "";
		default:
			return "";
	}
}