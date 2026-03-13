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
				if (is_some_ident(p.next.type))
				{
					return parse_decl_stmt(p)!;
				}
			}

			return parse_expr_stmt(p);
		}
	}
}

fn Stmt*? parse_expr_stmt(Parser* p)
{	
	advance(p)!;

	Stmt* stmt = mem::tnew(Stmt);
	return make_invalid_stmt(p, stmt);
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
	Stmt* stmt = mem::tnew(Stmt);
	stmt.kind = StmtKind.VAR;

	if (consume(p, TokenType.VAR)!)
	{

	}
	else
	{
		
	}

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
	expect(p, TokenType.RETURN)!;
	Stmt* stmt = mem::tnew(Stmt);
	defer (catch err)
	{
		allocator::free(tmem, stmt);
	}

	stmt.kind = StmtKind.RETURN;
	
	while (!token_is(p, TokenType.EOS))
	{
		//TODO: parse_expr();

	}

	if (!consume(p, TokenType.EOS)!)
	{
		p.error("Expected eos");
		return make_invalid_stmt(p, stmt);
	}

	return stmt;
}