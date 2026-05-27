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
	Should be aligned to C3C
	According to: https://c3-lang.org/language-rules/precedence/
*>
constdef Precedence : inline int
{
	NONE           = -1,
	LOWEST         = 0,
	ASSIGNMENT     = 10, // =, *=, /=, %=, +=, etc
	TERNARY        = 20, // ?:
	OR             = 30, // || |||
	AND            = 40, // && &&&
	RELATIONAL     = 50, // < > <= >= == !=
	ADDITIVE       = 60, // + - +++
	ORELSE         = 70, // ?: ??
	BIT            = 80, // ^ | &
	SHIFT          = 90, // << >>
	MULTIPLICATIVE = 100, // * / %
	UNARY          = 110, // ! - + ~ * & prefix ++/--
	CALL           = 120, // . () [] postfix ++ -- !! ! ~
  HIGHEST        = 130,
}

<*
	@param [&inout] lbp : "How strongly the operator pulls on the expression to its left."
	@param [&inout] rbp : "How strongly it pulls on the expression to its right."
*>
fn void get_binding_power(TokenKind type, int* lbp, int* rbp)
{
	switch (type)
	{
		// Assignment (Right-associative)
		case EQ:
		case MULT_ASSIGN:
		case PLUS_ASSIGN:
		case MINUS_ASSIGN:
		case BIT_OR_ASSIGN:
		case BIT_XOR_ASSIGN:
		case DIV_ASSIGN:
		case MOD_ASSIGN:
		case BIT_AND_ASSIGN:
		case LSHIFT_ASSIGN:
		case RSHIFT_ASSIGN:
		case CT_CONCAT_ASSIGN:
			*lbp = Precedence.ASSIGNMENT;
			*rbp = Precedence.ASSIGNMENT - 1;
			break;

		case CT_TERNARY:
		case QUESTION:
			*lbp = Precedence.TERNARY;
			*rbp = Precedence.TERNARY - 1;
			break;

		case OR:
		case CT_OR_OP:
			*lbp = Precedence.OR;
			*rbp = Precedence.OR + 1;
			break;

		case AND:
		case CT_AND_OP:
			*lbp = Precedence.AND;
			*rbp = Precedence.AND + 1;
			break;

		// RELATIONAL
		case EQEQ:
		case NOT_EQUAL:
		case GREATER:
		case GREATER_EQ:
		case LESS:
		case LESS_EQ:
			*lbp = Precedence.RELATIONAL;
			*rbp = Precedence.RELATIONAL + 1;
			break;

		// ADDITIVE
		case PLUS:
		case MINUS:
		case CT_CONCAT_OP:
			*lbp = Precedence.ADDITIVE;
			*rbp = Precedence.ADDITIVE + 1;
			break;

		case QUESTQUEST:
		case ELVIS:
			*lbp = Precedence.ORELSE;
			*rbp = Precedence.ORELSE + 1;
			break;

		// Bit
		case BIT_OR:
		case BIT_XOR:
		case AMP:
			*lbp = Precedence.BIT;
			*rbp = Precedence.BIT + 1;
			break;

		// Shift
		case RSHIFT:
		case LSHIFT:
			*lbp = Precedence.SHIFT;
			*rbp = Precedence.SHIFT + 1;
			break;

		// MULTIPLICATIVE
		case DIV:
		case MOD:
		case ASTERISK:
			*lbp = Precedence.MULTIPLICATIVE;
			*rbp = Precedence.MULTIPLICATIVE + 1;
			break;

		// Postfix / Access / Call
		case DOT:
		case SCOPE:
		case LPAREN:
		case LBRACE:
		case LBRACKET:
			*lbp = Precedence.CALL;
			*rbp = Precedence.CALL; //TODO: CALL or None?
			break;
		case BANGBANG:
		case PLUSPLUS:
		case MINUSMINUS:
		case BANG:
		case BIT_NOT:
			*lbp = Precedence.CALL;
			*rbp = Precedence.LOWEST; // Postfix has no RHS to pull
			break;

		default:
			*lbp = Precedence.NONE;
			*rbp = Precedence.NONE;
			break;
	}
}



<*
	TYPE_EXPR - unresolved type, parser only cares about the syntax
*>
fn Node*? parse_type_expr(ParseContext* ctx, ParseFlags parse_flags = {})
{
	int start = ctx.peek(0).pos;

	Node* current_type = new_node(ctx, TYPE_EXPR, start);
	Node* path_expr = parse_path_expr(ctx)!;



	return current_type;
}

fn Node*? parse_ident_expr(ParseContext* ctx)
{
	int start = ctx.peek(0).pos;
	Node* node = new_node(ctx, IDENT_EXPR, start);
	if (ctx.peek().kind == SCOPE)
	{
		return parse_path_expr(ctx, true)!;
	}
	IdentExpr* ident = node.as_ident();
	ident.ident = ctx.token_text(ctx.peek(0)).copy(ctx.arena);
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

	if (!ctx.is(IDENT))
	{
		//TODO:	
	}

	Node* node = new_node(ctx, PATH_EXPR, start_pos);
	PathExpr* path = node.as_path();
	defer node.end_token = ctx.peek(0).pos;

	List{String} temp_segments;
    temp_segments.init(tmem, 8);

	while (true)
	{
		Token t = ctx.peek(0);
		temp_segments.push(ctx.token_text(t));
		advance(ctx)!;

		if (!consume(ctx, SCOPE)!) break;

		if (!is_some_ident(ctx.peek(0).kind))
		{
			ctx.error("Expected identifier after '::'");
			
		}
	}

	path.segments = alloc::clone_slice(ctx.arena, temp_segments.array_view());
	return node;
}