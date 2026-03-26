module c3_parser::parser;

import lexer;
import string_pool;
import line_map;

import c3_parser::ast;
import c3_parser::common;

import std::io;
import std::collections::list;
import std::collections::maybe;

faultdef
	UNKNOWN,
	UNEXPECTED_EOS,
	CONTRACT_NOT_ALLOWED,
	INVALID_PATH,
	UNEXPECTED_TOKEN,
;

struct Parser
{
	StringPool strings;
	LineMap line_map;
	Token[] tokens;
	String src;
	Ast* ast;
	uint pos;
}

fn void init(Parser* p)
{
	p.strings.init();
	p.line_map.init();

	p.ast = mem::tnew(Ast);
	ast::init(p.ast, 1000);
}

fn void free(Parser* p)
{
	p.strings.free();
	p.line_map.free();
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
        if (p.current().kind == TokenKind.EOS)
        {
            (void)advance(p);
            return;
        }

        // Keywords which are top-lever (Decl)
		// TODO: Add more cases!
        switch (p.current().kind)
        {
            case TokenKind.MODULE:
            case TokenKind.IMPORT:
            case TokenKind.ALIAS:
            case TokenKind.TYPEDEF:
            case TokenKind.FN:
            case TokenKind.STRUCT:
            case TokenKind.CONST:
            case TokenKind.ENUM:
                return; // The next loop iteration will handle these
            default:
                (void)advance(p);
                break;
        }
    }
}

fn bool Parser.eof(&self) @inline
{
	return self.pos >= self.tokens.len || self.is(TokenKind.EOF);
}

fn bool Parser.is(&self, TokenKind kind) 
{
	return self.tokens[self.pos].kind == kind;
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
fn void? expect(Parser* parser, TokenKind kind) @inline
{
	if (!parser.is(kind))
	{
		parser.error("Expected '%s' got '%s'", kind.nameof, parser.current().kind.nameof);
		return UNEXPECTED_TOKEN~;
	}

	advance(parser)!;
}

<*
	@param [&inout] parser
	@param kind : "type to consume"
*>
fn bool? consume(Parser* parser, TokenKind kind)
{
	if (parser.is(kind))
	{
		advance(parser)!;
		return true;
	}

	return false;
}

fn String Parser.token_text(Parser* self, Token t) @inline
{
    return self.src[t.pos:t.len];
}

fn Node? parse_path(Parser* p)
{
    if (!p.is(TokenKind.IDENT))
	{
		return INVALID_PATH~;
	}

    uint start_tok = p.pos;
    List{uint} parts;
    parts.tinit(4);
    defer parts.free();

    while (true) 
    {
        Token t = p.current();
        uint sh = p.strings.intern(p.token_text(t));
        parts.push(sh);
        
        expect(p, TokenKind.IDENT)!;
        if (!consume(p, TokenKind.SCOPE)!) break;
    }

    uint ex = ast::reserve_extra(p.ast, 1 + (uint)parts.len());
    p.ast.extra_data[ex] = (uint)parts.len();
    for (uint i = 0; i < parts.len(); i++) 
	{
        p.ast.extra_data[(usz)ex + 1 + i] = parts[i];
    }

    return ast::add_node(p.ast, NodeKind.PATH, start_tok, ex);
}

fn Node? parse_ident(Parser* p)
{
	Token t = p.current();
	expect(p, TokenKind.IDENT)!;

	String name_str = p.token_text(t);
	uint name_id = p.strings.intern(name_str);

	return ast::add_node(p.ast, NodeKind.IDENT_EXPR, (uint)p.pos - 1, name_id);
}

<*
	@param [&inout] parser
*>
fn void? parse(Parser* parser, String path)
{
	String src = (String)file::load(tmem, path)!;
	Lexer lexer = (Lexer){
		.buffer = src,
		.index = 0,
	};

	parser.src = src;

	log::info("parsing file: %s", path);

	List{ Token } tokens;
	tokens.tinit(1000);
	defer tokens.free();
	while (try token = lexer.next())
	{
		tokens.push(token);
		io::printfn("Added token: <%s> - %s", token.kind, parser.token_text(token));
	}

	parser.tokens = tokens.array_view();
	parser.line_map.build(src);
	parser.pos = 0;

	while (!parser.eof())
	{
		if (catch err = parse_top_level(parser))
		{			
			synchronize(parser);
			continue;
		}
	}
}

fn void? parse_top_level(Parser* p)
{
    log::debug("parse_top_level: %s", p.token_text(p.current()));

    TokenKind kind = p.current().kind;
	Maybe{ Node } node;

    switch (kind)
    {
        case TokenKind.EOS:
            p.error("<EOS> appeared in parse_top_level");
            advance(p)!;
            return UNEXPECTED_EOS~;

		case TokenKind.MODULE:
			node.set(parse_module(p)!);
			break;
		case TokenKind.IMPORT:
			node.set(parse_import(p)!);
			break;
        default:
			p.error("Couldn't find any matching top level declaration: %s", p.current());
    		return UNEXPECTED_TOKEN~;
    }

	if (try value = node.get())
	{
		p.ast.top_level_nodes.push((uint)value);
	}
}