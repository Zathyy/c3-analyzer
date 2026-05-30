<*
 Pratt parsing using Binding power
	
	Resources for Binding power pratt parsing:
	- https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html
*>
module parser::parser;
import lexer;
import std::collections;
import parser::ast;

<*
 Should be aligned to C3C
	According to: https://c3-lang.org/language-rules/precedence/
*>
constdef Precedence : inline int
{
	NONE           = -1,
	LOWEST         =  0,
	ASSIGNMENT     =  10, // =, *=, /=, %=, +=, etc
	TERNARY        =  20, // ?:
	OR             =  30, // || |||
	AND            =  40, // && &&&
	RELATIONAL     =  50, // < > <= >= == !=
	ADDITIVE       =  60, // + - +++
	ORELSE         =  70, // ?: ??
	BIT            =  80, // ^ | &
	SHIFT          =  90, // << >>
	MULTIPLICATIVE =  100, // * / %
	UNARY          =  110, // ! - + ~ * & prefix ++/--
	CALL           =  120, // . () [] postfix ++ -- !! ! ~
	HIGHEST        =  130,
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
			*rbp = Precedence.CALL; // TODO: CALL or None?
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
 parse expressions recursively with Pratt parsing
	using Binding power.
 @param [&inout] ctx
 @param min_bp : "Starting binding power"
*>
fn Node*? parse_expr(ParseContext* ctx, Precedence min_bp = LOWEST)
{
	Node* left = parse_prefix_expr(ctx)!;

	while (true)
	{
		int lbp, rbp;
		get_binding_power(ctx.current().kind, &lbp, &rbp);

		// debug purposes
		log::debug("Current Token: %s, LBP: %d, MinBP: %d", ctx.current().kind, lbp, min_bp);

		// BREAK if:
		// 1. Token is not an infix operator (lbp is -1)
		// 2. Token precedence is lower than current min_bp
		if (lbp == Precedence.NONE || lbp < (int)min_bp)
		{
			break;
		}

		left = parse_infix(ctx, left, (Precedence)rbp)!;
	}

	if (min_bp == 0 && ctx.is(AT_IDENT))
	{
		// TODO:
	}

	return left;
}

<*
 parse_prefix (Nud)
	Handles tokens that start an expression (e.g., -5, (expr), !true)
	It has no "left" side to worry about.
*>
fn Node*? parse_prefix_expr(ParseContext* ctx)
{
	Token t = ctx.current();

	if (is_type(ctx))
	{
		return parse_type_expr(ctx, { .type_as_expression = true })!;
	}

	switch (t.kind)
	{
		case CT_FEATURE:
		case CT_DEFINED:
		case AT_IDENT:
		case AT_CONST_IDENT:
		case AT_TYPE_IDENT:
		case IDENT:
		case CONST_IDENT:
		case TYPE_IDENT:
		case CT_IDENT:
		case CT_CONST_IDENT:
		case CT_TYPE_IDENT:
		case HASH_IDENT:
		case HASH_CONST_IDENT:
		case HASH_TYPE_IDENT:
			return parse_ident_expr(ctx)!;
		case STRING_LITERAL:
		case CHAR_LITERAL:
		case TRUE:
		case FALSE:
		case NULL:
		case FLOAT_DECIMAL_LITERAL:
		case FLOAT_HEX_LITERAL:
		case INT_DECIMAL_LITERAL:
		case INT_HEX_LITERAL:
		case INT_OCTAL_LITERAL:
		case INT_BIN_LITERAL:
		case BYTES_LITERAL:
			return parse_literal_expr(ctx)!;
		case BANG:
		case BANGBANG:
		case MINUS:
		case BIT_NOT:
		case AMP:
		case AND:
		case ASTERISK:
			return parse_unary_expr(ctx)!;
		case LBRACE:
			return parse_compound_literal(ctx)!;
		default:
			log::error(
				"parse_prefix_expr - Expected expression for token: ((%s) %s - %s)",
				ctx.token_text(ctx.current()),
				ctx.current()
				.kind);
			ctx.error("Expected expression");
			return EXPECTED_EXPRESSION~;
	}
}

<*
 parse_infix (Led)
	Handles tokens that connect expressions (e.g. 1 + 2, obj.prop, arr[0])
	It takes a pre-parsed "left" node and attaches a "right" side to it.
*>
fn Node*? parse_infix(ParseContext* ctx, Node* left, Precedence rbp)
{
	Token t = ctx.current();

	switch (t.kind)
	{
		case LPAREN:
			return parse_call_expr(ctx, left)!;
		case PLUS:
		case PLUS_ASSIGN:
		case MINUS:
		case MINUS_ASSIGN:
		case ASTERISK:
		case MULT_ASSIGN:
		case DIV:
		case DIV_ASSIGN:
		case MOD:
		case MOD_ASSIGN:
		case EQ:
		case GREATER:
		case GREATER_EQ:
		case LESS:
		case LESS_EQ:
		case AND:
		case OR:
		case BIT_OR:
		case BIT_XOR:
		case BIT_XOR_ASSIGN:
		case BIT_OR_ASSIGN:
		case AMP:
		case BIT_AND_ASSIGN:
		case EQEQ:
		case NOT_EQUAL:
		case RSHIFT:
		case LSHIFT:
		case RSHIFT_ASSIGN:
		case LSHIFT_ASSIGN:
		case QUESTQUEST:
		case ELVIS:
		case CT_CONCAT_OP:
		case CT_CONCAT_ASSIGN:
		case CT_AND_OP:
		case CT_OR_OP:
			return parse_binary_expr(ctx, left, rbp)!;
		default:
			ctx.error("Unexpected infix token: %s", t.kind);
			return UNEXPECTED_TOKEN~;
	}
}

<*
 decl_or_expr ::= var_decl | expr
*>
fn Node*? parse_decl_or_expr(ParseContext* ctx)
{
	if (ctx.is(VAR))
	{
		return parse_var_decl(ctx, { .is_expr = true, .is_local = true, .skip_eos = true, .is_var = true })!;
	}

	if (is_type(ctx) && is_declaration_followup(ctx))
	{
		return parse_var_decl(ctx, { .is_expr = true, .is_local = true, .skip_eos = true })!;
	}

	return parse_expr(ctx)!;
}

<*
 "Shortcut" for when a left node has already been parsed (like an identifier) 
 and want to continue building an expression from that specific point without starting over
*>
fn Node*? parse_expr_resuming_with_left(ParseContext* ctx, Node* left, Precedence min_bp)
{
	while (true)
	{
		int lbp, rbp;
		get_binding_power(ctx.current().kind, &lbp, &rbp);
		if (lbp < min_bp) break;

		left = parse_infix(ctx, left, (Precedence)rbp)!;
	}
	return left;
}

fn Node*? parse_constant_expr(ParseContext* ctx)
{
	return parse_expr(ctx, ASSIGNMENT + 1)!;
}
