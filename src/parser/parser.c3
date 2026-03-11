module c3_parser::parser;

import c3::lexer;
import c3_parser::ast;
import c3_parser::mod;
import c3_parser::common;
import c3_parser::diagnostics;

import std::collections::list;
import std::io;

faultdef 
	CONTRACT_NOT_ALLOWED,
	UNEXPECTED_TOKEN,
	FOUND_MODULE,
;

//TODO?: store Token[] instead of lexer?
struct Parser
{
	Lexer lexer;
	Token token;
	Token next;
	String src;
	ModuleSection* section;
	SourceSpan span;
}

macro void Parser.info(self, String fmt, ...)
{    
	if (diagnostics::use_diagnostics)
	{
		diagnostics::report(INFO, self.span, format, $vasplat);
	}
	$if $defined (env::DEBUG_SYMBOLS):
		log::info("at: %s %s:%s", $$FILE, $$FUNC, $$LINE);
	$endif
}

macro void Parser.warn(self, String fmt, ...)
{    
	if (diagnostics::use_diagnostics)
	{
		diagnostics::report(WARN, self.span, fmt, $vasplat);
	}
	$if $defined (env::DEBUG_SYMBOLS):
		log::warn("at: %s %s:%s", $$FILE, $$FUNC, $$LINE);
	$endif
}

macro void Parser.error(self, String format, ...)
{   
	if (diagnostics::use_diagnostics)
	{
		diagnostics::report(ERROR, self.span, format, $vasplat);
	}
	$if $defined (env::DEBUG_SYMBOLS):
		log::error("at: %s %s:%s", $$FILE, $$FUNC, $$LINE);
	$endif
}

fn bool Parser.eof(&self) @inline
{
	return token_is(self, TokenType.EOF);
}

//TODO: better way?
fn bool is_keyword_ident(TokenType type) 
{
	switch (type) 
	{
		case ALIAS:
		case ASM:
		case ASSERT:
		case ATTRDEF:
		case BITSTRUCT:
		case CONST:
		case CONSTDEF:
		case ENUM:
		case FAULTDEF:
		case FUNC:
		case IMPORT:
		case INTERFACE:
		case MACRO:
		case MODULE:
		case STRUCT:
		case UNION:
		case TYPEDEF:
		case BREAK:
		case CASE:
		case CATCH:
		case CONTINUE:
		case DEFAULT:
		case DEFER:
		case DO:
		case ELSE:
		case EXTERN:
		case FALSE:
		case FOR:
		case FOREACH:
		case FOREACH_R:
		case IF:
		case INLINE:
		case LENGTHOF:
		case NEXTCASE:
		case NULL:
		case RETURN:
		case STATIC:
		case SWITCH:
		case TLOCAL:
		case TRUE:
		case TRY:
		case VAR:
		case WHILE:
			return true;
		default:
			break;
	}

	return false;
}

fn bool is_some_ident(TokenType type) 
{
	switch (type)
	{
		case TYPE_IDENT:
		case IDENT:
		case CONST_IDENT:
			return true;
		default:
			break;
	}

	return false;
}

<*
	@param [&inout] parser
*>
fn bool token_is(Parser* parser, TokenType type) @inline 
{
	return parser.token.type == type;
}

<*
	@param [&inout] parser
*>
fn void? advance(Parser* parser)
{
	if (parser.eof())
	{
		return io::EOF~;
	}

	parser.token = parser.lexer.next()!;
	parser.span.start = parser.token.offset;
	parser.span.end =  parser.token.offset + parser.token.len - 1;
}

<*
	@param [&inout] parser
*>
fn void? expect(Parser* parser, TokenType type) @inline
{
	if (!token_is(parser, type))
	{
		parser.error("Expected '%s' got '%s'", type, parser.token.type);
		return UNEXPECTED_TOKEN~;
	}

	advance(parser)!;
}

<*
	@param [&inout] parser
	@param type : "type to consume"
*>
fn bool? consume(Parser* parser, TokenType type)
{
	if (token_is(parser, type))
	{
		advance(parser)!;
		return true;
	}

	return false;
}

<*
	@param [&inout] parser
*>
fn CPath? parse_path(Parser* parser)
{
	SourceSpan start = parser.span;
    SourceSpan end = parser.span;

	CPath path;

    while (true) 
    {
		String string = parser.token.text;
        expect(parser, TokenType.IDENT)!;

		path.name = path.name.concat(tmem, string);

        if (!consume(parser, TokenType.SCOPE)!) 
		{
        	end = parser.span;
			break;
		}

		path.name = path.name.concat(tmem, "::");
    }

    path.span = start.combine(end);
	return path;
}

<*
	@param [&inout] parser
	@require parser.section != null
*>
fn void? parse(Parser* parser)
{
	while (!parser.eof())
	{
		if (token_is(parser, TokenType.MODULE)) 
		{
			return FOUND_MODULE~;
		};

		if (catch parse_top_level_statement(parser))
		{
			advance(parser)!;
			continue;
		}
	}
}

<*
	@param [&inout] parser
*>
fn void? parse_top_level_statement(Parser* parser)
{
	//TODO: refine this loop and add more cases.

	TokenType type = parser.token.type;
	bool attach_contracts = false;
	log::debug("parse_top_level_statement: %s", parser.token);

	switch (type)
	{
	case TokenType.FUNC:
		return parse_function(parser)!;
	case TokenType.IMPORT: 
		return parse_import(parser)!;
	default:
		break;
	}

	return UNEXPECTED_TOKEN~;
}
