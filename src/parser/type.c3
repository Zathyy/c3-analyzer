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

fn TypeInfo*? parser_ct_base_type(Parser* p, TypeInfoKind kind) @private
{
	TypeInfo* info = type_info_new(kind, p.span);
	defer (catch err)
	{
		allocator::free(tmem, info);
	}
	if (!consume(p, TokenType.LPAREN)!)
	{
		p.error("Expected %s got %s", TokenType.LPAREN, p.token);
		return make_invalid_type_info(p, info);
	}
	Expr* expr = parse_expr(p)!;
	if (!ast::expr_ok(expr))
	{
		p.error("Expected %s got %s", TokenType.LPAREN, p.token);
		return make_invalid_type_info(p, info);
	}
	if (!consume(p, TokenType.RPAREN)!)
	{
		p.error("Expected %s got %s", TokenType.RPAREN, p.token);
		return make_invalid_type_info(p, info);
	}
	info.span = info.span.combine(p.span);
	return info;
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

fn TypeInfo*? parse_base_type(Parser* p)
{
	if (consume(p, TokenType.CT_TYPEFROM)!)
	{
		return parser_ct_base_type(p, TypeInfoKind.TYPEFROM)!;
	}
	if (consume(p, TokenType.CT_TYPEOF)!)
	{
		return parser_ct_base_type(p, TypeInfoKind.TYPEOF)!;
	}
	if (consume(p, TokenType.CT_VATYPE)!)
	{
		return parser_ct_base_type(p, TypeInfoKind.VATYPE)!;
	}
	if (consume(p, TokenType.CT_EVALTYPE)!)
	{
		return parser_ct_base_type(p, TypeInfoKind.EVALTYPE)!;
	}
	SourceSpan span = p.span;
	CPath*? path = parse_path(p);
	if (try path && path)
	{
		TypeInfo* info = type_info_new(TypeInfoKind.IDENTIFIER, span);
		info.unresolved.path = path;
		info.unresolved.name = p.token.text;
		if (!consume_type_name(p, "type")!)
		{
			return make_invalid_type_info(p, info);
		}
		info.span = info.span.combine(p.span);
		return info;
	}

	TypeInfo* info = null;
	switch (p.token.type)
	{
		case TokenType.TYPE_IDENT:
			info = type_info_new(TypeInfoKind.IDENTIFIER, p.span);
			info.unresolved.name = p.token.text;
			break;
		case TokenType.CT_TYPE_IDENT:
			info = type_info_new(TypeInfoKind.CT_IDENTIFIER, p.span);
			info.unresolved.name = p.token.text;
			break;
		case TokenType.BOOL:
		case TokenType.CHAR:
		case TokenType.DOUBLE:
		case TokenType.FLOAT:
		case TokenType.FLOAT16:
		case TokenType.BFLOAT16:
		case TokenType.INT128:
		case TokenType.ICHAR:
		case TokenType.INT:
		case TokenType.IPTR:
		case TokenType.LONG:
		case TokenType.SHORT:
		case TokenType.UINT128:
		case TokenType.UINT:
		case TokenType.ULONG:
		case TokenType.UPTR:
		case TokenType.USHORT:
		case TokenType.USZ:
		case TokenType.ISZ:
		case TokenType.FLOAT128:
		case TokenType.TYPEID:
		case TokenType.FAULT:
		case TokenType.ANY:
		case TokenType.VOID:
			info = type_info_new(TypeInfoKind.IDENTIFIER, p.span);
			info.unresolved.name = p.token.text;
			//TODO: Type
			break;
		default:
			if (token_is(p, TokenType.IDENT))
			{
				if (peek(p) == TokenType.IDENT)
				{

				}
			}
			else
			{
				p.error("type name expected");
			}
			
			info = mem::tnew(TypeInfo);
			return make_invalid_type_info(p, info);
	}

	advance(p)!;
	info.span = info.span.combine(p.span);
	return info;
}