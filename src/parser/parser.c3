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

fn bool is_keyword_ident(TokenType type) 
{
	return type >= TokenType.ALIAS
		&& type <= TokenType.WHILE;
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
			return false;
	}
}

<*
	@param [&in] parser
*>
fn bool token_is(Parser* parser, TokenType type) @inline 
{
	return parser.token.type == type;
}

fn TokenType peek(Parser* p) @inline
{
	return p.next.type;
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

	parser.token = parser.next;

	parser.span.start = parser.token.offset;
	parser.span.end =  parser.token.offset + parser.token.len - 1;

	if (!token_is(parser, TokenType.EOF))
	{
		parser.next = parser.lexer.next()!;
	}
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
	@return? expect!, consume!
*>
fn CPath*? parse_path(Parser* parser)
{
	if (!token_is(parser, TokenType.IDENT) || peek(parser) != TokenType.SCOPE)
	{
		return null;
	}

	SourceSpan start = parser.span;
    SourceSpan end = parser.span;

	CPath* path = mem::tnew(CPath);
	defer (catch err)
	{
		mem::free(path);
	}

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
