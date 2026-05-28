<*
 Pratt parsing using Binding power
	
	Resources for Binding power pratt parsing:
	- https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html
*>
module parser::parser;

import parser::ast;
import lexer;
import std::core::ascii;

import parser::common;

import std::io;
import std::collections::list;

<*
	TYPE_EXPR - unresolved type, parser only cares about the syntax
*>
fn Node*? parse_type_expr(ParseContext* ctx, ParseFlags parse_flags = {})
{
	int start = ctx.peek(0).pos;

	Node* current_type = ctx.ast.alloc_node(TYPE_EXPR, start, ctx.peek().pos);
	Node* path_expr = parse_path_expr(ctx)!;

	//TODO:

	return current_type;
}

fn Node*? parse_ident_expr(ParseContext* ctx)
{
	int start = ctx.peek(0).pos;
	if (ctx.peek(1).kind == SCOPE)
	{
		return parse_path_expr(ctx, true)!;
	}
	Node* node = ctx.ast.alloc_node(IDENT_EXPR, start, ctx.peek().pos);
	IdentExpr* ident = node.as(IDENT_EXPR);
	ident.ident = ctx.ast.string_pool.internalize(ctx.token_text(ctx.peek(0)));
	advance(ctx)!;
	return node;
}

<*
	Parse a full path e.g. foo::bar::baz;
	@param [&inout] ctx
*>
fn Node*? parse_path_expr(ParseContext* ctx, bool as_prefix = false) => @pool()
{
	int start_pos = ctx.peek(0).pos;

	if (!ctx.is(IDENT) && ctx.peek(1).kind != SCOPE)
	{
		if (as_prefix)
		{
			return ctx.ast.alloc_node(MISSING, start_pos);
		}

		ctx.error("Expected a path identifier here");
		return ctx.ast.alloc_node(ERROR, start_pos);
	}

	Node* node = ctx.ast.alloc_node(PATH_EXPR, start_pos, ctx.peek().pos);
	PathExpr* path = node.as(PATH_EXPR);
	defer node.end_token = ctx.peek(0).pos;

	List{StringID} temp_segments;
	temp_segments.init(tmem, 8);

	while (true)
	{
		Token t = ctx.peek(0);
		temp_segments.push(ctx.ast.string_pool.internalize(ctx.token_text(t)));
		advance(ctx)!;

		if (!consume(ctx, SCOPE)!) break;

		if (!expect(ctx, IDENT)!)
		{
			temp_segments.push(-1);
			node.kind = MISSING;
			break;
		}
	}

	path.segments = alloc::clone_slice(ctx.arena, temp_segments.array_view());
	return node;
}

fn Node*? parse_binary_expr(ParseContext* ctx, Node* left, Precedence prec) 
{
	int start = ctx.peek(0).pos;
	TokenKind kind = ctx.peek(0).kind;
	advance(ctx)!;
	Node* right = parse_expr(ctx, prec)!;

	Node* node = ctx.ast.alloc_node(BINARY_EXPR, start, ctx.peek(0).pos);
	BinaryExpr* bin = node.as(BINARY_EXPR);
	bin.left = left;
	bin.right = right;
	bin.op = parser::binaryop_from_token(kind);
	return node;
}
