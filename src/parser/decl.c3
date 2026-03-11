module c3_parser::parser;
import c3_parser::ast;
import c3::lexer;

import c3_parser::common;
import std::collections::list;

fn Decl*? parse_module(Parser* parser)
{
	expect(parser, TokenType.MODULE)!;
    
    Decl* decl = mem::tnew(Decl);
    decl.type = DeclType.MODULE;
	decl.span = parser.span;
    decl.mod.path = parse_path(parser)!;
	//TODO: generics, attributes
    expect(parser, TokenType.EOS)!;
	decl.span = decl.span.combine(parser.span);
    return decl;
}

fn void? parse_import(Parser* parser)
{
	expect(parser, TokenType.IMPORT)!;
    
    Decl* decl = mem::tnew(Decl);
    decl.type = DeclType.IMPORT;
	decl.span = parser.span;
    decl.imp.path = parse_path(parser)!;
    expect(parser, TokenType.EOS)!;
	decl.span = decl.span.combine(parser.span);
	parser.section.ast.decls.push(decl);
	log::debug("Token after import: %s", parser.token);
}

fn void? parse_function(Parser* parser)
{
	expect(parser, TokenType.FUNC)!;

	Decl* decl = mem::tnew(Decl);
	decl.type = DeclType.FUNC;
	SourceSpan start = parser.span;
	
	//TODO: parse type
	if (token_is(parser, TokenType.TYPE_IDENT))
	{
		consume(parser, TokenType.TYPE_IDENT)!;
	}

	decl.func.ret_type = parser.token.text;
	advance(parser)!;

	if (!token_is(parser, TokenType.IDENT))
	{
		parser.error("Expected function name after return type");
		return UNEXPECTED_TOKEN~;
	}

	decl.name = parser.token.text;
	advance(parser)!;

	consume(parser, TokenType.LPAREN)!;

	// just simulate parsing args for now
	while (!token_is(parser, TokenType.RPAREN))
	{
		advance(parser)!;
	}

	advance(parser)!;

	// skip last paren

	if (token_is(parser, TokenType.LBRACE))
	{
		decl.func.block = parse_compound(parser)!;
	}

	decl.span = decl.span.combine(start);
	parser.section.ast.decls.push(decl);
}

<*
	global ::= TLOCAL? optional_type IDENT (('=' expression)? | (',' IDENT)* opt_attributes) ';'
*>
fn void? parse_global(Parser* parser)
{
	bool is_thread_local = consume(parser, TokenType.TLOCAL)!;
    
    // Use a local list that clean up easily
    List{Decl*} decls;
    decls.init(tmem, 4); 

    do {
        Decl* decl = mem::tnew(Decl);
        decl.type = DeclType.VAR;
        decl.var_decl.kind = VarDeclKind.GLOBAL;
        decl.var_decl.is_threadlocal = is_thread_local;

        expect(parser, TokenType.IDENT)!;
        decl.name = parser.token.text;
        
        decls.push(decl);
    } while (consume(parser, TokenType.COMMA)!);

    if (consume(parser, TokenType.EQ)!)
    {
        if (decls.len() > 1)
        {
            parser.error("Initialization is not allowed with multiple declarations.");
            return UNEXPECTED_TOKEN~;
        }
        // TODO: parse_expression()
    }

    expect(parser, TokenType.EOS)!;

    foreach (d : decls) 
	{
		parser.section.ast.decls.push(d);
	}
}