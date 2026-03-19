module c3_parser::parser;

import c3_parser::ast;
import c3::lexer;

import c3_parser::common;
import std::collections::list;

fn TypeInfo* make_invalid_type_info(Parser* p, TypeInfo* info)
{
	info.kind = TypeInfoKind.INVALID;
	if (info.span.is_valid())
	{
		info.span = info.span.combine(p.span);
	}
	else
	{
		info.span = p.span;
	}
	return info;
}

fn TypeInfo* type_info_new(TypeInfoKind kind, SourceSpan span)
{
	TypeInfo* info = mem::tnew(TypeInfo);
	info.kind = kind;
	info.span = span;
	return info;
}

fn bool is_type_start(TokenType type) 
{
    if (type >= TokenType.BOOL && type <= TokenType.FLOAT128) {
        return true;
    }

    switch (type)
    {
		case TokenType.TYPEID:
		case TokenType.FAULT:
		case TokenType.ANY:
		case TokenType.VOID:
		case TokenType.TYPE_IDENT:
		case TokenType.CT_TYPE_IDENT:
		case TokenType.CT_TYPEOF:
		case TokenType.CT_EVALTYPE:
		case TokenType.CT_VATYPE:
		case TokenType.CT_TYPEFROM:
            return true;
        default:
            return false;
    }
}

fn bool? consume_type_name(Parser* p, String type)
{
	if (token_is(p, TokenType.IDENT) || is_keyword_ident(p.token.type))
	{
		p.error("Names of %s must start with an uppercase letter", type);
		return false;
	}
	if (token_is(p, TokenType.CONST_IDENT))
	{
		p.error("Names of %s cannot be all uppercase", type);
		return false;
	}
	if (!consume(p, TokenType.TYPE_IDENT)!)
	{
		p.error("'%s' should be followed by the name of the %s", type, type);
		return false;
	}

	return true;
}

fn TypeInfo* make_type_info_generic(TypeInfo* base, List{Expr*} params, SourceSpan span)
{
	TypeInfoGeneric* gen = mem::tnew(TypeInfoGeneric);
	gen.base = base;
	gen.params = params;

    TypeInfo* info = mem::tnew(TypeInfo);
    info.kind = TypeInfoKind.GENERIC;
    info.data = gen;
    info.span = span;
    info.is_optional = false;

    return info;
}

fn TypeInfo* make_type_info_ptr(TypeInfo* base, SourceSpan span)
{
    TypeInfoPtr* data = mem::tnew(TypeInfoPtr);
    data.base = base;

    TypeInfo* node = mem::tnew(TypeInfo);
    node.kind = TypeInfoKind.POINTER;
    node.data = data;
    node.span = span; // The span of the '*' character
    node.is_optional = false;

    return node;
}

fn TypeInfo* make_type_info_ident(String name, SourceSpan span)
{
    TypeInfoIdent* data = mem::tnew(TypeInfoIdent);
    data.name = name;

    TypeInfo* node = mem::tnew(TypeInfo);
    node.kind = TypeInfoKind.IDENTIFIER;
    node.data = data;
    node.span = span;
    node.is_optional = false;

    return node;
}

fn TypeInfo* make_type_info_func(TypeInfo* ret, List{TypeInfo*} params, bool var_, SourceSpan span)
{
    TypeInfoFunc* data = mem::tnew(TypeInfoFunc);
    data.return_info = ret;
    data.params = params;
    data.is_variadic = var_;

    TypeInfo* node = mem::tnew(TypeInfo);
    node.kind = TypeInfoKind.FUNCTION;
    node.data = data;
    node.span = span;
    node.is_optional = false;

    return node;
}

fn TypeInfo* make_type_info_array(TypeInfo* base, Expr* length, SourceSpan span)
{
    TypeInfoArray* data = mem::tnew(TypeInfoArray);
    data.base = base;
    data.length_expr = length;

    TypeInfo* node = mem::tnew(TypeInfo);
    node.kind = TypeInfoKind.ARRAY;
    node.data = data;
    node.span = span;
    node.is_optional = false;

    return node;
}

fn TypeInfo*? parse_generic_type_params(Parser* p, TypeInfo* base)
{
    List{Expr*} params;
	params.tinit();

    if (!token_is(p, TokenType.RBRACE))
    {
        do 
		{
            params.push(parse_expr(p)!);
        } 
		while (consume(p, TokenType.COMMA)!);
    }

    expect(p, TokenType.RBRACE)!;
    return make_type_info_generic(base, params, base.span.combine(p.span));
}

fn TypeInfo*? parse_primary_type(Parser* p)
{
    SourceSpan span = p.span;

    if (consume(p, TokenType.FUNC)!)
    {
        return parse_function_type(p, span)!;
    }
    
    if (is_type_start(p.token.type))
    {
        String name = p.token.text;
        advance(p)!;
        return make_type_info_ident(name, span);
    }

    p.error("Expected a type name or 'fn'");
    return UNEXPECTED_TOKEN~;
}

fn TypeInfo*? parse_type(Parser* p)
{
    TypeInfo* type = parse_primary_type(p)!;
	log::debug("parse_type()");

    while (true)
    {
        if (consume(p, TokenType.STAR)!) 
        {
            type = make_type_info_ptr(type, p.span);
        }
        else if (consume(p, TokenType.LBRACKET)!) 
        {
            // Array: [ <expr> ]
            Expr* length = null;
            if (!token_is(p, TokenType.RBRACKET)) 
			{
                length = parse_expr(p, 0)!; 
            }
            expect(p, TokenType.RBRACKET)!;
            type = make_type_info_array(type, length, p.span);
        }
        else if (consume(p, TokenType.LBRACE)!)
        {
            // Generic: { ... }
			log::debug("parse_type() - Found LBRACE");
            type = parse_generic_type_params(p, type)!;
        }
        else if (consume(p, TokenType.QUESTION)!)
        {
            type.is_optional = true;
        }
        else 
        {
            break;
        }
    }

    return type;
}

fn TypeInfo*? parse_function_type(Parser* p, SourceSpan start_span)
{
    TypeInfo* ret = parse_type(p)!;

    expect(p, TokenType.LPAREN)!;
    
    List{TypeInfo*} params;
	params.tinit();
    bool variadic = false;

    if (!token_is(p, TokenType.RPAREN))
    {
        do 
		{
            if (consume(p, TokenType.ELLIPSIS)!) 
			{
                variadic = true;
                break; 
            }
            
            params.push(parse_type(p)!);
            
        } 
		while (consume(p, TokenType.COMMA)!);
    }

    expect(p, TokenType.RPAREN)!;

    SourceSpan full_span = start_span.combine(p.span);
    return make_type_info_func(ret, params, variadic, full_span);
}