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
- func: TYPE_FUNCTION return type and VAR_DECL parameter nodes.
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
	bool is_outer_call;
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

struct BuiltinExpr
{
	BuiltinFunction builtin;
	StringID name;
}

struct CompilerConstExpr
{
	inline BuiltinExpr expr;
}

struct SplatExpr
{
	Node* inner;
}

struct VasplatExpr
{
	Node* range_expr;
}

struct NamedArgExpr
{
	StringID name;
	Node* value;
}

struct EvalNamedArgExpr
{
	Node* name;
	Node* value;
}

struct CtEvalExpr
{
	Node* inner_expr;
}

struct LambdaExpr
{
	NodeArray attributes;
	NodeArray params;
	Node* return_type;
	Node* body;
}

struct GenericIdentExpr
{
	NodeArray exprs;
}

struct CastExpr
{
	Node* operand;
	Node* inner;
}

struct GroupExpr
{
	Node* inner;
}

struct InitializerListExpr
{
	NodeArray exprs;
}

<*
 - `path`:  Left-hand side part of the path (null if it's the start)
 - `field`: Valid if kind == PERIOD (.field)
 - `start`: Valid if kind == INDEX or RANGE ([start])
 - `end`:   Valid if kind is RANGE ([start .. end])
*>
struct DesignatorExpr
{
	DesignatorKind kind;
	Node* path;

	union
	{
		Node* field;
		Node* range;
	}
}

<*
 - `path`: DESIGNATOR_EXPR node chain (.foo.bar)
 - `value`: assigned expression node (= 42)
*>
struct DesignatedInitializerExpr
{
	Node* path;
	Node* value;
}

struct CompoundLiteralExpr
{
	Node* initializer_expr;
	Node* type_expr;
}

struct AccessExpr
{
	AccessKind kind;
	Node* left;
	Node* member;
}

struct MaybeDeferExpr
{
	Node* left;
}

<*
 - `start_from_end`: True if start had '^' (BIT_XOR)
 - `end_from_end`: True if end had '^' (BIT_XOR)
*>
struct RangeExpr
{
	RangeKind kind;
	bool start_from_end;
	bool end_from_end;
	Node* start;
	Node* end;
}
