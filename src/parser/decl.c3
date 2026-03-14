module c3_parser::parser;
import c3_parser::ast;
import c3::lexer;

import c3_parser::common;
import std::collections::list;

macro void make_invalid_decl(Parser* p, Decl* decl)
{
	decl.kind = DeclKind.INVALID;
	decl.span = p.span;
}

//TODO: make use of DeclKind.INVALID
fn Decl*? parse_module(Parser* p)
{
	expect(p, TokenType.MODULE)!;
    
    Decl* decl = mem::tnew(Decl);
	defer (catch err)
	{
		allocator::free(tmem, decl);
	}
    decl.kind = DeclKind.MODULE;
	decl.span = p.span;
    decl.mod.path = parse_path(p)!;
	//TODO: generics, attributes
    expect(p, TokenType.EOS)!;
	decl.span = decl.span.combine(p.span);
    return decl;
}

//TODO: make use of DeclKind.INVALID
fn void? parse_import(Parser* p)
{
	expect(p, TokenType.IMPORT)!;
    Decl* decl = mem::tnew(Decl);
	defer (catch err)
	{
		allocator::free(tmem, decl);
	}
    decl.kind = DeclKind.IMPORT;
	decl.span = p.span;
    decl.imp.path = parse_path(p)!;
    expect(p, TokenType.EOS)!;
	decl.span = decl.span.combine(p.span);
	p.section.ast.decls.push(decl);
	log::debug("Token after import: %s", p.token);
}

//TODO: make use of DeclKind.INVALID
fn void? parse_function(Parser* p)
{
	expect(p, TokenType.FUNC)!;
	Decl* decl = mem::tnew(Decl);
	defer (catch err)
	{
		allocator::free(tmem, decl);
	}
	decl.kind = DeclKind.FUNC;
	SourceSpan start = p.span;
	
	//TODO: parse type
	if (token_is(p, TokenType.TYPE_IDENT))
	{
		consume(p, TokenType.TYPE_IDENT)!;
	}

	decl.func.ret_type = p.token.text;
	advance(p)!;

	if (!token_is(p, TokenType.IDENT))
	{
		p.error("Expected function name after return type");
		return UNEXPECTED_TOKEN~;
	}

	decl.name = p.token.text;
	advance(p)!;

	expect(p, TokenType.LPAREN)!;

	// just simulate parsing args for now
	while (!token_is(p, TokenType.RPAREN))
	{
		advance(p)!;
	}

	advance(p)!;

	// skip last paren

	if (token_is(p, TokenType.LBRACE))
	{
		decl.func.compound = parse_compound(p)!;
	}

	decl.span = decl.span.combine(start);
	p.section.ast.decls.push(decl);
	log::debug("parsed function %s", decl.name);
}

<*
	global ::= TLOCAL? optional_type IDENT (('=' expression)? | (',' IDENT)* opt_attributes) ';'
	@return? consume!, expect!, UNEXPECTED_TOKEN
*>
fn void? parse_global(Parser* p)
{
	bool is_thread_local = consume(p, TokenType.TLOCAL)!;
    
    // Use a local list that clean up easily
    List{Decl*} decls;
    decls.init(tmem, 4); 
	defer (catch err)
	{
		decls.free();
	}

    do {
        Decl* decl = mem::tnew(Decl);
        decl.kind = DeclKind.VAR;
        decl.var_decl.kind = VarDeclKind.GLOBAL;
        decl.var_decl.is_threadlocal = is_thread_local;

        expect(p, TokenType.IDENT)!;
        decl.name = p.token.text;
        
        decls.push(decl);
    } while (consume(p, TokenType.COMMA)!);

    if (consume(p, TokenType.EQ)!)
    {
        if (decls.len() > 1)
        {
            p.error("Initialization is not allowed with multiple declarations.");
            return UNEXPECTED_TOKEN~;
        }
        // TODO: parse_expression()
    }

    expect(p, TokenType.EOS)!;

    foreach (d : decls) 
	{
		p.section.ast.decls.push(d);
	}
}

fn Decl*? parse_var_decl(Parser* p)
{
	Decl* decl = mem::tnew(Decl);
	defer (catch err)
	{
		allocator::free(tmem, decl);
	}
	decl.kind = DeclKind.VAR;
	decl.var_decl.kind = VarDeclKind.GLOBAL;


	return decl;
}