module c3_parser::parser;

import c3_parser::ast;
import c3::lexer;
import c3_parser::common;

<*
	'{' ... '}'
*>
fn Stmt*? parse_compound(Parser* parser)
{
 	expect(parser, TokenType.LBRACE)!;

	Stmt* stmt = mem::tnew(Stmt);
	stmt.type = StmtType.COMPOUND;

	SourceSpan start = parser.span;

	do
	{
		advance(parser)!;
	} 
	while (parser.token.type != TokenType.RBRACE);

	stmt.compound.body = start.combine(parser.span);

	return stmt;
}

fn Stmt*? parse_defer(Parser* parser)
{
	expect(parser, TokenType.DEFER)!;

	Stmt* stmt = mem::tnew(Stmt);
	stmt.type = StmtType.DEFER;

	if (consume(parser, TokenType.TRY)!)
	{
		stmt.defer_stmt.is_try = true;
	}
	else if (consume(parser, TokenType.CATCH)!)
	{
		stmt.defer_stmt.is_catch = true;
	}
	else if (token_is(parser, TokenType.LPAREN))
	{
		advance(parser)!;

		if (!consume(parser, TokenType.CATCH)!)
		{
			parser.error("Expected 'catch' after 'defer ('");
			return UNEXPECTED_TOKEN~;
		}

		if (catch expect(parser, TokenType.IDENT))
		{
			parser.error("Expected 'Identifier' after catch");
			return UNEXPECTED_TOKEN~;
		}

		advance(parser)!;

		if (catch expect(parser, TokenType.RPAREN))
		{
			parser.error("Expected a closing ')' after 'Identifier");
			return UNEXPECTED_TOKEN~;
		}

		advance(parser)!;

		stmt.defer_stmt.compound = parse_compound(parser)!;
		stmt.defer_stmt.is_catch = true;
	}

	return stmt;
}