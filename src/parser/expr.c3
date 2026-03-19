module c3_parser::parser;
import c3_parser::ast;
import c3::lexer;
import c3_parser::common;

fn Expr* make_invalid_expr(SourceSpan span)
{
	Expr* bad = mem::tnew(Expr);
	bad.kind = ExprKind.INVALID;
	bad.span = span;
	return bad;
}

<*
	parse expressions recursively using Pratt parsing
	using Binding power.
	@param [&inout] p
	@param min_bp : "Starting binding power, always call with 0, it will call itself recursively with other values"
*>
fn Expr*? parse_expr(Parser* p, int min_bp = 0)
{
	Expr* left = parse_prefix(p)!;

	while (true)
	{
		int lbp, rbp;
		get_binding_power(p.token.type, &lbp, &rbp);

		// If the next operator doesn't bind strongly enough to the left, we stop
		if (lbp < min_bp) break;

		left = parse_infix(p, left, rbp)!;
	}

	return left;
}

fn Expr* make_binary_expr(Expr* left, TokenType op, Expr* right)
{
    Expr* expr = mem::tnew(Expr);
    expr.kind = ExprKind.BINARY;
    expr.binary_expr.left = left;
    expr.binary_expr.op = op;
    expr.binary_expr.right = right;

    expr.span = left.span.combine(right.span);

    return expr;
}

fn Expr* make_unary_expr(TokenType op, Expr* rhs, SourceSpan op_span)
{
    Expr* expr = mem::tnew(Expr);
    expr.kind = ExprKind.UNARY;
    expr.unary_expr.op = op;
    expr.unary_expr.rhs = rhs;

    expr.span = op_span.combine(rhs.span);
    
    return expr;
}

fn Expr* make_type_expr(TypeInfo* info)
{
    Expr* node = mem::tnew(Expr);
    node.kind = ExprKind.TYPE;
    node.type_expr.type = info;
    node.span = info.span;
    
    return node;
}

fn Expr* make_ternary_expr(Expr* cond, Expr* true_expr, Expr* false_expr)
{
    Expr* expr = mem::tnew(Expr);
    expr.kind = ExprKind.TERNARY;
    expr.ternary_expr.cond = cond;
    expr.ternary_expr.true_expr = true_expr;
    expr.ternary_expr.false_expr = false_expr;

    expr.span = cond.span.combine(false_expr.span);
    
    return expr;
}

fn Expr*? parse_ternary(Parser* p, Expr* condition, int rbp)
{
    expect(p, TokenType.QUESTION)!;

    Expr* true_expr = parse_expr(p, 0)!;

    expect(p, TokenType.COLON)!;

    Expr* false_expr = parse_expr(p, rbp)!;

    return make_ternary_expr(condition, true_expr, false_expr);
}

fn Expr*? parse_call(Parser* p, Expr* callee)
{
    expect(p, TokenType.LPAREN)!;

    Expr* call = mem::tnew(Expr);
    call.kind = ExprKind.CALL;
    call.call_expr.callee = callee;
	call.call_expr.args.tinit(4);

    if (!token_is(p, TokenType.RPAREN))
    {
        do 
		{
            Expr* arg = parse_expr(p)!;
            call.call_expr.args.push(arg);
        } 
		while (consume(p, TokenType.COMMA)!);
    }

    expect(p, TokenType.RPAREN)!;
    
    call.span = callee.span.combine(p.span);

    return call;
}

fn Expr*? parse_ident(Parser* p)
{
    String name = p.token.text;
    SourceSpan span = p.span;

    advance(p)!;

    Expr* node = mem::tnew(Expr);
    node.kind = ExprKind.IDENTIFIER;
    node.value = name;
    node.span = span;

    return node;
}

fn Expr*? parse_literal(Parser* p)
{
    TokenType type = p.token.type;
    String value = p.token.text;
    SourceSpan span = p.span;

    advance(p)!;

    Expr* node = mem::tnew(Expr);
    node.span = span;

    switch (type)
    {
        case TokenType.INTEGER:
            node.kind = ExprKind.INTEGER;
            node.value = value;
            break;

        case TokenType.REAL:
            node.kind = ExprKind.REAL;
            node.value = value;
            break;

        case TokenType.STRING:
            node.kind = ExprKind.STRING;
            node.value = value;
            break;

        case TokenType.TRUE:
        case TokenType.FALSE:
            node.kind = ExprKind.BOOL;
            node.value = value;
            break;

        default:
            p.error("Expected literal, found %s", type);
            return UNEXPECTED_TOKEN~;
    }

    return node;
}