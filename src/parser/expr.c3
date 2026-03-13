module c3_parser::parser;
import c3_parser::ast;
import c3::lexer;

macro Expr* make_invalid_expr(Parser* p, String fmt, ...)
{
	Expr* bad = mem::tnew(Expr);
	bad.kind = ExprKind.INVALID;
	bad.span = p.span;
	bad.bad_expr.msg = string::format(tmem, fmt, $vasplat);
	return bad;
}

fn Expr*? parse_expr(Parser* p)
{
	Expr* expr = mem::tnew(Expr);
	defer (catch err)
	{
		allocator::free(tmem, expr);
	}

	return null;
}