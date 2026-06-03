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

fn String? IdentExpr.get_ident(&self, StringPool* pool) => pool.get(self.ident);

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

<*
 TypeExpr represents C3 type syntax.

 Payloads:
- unresolved: TYPE_IDENTIFIER name and optional module path.
- modify: TYPE_POINTER and TYPE_SLICE base type.
- array: TYPE_ARRAY and TYPE_VECTOR base type plus length expression.
  `len_expr` is null for inferred arrays such as `Type[*]`.
- generic: TYPE_GENERIC base type and generic argument expressions.
- func: TYPE_FUNCTION return type and PARAM_DECL parameter nodes.
*>
struct TypeExpr
{
	TypeKind kind;
	bool optional;

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

		struct func
		{
			Node* ret_type;
			NodeArray params;
		}
	}
}

struct CallExpr
{
	Node* callee;
	Node* macro_body_expr;
	NodeArray args;
	NodeArray attributes;
}

struct ContractExpr
{
	Node* exprs;
	StringID comment;
	Node* expr_string;
}

fn String? ContractExpr.get_comment(&self, StringPool* pool) => pool.get(self.comment);

struct ExprList
{
	NodeArray exprs;
}

enum LiteralKind : char
{
	INT_LITERAL,
	STRING_LITERAL,
	BYTES_LITERAL,
	REAL_LITERAL,
	BOOL_LITERAL,
	NULL_LITERAL,
}

struct LiteralExpr
{
	LiteralKind kind;

	union
	{
		long integer;
		double real;
		StringID string;
		char[] bytes;
		bool boolean;
	}
}

struct UnaryExpr
{
	UnaryOpKind operator;
	Node* expr;
}

struct PostUnaryExpr
{
	inline UnaryExpr unary;
}

struct CondExpr
{
	NodeArray exprs;
}

<*
 - variable: 
 - type: type_expr | missing
 - exprs:
*>
struct CatchExpr
{
	Node* variable;
	Node* type;
	NodeArray exprs;
}

<*
 - next: null | points to the next TryExpr
*>
struct TryExpr
{
	Node* variable;
	Node* type;
	Node* init;
	Node* next;
}

<*
 - then_expr: may be null for elvis
*>
struct TernaryExpr
{
	Node* cond;
	Node* then_expr;
	Node* else_expr;
	bool is_grouped;
	bool is_const;
}

struct MacroBodyExpr
{
	Node* body;
	NodeArray args;
}
