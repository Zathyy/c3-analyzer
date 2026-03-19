module c3_parser::parser;

import c3_parser::ast;
import c3::lexer;
import c3_parser::common;

fn Stmt* make_invalid_stmt(Parser* p, Stmt* stmt)
{
	stmt.kind = StmtKind.INVALID;
	stmt.span = p.span;
	return stmt;
}

fn Stmt*? parse_stmt(Parser* p)
{
	TokenType type = p.token.type;

	switch (type)
	{
		case TokenType.LBRACE:
			return parse_compound(p)!;
		case TokenType.VAR:
			return parse_decl_stmt(p)!;
		case TokenType.RETURN:
			return parse_return(p)!;
		default:
		{
			if (is_type_start(type))
			{
				return parse_decl_stmt(p)!;
			}

			return parse_expr_stmt(p)!;
		}
	}
}

fn Stmt*? parse_expr_stmt(Parser* p)
{	
	Expr* expr = parse_expr(p)!;
    expect(p, TokenType.EOS)!;

    Stmt* stmt = mem::tnew(Stmt);
    stmt.kind = StmtKind.EXPR;
    stmt.expr_stmt.expr = expr;
    stmt.span = expr.span;
    
    return stmt;
}

<*
	'{' 
		Stmt list
	'}'
*>
fn Stmt*? parse_compound(Parser* p)
{
 	expect(p, TokenType.LBRACE)!;

	Stmt* stmt = mem::tnew(Stmt);
	stmt.kind = StmtKind.COMPOUND;

	while (p.token.type != TokenType.RBRACE)
	{
		if (p.eof()) break;

		Stmt*? child = parse_stmt(p);
		if (catch err = child)
		{
			//TODO: handle error?
			continue;
		}

		if (!stmt.compound.stmts.is_initialized())
		{
			stmt.compound.stmts.tinit();
		}

		stmt.compound.stmts.push(child);
	} 

	expect(p, TokenType.RBRACE)!;
	return stmt;
}

<*
	see `DeclStmt`
*>
fn Stmt*? parse_decl_stmt(Parser* p)
{
    TypeInfo* info = null;
    
    // Handle 'var x = ...' (Inferred) vs 'int x = ...' (Explicit)
    if (!consume(p, TokenType.VAR)!)
    {
        info = parse_type(p)!;
    }

    Token name_tok = p.token;
    expect(p, TokenType.IDENT)!;

    // Handle optional initializer: '= 10'
    Expr* init = null;
    if (consume(p, TokenType.EQ)!)
    {
        init = parse_expr(p)!;
    }

    expect(p, TokenType.EOS)!;

    Decl* decl = mem::tnew(Decl);
    decl.name = name_tok.text;
    decl.var_decl.type_info = info; // Might be null if 'var' was used
    decl.var_decl.init_expr = init;

    Stmt* stmt = mem::tnew(Stmt);
    stmt.kind = StmtKind.DECL;
    stmt.decl_stmt.decl = decl;
    stmt.span = p.span.combine(p.span);
    
    return stmt;
}

fn Stmt*? parse_defer(Parser* p)
{
	expect(p, TokenType.DEFER)!;

	Stmt* stmt = mem::tnew(Stmt);
	stmt.kind = StmtKind.DEFER;

	if (consume(p, TokenType.TRY)!)
	{
		stmt.defer_stmt.is_try = true;
	}
	else if (consume(p, TokenType.CATCH)!)
	{
		stmt.defer_stmt.is_catch = true;
	}
	else if (token_is(p, TokenType.LPAREN))
	{
		advance(p)!;

		if (!consume(p, TokenType.CATCH)!)
		{
			p.error("Expected 'catch' after 'defer ('");
			return UNEXPECTED_TOKEN~;
		}

		expect(p, TokenType.IDENT)!;
		expect(p, TokenType.RPAREN)!;

		stmt.defer_stmt.compound = parse_compound(p)!;
		stmt.defer_stmt.is_catch = true;
	}

	return stmt;
}

fn Stmt*? parse_return(Parser* p)
{
	SourceSpan start = p.span;
    expect(p, TokenType.RETURN)!;
    
    Expr* expr = null;
    if (!token_is(p, TokenType.EOS))
    {
        expr = parse_expr(p, 0)!;
    }

    expect(p, TokenType.EOS)!;

    Stmt* stmt = mem::tnew(Stmt);
    stmt.kind = StmtKind.RETURN;
    stmt.return_stmt.expr = expr;
    stmt.span = start.combine(p.span);
    
    return stmt;
}