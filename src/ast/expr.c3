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
	bool is_prefix;
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
			result = result.tconcat("::");
		}
	}

	if (self.is_prefix)
	{
		result = result.tconcat("::");
	}

	return result.copy(allocator);
}	

struct TypeExpr
{
	TypeKind kind;
    union
    {
        struct unresolved
		{
			StringID name;
            Node* path;
        }

        struct modify
		{
            Node* base;
        }

        struct array
		{
            Node* base;
            Node* len_expr;
        }

        struct generic
		{
            Node* base;
            Node*[] params;
        }
    }
}

struct ContractExpr 
{
	Node* exprs;
	StringID comment;
	StringID expr_string;
}