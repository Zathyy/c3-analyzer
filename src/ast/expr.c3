module parser::ast;
import lexer;

import std::collections::list;

struct BinaryExpr
{
	Node* left;
	Node* right;
	OperatorKind op;
}

struct IdentExpr 
{
	StringID ident;
}

struct PathExpr
{
    StringID[] segments;
}

fn String? PathExpr.full_path(&self, StringPool* pool, Allocator allocator) => @pool()
{
	sz len = self.segments.len;
	String result;
	for (sz i = 0; i < len; i++)
	{
		String part = pool.get(self.segments[i])!;
		result = result.tconcat(part);
		if (i < len - 1)
		{
			result = result.concat(tmem, "::");
		}
	}

	return result.copy(allocator);
}	

struct TypeExpr
{
    TypeKind type_kind;
    Node* base_type; // Points to the child Node type being wrapped/modified
    Node* size_expr; // Only used for TYPE_AARRAY (e.g., the "4" in "int[4]")
}

