module c3_parser::parser;

import c3::lexer;
import c3_parser::ast;
import c3_parser::common;
import c3_parser::diagnostics;

import std::collections::list;
import std::io;

faultdef 
	UNKNOWN,
	CONTRACT_NOT_ALLOWED,
	UNEXPECTED_TOKEN,
	FOUND_MODULE,
;

alias DeclBuffer = List{ Decl* };

struct Parser
{
	Token[] tokens;
	String src;
	String comment;
	ModuleSection* section;
	FileID file;
	uint pos;
}

macro void Parser.info(self, String fmt, ...)
{    
	io::print(ansi::get_color_rgb(0, 200, 0));
	if (diagnostics::use_diagnostics)
	{
		diagnostics::report(INFO, self.span(), fmt, $vasplat);
	}
	$if $defined (env::DEBUG_SYMBOLS):
		log::info("at: %s %s:%s", $$FILE, $$FUNC, $$LINE);
	$endif
	io::print(ansi::get_color_rgb(200, 200, 200));
}

macro void Parser.warn(self, String fmt, ...)
{    
	if (diagnostics::use_diagnostics)
	{
		diagnostics::report(WARN, self.span(), fmt, $vasplat);
	}
	$if $defined (env::DEBUG_SYMBOLS):
		log::warn("at: %s %s:%s", $$FILE, $$FUNC, $$LINE);
	$endif
}

macro void Parser.error(self, String format, ...)
{   
	io::print(ansi::get_color_rgb(255, 0, 0));
	if (diagnostics::use_diagnostics)
	{
		diagnostics::report(ERROR, self.span(), format, $vasplat);
	}
	$if $defined (env::DEBUG_SYMBOLS):
		log::error("at: %s %s:%s", $$FILE, $$FUNC, $$LINE);
	$endif
	io::print(ansi::get_color_rgb(200, 200, 200));
}

macro void Parser.@take_comment(&self, #t)
{
	#t.comment = self.comment;
	self.comment = "";
}

<*
	synchronize the top level/recover top level
	@param [&inout] p
*>
fn void synchronize(Parser* p)
{
    if (catch advance(p)) return;

    while (!p.eof())
    {
        if (p.current().type == TokenType.EOS)
        {
            (void)advance(p);
            return;
        }

        // Keywords which are top-lever (Decl)
		// TODO: Add more cases!
        switch (p.current().type)
        {
            case TokenType.MODULE:
            case TokenType.IMPORT:
            case TokenType.ALIAS:
            case TokenType.TYPEDEF:
            case TokenType.FUNC:
            case TokenType.STRUCT:
            case TokenType.CONST:
            case TokenType.ENUM:
                return; // The next loop iteration will handle these
            default:
                (void)advance(p);
                break;
        }
    }
}

fn bool Parser.eof(&self) @inline
{
	return self.pos >= self.tokens.len || self.is(TokenType.EOF);
}

<*
	@param pos : "absolute position into tokens, 0 if use current"
*>
fn SourceSpan Parser.span(&self, uint pos = 0)
{
	Token token = pos > 0 ? self.tokens[pos] : self.tokens[self.pos];

	return (SourceSpan){
		.file_id = self.file,
		.start = token.offset,
		.end = token.offset + token.len - 1
	};
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

fn bool Parser.is(&self, TokenType type) 
{
	return self.tokens[self.pos].type == type;
}

fn Token Parser.current(&self) @inline
{
	return self.peek(0);
}

fn Token Parser.peek(&self, uint pos = 1) @inline
{
	return self.tokens[self.pos + pos];
}

<*
	@param [&inout] parser
*>
fn void? advance(Parser* parser)
{
	if (parser.eof())
	{
		log::debug("parser::advance() : eof");
		return io::EOF~;
	}
	parser.pos++;
}

<*
	@param [&inout] parser
*>
fn void? expect(Parser* parser, TokenType type) @inline
{
	if (!parser.is(type))
	{
		parser.error("Expected '%s' got '%s'", type, parser.current().type);
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
	if (parser.is(type))
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
	if (!parser.is(TokenType.IDENT) || parser.peek().type != TokenType.SCOPE)
	{
		return null;
	}

	SourceSpan start = parser.span();
    SourceSpan end = parser.span();

	CPath* path = mem::tnew(CPath);
	defer (catch err)
	{
		allocator::free(tmem, path);
	}

    while (true) 
    {
		String string = parser.current().text;
        expect(parser, TokenType.IDENT)!;

		path.name = path.name.concat(tmem, string);

        if (!consume(parser, TokenType.SCOPE)!) 
		{
        	end = parser.span();
			break;
		}

		path.name = path.name.concat(tmem, "::");
    }

    path.span = start.combine(end);
	return path;
}

<*
	parse comments
*>
fn void parse_docs(Parser* parser)
{
	if (!parser.is(TokenType.LINE_COMMENT) || !parser.is(TokenType.BLOCK_COMMENT))
	{
		return;
	}

	Token token = parser.current();
	parser.comment = token.text;
	(void)advance(parser);

	while (token.type == TokenType.LINE_COMMENT)
	{
		token = parser.current();
		parser.comment.tconcat(parser.current().text);
		if (catch advance(parser)) return;
	}
}

<*
	@param [&inout] parser
	@require parser.section != null
*>
fn void? parse(Parser* parser)
{
	while (!parser.eof())
	{
		if (parser.is(TokenType.MODULE)) 
		{
			return FOUND_MODULE~;
		};

		if (catch err = parse_top_level_statement(parser, &parser.section.ast.decls))
		{	
			log::debug("Failed parse_top_leverl: %s. Adding as invalid...", err);
			
			Decl* inv_decl = mem::tnew(Decl);
			make_invalid_decl(parser, inv_decl);
			parser.section.ast.decls.push(inv_decl);

			synchronize(parser);
			continue;
		}
	}
}

fn void? parse_top_level_statement(Parser* p, List{Decl*}* out)
{
    log::debug("parse_top_level_statement: %s", p.current());

    // Metadata / Documentation
    parse_docs(p);

    TokenType type = p.current().type;

    // Handle specific keywords
    switch (type)
    {
        case TokenType.EOS:
            p.error("<EOS> appeared in parse_top_level");
            advance(p)!;
            return;

        case TokenType.FUNC:
            return parse_function(p, out)!;

        case TokenType.IMPORT: 
            return parse_import(p, out)!;

        case TokenType.ALIAS:
            return parse_alias(p, out)!;

        case TokenType.TYPEDEF:
            return parse_typedef(p, out)!;

        case TokenType.STRUCT:
        case TokenType.UNION:
        case TokenType.BITSTRUCT:
            return parse_struct(p, out)!; // Passing the list we got!

        default:
            // Fallback: Is it a global variable or something else?
            if (is_type_start(type) || type == TokenType.IDENT)
            {
                return parse_global(p, out)!;
            }
            break;
    }

    log::error("Couldn't find any matching top level declaration: %s", p.current());
    return UNEXPECTED_TOKEN~;
}