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

<*
	@require p.section != null
*>
fn void append_decl(Parser* p, Decl* decl)
{
	p.section.ast.decls.push(decl);	
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
	
	decl.func.ret_type = parse_type(p)!;

	if (!token_is(p, TokenType.IDENT))
	{
		p.error("Expected function name after return type");
		return UNEXPECTED_TOKEN~;
	}

	decl.name = p.token.text;
	advance(p)!;

	expect(p, TokenType.LPAREN)!;

	decl.func.params.tinit(4);

	if (!token_is(p, TokenType.RPAREN))
    {
        do 
		{
            decl.func.params.push(parse_param_decl(p)!);
        } 
		while (consume(p, TokenType.COMMA)!);
    }

	expect(p, TokenType.RPAREN)!;

	if (token_is(p, TokenType.LBRACE))
	{
		decl.func.compound = parse_compound(p)!;
	}

	decl.span = decl.span.combine(start);
	append_decl(p, decl);
	log::debug("parsed function %s", decl.name);
}

<*
	global ::= TLOCAL? optional_type IDENT (('=' expression)? | (',' IDENT)* opt_attributes) ';'
	@return? consume!, expect!, UNEXPECTED_TOKEN
*>
fn void? parse_global(Parser* p)
{
	bool is_thread_local = consume(p, TokenType.TLOCAL)!;
    
	TypeInfo* info = parse_type(p)!;

    // Use a local list that clean up easily
    List{Decl*} decls;
    decls.init(tmem, 4); 
	defer decls.free();

    do 
	{
        Decl* decl = mem::tnew(Decl);
        decl.kind = DeclKind.VAR;
        decl.var_decl.kind = VarDeclKind.GLOBAL;
        decl.var_decl.is_threadlocal = is_thread_local;
		decl.var_decl.type_info = info;

        if (token_is(p, TokenType.IDENT))
		{
        	decl.name = p.token.text;
			advance(p)!;
		}
		else
		{
			p.error("Expected Identifier for global variable");
			return UNEXPECTED_TOKEN~;
		}
        
        decls.push(decl);
    } while (consume(p, TokenType.COMMA)!);

    if (consume(p, TokenType.EQ)!)
    {
        if (decls.len() > 1)
        {
            p.error("Initialization is not allowed with multiple declarations.");
            return UNEXPECTED_TOKEN~;
        }

		// Parse the init expression, eg. int a = 2;
		decls.first()!.var_decl.init_expr = parse_expr(p)!;
    }

    expect(p, TokenType.EOS)!;

    foreach (d : decls) 
	{
		append_decl(p, d);
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

fn void? parse_alias_ident(Parser* p, Decl* decl)
{
	decl.name = p.token.text;
	advance(p)!;

	//TODO: Attributes.	

	expect(p, TokenType.EQ)!;

	if (token_is(p, TokenType.MODULE))
	{

	}
}

fn void? parse_alias_type(Parser* p, Decl* decl)
{
	decl.name = p.token.text;
	advance(p)!;

	//TODO: Attributes.

	expect(p, TokenType.EQ)!;

	if (consume(p, TokenType.FUNC)!)
	{
		decl.alias_decl.kind = AliasKind.FUNC;

		Decl* decl_type = mem::tnew(Decl);
		decl_type.kind = DeclKind.FUNC;
		
		decl.alias_decl.type.decl = decl_type;
		
		expect(p, TokenType.EOS)!;

		return;
	}

	decl.alias_decl.kind = AliasKind.TYPE;
	decl.alias_decl.type.type_info = parse_type(p)!;

	expect(p, TokenType.EOS)!;
}

fn void? parse_alias(Parser* p)
{
	expect(p, TokenType.ALIAS)!;

	Decl* decl = mem::tnew(Decl);
	defer (catch err)
	{
		allocator::free(tmem, decl);
	}

	decl.kind = DeclKind.ALIAS;

	if (token_is(p, TokenType.TYPE_IDENT))
	{
		parse_alias_type(p, decl)!;
	}
	else
	{
		parse_alias_ident(p, decl)!;
	}

	append_decl(p, decl);
}

fn void? parse_typedef(Parser* p)
{
	expect(p, TokenType.TYPEDEF)!;

	Decl* decl = mem::tnew(Decl);
	defer (catch err)
	{
		allocator::free(tmem, decl);
	}
	decl.kind = DeclKind.TYPEDEF;

	decl.name = p.token.text;
	
	expect(p, TokenType.TYPE_IDENT)!;

	expect(p, TokenType.EQ)!;

	decl.typedef_decl.type = parse_type(p)!;

	append_decl(p, decl);
}

fn Decl*? parse_param_decl(Parser* p)
{
    TypeInfo* type = parse_type(p)!;
    
    if (!token_is(p, TokenType.IDENT))
    {
        p.error("Expected parameter name");
        return UNEXPECTED_TOKEN~;
    }
    
    String name = p.token.text;
    SourceSpan span = type.span.combine(p.span);
    advance(p)!;

    Decl* decl = mem::tnew(Decl);
    decl.name = name;
    decl.var_decl.type_info = type;
    decl.span = span;
    return decl;
}