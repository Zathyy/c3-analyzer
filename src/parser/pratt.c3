<*
 Pratt parsing using Binding power
	
	Resources for Binding power pratt parsing:
	- https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html
*>
module analyzer::parser;
import std::collections;
import analyzer::core;

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
			*rbp = Precedence.CALL + 1; // TODO: CALL or None?
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
 @require(scope.ctx != null) 
 @param min_bp : "Starting binding power"
*>
fn Node*? parse_expr(ContextScope scope, Precedence min_bp = LOWEST)
{
	ParseContext* ctx = scope.ctx;
	Node* left = parse_prefix_expr(scope)!;

	while (true)
	{
		int lbp, rbp;
		get_binding_power(ctx.current().kind, &lbp, &rbp);

		// debug purposes
		plog::debug("Current Token: %s, LBP: %d, MinBP: %d", ctx.current().kind, lbp, min_bp);

		// BREAK if:
		// 1. Token is not an infix operator (lbp is -1)
		// 2. Token precedence is lower than current min_bp
		if (lbp == Precedence.NONE || lbp < min_bp)
		{
			break;
		}

		left = parse_infix(scope, left, (Precedence)rbp)!;
	}

	return left;
}

<*
 parse_prefix (Nud)
	Handles tokens that start an expression (e.g., -5, (expr), !true)
	It has no "left" side to worry about.
*>
fn Node*? parse_prefix_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	Token t = ctx.current();

	if (is_type(ctx))
	{
		return parse_type_expr({...scope, .flags = { .type_as_expression = true }}, null)!;
	}

	switch (t.kind)
	{
		case FN:
			return parse_lambda_expr(scope)!;
		case CT_EVAL:
			return parse_ct_eval_expr(scope)!;
		case ELLIPSIS:
			return parse_splat_expr(scope)!;
		case BUILTIN:
			return parse_builtin_expr(scope)!;
		case CT_DEFINED:
			return parse_ct_defined_expr(scope)!;
		case CT_FEATURE:
			return parse_ct_feature(scope)!;
		case LENGTHOF:
			return parse_lengthof_expr(scope)!;
		case IDENT:
		case CONST_IDENT:
		case AT_IDENT:
		case CT_IDENT:
		case HASH_IDENT:
		case TYPE_IDENT:
			return parse_ident_expr(scope)!;
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
			return parse_literal_expr(scope)!;
		case BANG:
		case BANGBANG:
		case MINUS:
		case BIT_NOT:
		case AMP:
		case AND:
		case ASTERISK:
			return parse_unary_expr(scope)!;
		case LBRACE:
			return parse_initializer_list_expr(scope)!;
		case LPAREN:
			return parse_group_expr(scope)!;
		default:
			plog::error(
				"parse_prefix_expr - Expected expression for token: ((%s) %s - %s)",
				ctx.token_text(ctx.current()),
				ctx.current()
				.kind);

			advance(ctx)!;
			return unexpected_at(ctx, t, "Unexpected expression for token '%s'", t.kind.description);
	}
}

<*
 parse_infix (Led)
	Handles tokens that connect expressions (e.g. 1 + 2, obj.prop, arr[0])
	It takes a pre-parsed "left" node and attaches a "right" side to it.
*>
fn Node*? parse_infix(ContextScope scope, Node* left, Precedence rbp)
{
	ParseContext* ctx = scope.ctx;
	Token t = ctx.current();

	switch (t.kind)
	{
		case LPAREN:
			return parse_call_expr(scope, left)!;
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
			return parse_binary_expr(scope, left, rbp)!;
		case PLUSPLUS:
		case MINUSMINUS:
		case BANG:
		case BANGBANG:
			return parse_post_unary_expr(scope, left, rbp)!;
		case QUESTION:
		case CT_TERNARY:
			return parse_ternary_expr(scope, left)!;
		case BIT_NOT:
			return parse_raise_suffix_expr(scope, left, t)!;
		case DOT:
		case SCOPE:
			return parse_access_expr(scope, left)!;
		case LBRACE:
			NodeKind kind = left.kind;
			if (kind == TYPE_EXPR)
			{
				int start_pos = left.offset.start;
				Node* init    = parse_initializer_list_expr(scope)!;

				Node* node = ctx.ast.alloc_node(COMPOUND_LITERAL_EXPR, start_pos);
				node.offset.end = ctx.current().pos;

				CompoundLiteralExpr* comp = node.as(COMPOUND_LITERAL_EXPR);
				comp.type_expr = left;
				comp.initializer_expr = init;

				return node;
			}
			return parse_generic_expr(scope)!;
		case LBRACKET:
			int start_pos = t.pos;
			advance(ctx)!; // Consume the '[' token
			return parse_range_expr(scope, left, start_pos)!;
		default:
			advance(ctx)!;
			return unexpected_at(ctx, t, "Unexpected infix token '%s'", t.kind);
	}
}

<*
 decl_or_expr ::= var_decl | expr
*>
fn Node*? parse_decl_or_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	if (ctx.is(VAR))
	{
		return parse_var_decl({ .ctx = ctx, .flags =  { .is_expr = true, .is_local = true, .skip_eos = true, .is_var = true }}, null)!;
	}

	Node* expr = parse_expr(scope)!;

	plog::debug("parse_decl_or_expr - (%s)", expr.kind.description);

	if (expr.kind != TYPE_EXPR && expr.kind != COMPOUND_LITERAL_EXPR)
	{
		return expr;
	}

	TokenKind next = ctx.current().kind;
	switch (next)
	{
		case RPAREN:
		case RBRACKET:
		case RBRACE:
		case RVEC:
			return expr;
		default:
			break;
	}

	return parse_var_decl({ .ctx = ctx, .flags = { .is_expr = true, .is_local = true, .skip_eos = true }}, expr)!;
}

<*
 "Shortcut" for when a left node has already been parsed (like an identifier) 
 and want to continue building an expression from that specific point without starting over
*>
fn Node*? parse_expr_resuming_with_left(ContextScope scope, Node* left, Precedence min_bp)
{
	ParseContext* ctx = scope.ctx;
	while (true)
	{
		int lbp, rbp;
		get_binding_power(ctx.current().kind, &lbp, &rbp);
		if (lbp < min_bp) break;

		left = parse_infix(scope, left, (Precedence)rbp)!;
	}
	return left;
}

fn Node*? parse_constant_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	return parse_expr(scope, ASSIGNMENT + 1)!;
}

<*
 @ensure return != null
*>
fn Node*? parse_try_chain_expr(ContextScope scope)
{
	ParseContext* ctx = scope.ctx;
	return parse_expr(scope, RELATIONAL + 1)!;
}
