module c3_parser::parser;

import lexer;
import string_pool;
import line_map;

import c3_parser::ast;
import c3_parser::common;
import c3_parser::registry;
import c3_parser::workspace @norecurse;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::maybe;

faultdef
	UNKNOWN,
	UNEXPECTED_EOS,
	MODULE_HEADER_FAILED,
	CONTRACT_NOT_ALLOWED,
	INVALID_PATH,
	PATH_TOO_LONG,
	TOO_MANY_GENERICS,
	EXPECTED_EXPRESSION,
	UNEXPECTED_TOKEN,
;

// length in parts, eg: foo::bar = 2 parts
const uint PATH_MAX_LENGTH = 16;

struct Parser
{
	LineMap line_map;
	StringPool* pool;
	Ast* ast;
	Module* mod;
	Token[] tokens;
	String file_path; // current file being parsed
	String src;
	uint pos;
}

<*
	synchronize the top level/recover top level
	@param [&inout] p
*>
fn void synchronize(Parser* p)
{
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
			case TokenKind.CONTRACT:
            case TokenKind.MODULE:
            case TokenKind.IMPORT:
            case TokenKind.ALIAS:
            case TokenKind.TYPEDEF:
            case TokenKind.FN:
			case TokenKind.MACRO:
            case TokenKind.STRUCT:
            case TokenKind.CONST:
            case TokenKind.ENUM:
			case TokenKind.EXTERN:
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

fn void Parser.print_current(&self)
{
	log::debug("%s", self.token_text(self.current()));
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
	if (parser.eof()) return io::EOF~;
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

fn String Parser.current_text(Parser* self) @inline
{
	return self.token_text(self.current());
}

fn Node? parse_path(Parser* p)
{
    if (!p.is(TokenKind.IDENT) && p.peek().kind != TokenKind.SCOPE)
	{
		log::debug("not a valid path");
		return INVALID_PATH~;
	}

    uint start_tok = p.pos;
    uint[PATH_MAX_LENGTH] stack_parts; 
    uint count = 0;

    while (true) 
    {
        Token t = p.current();
        uint sh = p.pool.intern(p.token_text(t));
        if (count < PATH_MAX_LENGTH) 
		{
            stack_parts[count++] = sh;
        } 
		else 
		{
            p.error("Path too long (max %s segments)", PATH_MAX_LENGTH);
            return PATH_TOO_LONG~;
        }
        
        expect(p, TokenKind.IDENT)!;
        if (!consume(p, TokenKind.SCOPE)!) break;
    }

    uint[PATH_MAX_LENGTH + 1] final_block;
    final_block[0] = count;
    
    // Copy the parts into the block
    for (uint i = 0; i < count; i++) 
	{
        final_block[i + 1] = stack_parts[i];
    }
    uint ex = ast::push_extra_block(p.ast, &final_block);
    return ast::add_node(p.ast, NodeKind.PATH, start_tok, ex);
}

fn Node? parse_ident(Parser* p)
{
	Token t = p.current();
	expect(p, TokenKind.IDENT)!;

	String name_str = p.token_text(t);
	uint name_id = p.pool.intern(name_str);

	return ast::add_node(p.ast, NodeKind.IDENT_EXPR, (uint)p.pos - 1, name_id);
}

fn String peek_module_name(Parser* p)
{
    for (usz i = 0; i < p.tokens.len; i++)
    {
        if (p.tokens[i].kind == TokenKind.MODULE)
        {
            // Start collecting the name after the 'module' keyword
            usz j = i + 1;
            String full_name = "";

            while (j < p.tokens.len)
            {
                Token t = p.tokens[j];
                
                if (t.kind == TokenKind.IDENT) 
				{
                    String part = p.token_text(t); 
                    full_name = full_name.tconcat(part);
                } 
                else if (t.kind == TokenKind.SCOPE) 
				{
                    full_name = full_name.tconcat("::");
                } 
                else if (t.kind == TokenKind.EOS) 
				{
                    break; // End of module declaration
                }
                
                j++;
            }
            return full_name;
        }
    }

    return "";
}

<*
	Parse a specific file.
	Appends the nodes to the provided Modules Ast
*>
fn void? parse_file(Workspace* ws, String path)
{
	Parser parser = (Parser){
		.mod = null,
		.pool = &ws.strings,
		.file_path = path,
	};

	String src = (String)file::load(tmem, path)!;
	Lexer lexer = (Lexer){
		.buffer = src,
		.index = 0,
	};

	parser.src = src;

	List{ Token } tokens;
	tokens.tinit(1000);
	defer tokens.free();
	while (try token = lexer.next())
	{
		tokens.push(token);
		log::debug("Added token: <%s> - %s", token.kind, parser.token_text(token));
	}
	parser.tokens = tokens.array_view();
	parser.line_map.build(src);

	String mod_name = peek_module_name(&parser);
    
    if (mod_name == "") 
	{
        mod_name = path_to_module_name(path)!;
        log::debug("Inferred module: %s", mod_name);
    }
	Module* mod = workspace::get_or_create_module(ws, mod_name);
	parser.mod = mod;
	parser.ast = &mod.ast;

	log::debug("parsing file: %s", path);

	ModuleSection* section = workspace::get_or_create_section(mod, path);
	assert(section != null);

	while (!parser.eof())
	{
		uint start_idx = (uint)mod.ast.len();

		if (catch err = parse_top_level(&parser, ws))
		{			
			synchronize(&parser);
			continue;
		}

		uint end_idx = (uint)mod.ast.len();
		if (end_idx > start_idx) 
		{
			Node latest_node = (Node)mod.ast.kinds[start_idx];

			if (!section.header_node.is_valid())
			{
				section.header_node = latest_node;
			}
			section.node_count += (end_idx - start_idx);
		}
	}
}

fn String? path_to_module_name(String path)
{
    String base_name = path.file_tbasename()!;
	return base_name.strip_end(".c3");
}

fn void? parse_top_level(Parser* p, Workspace* ws)
{
    log::debug("parse_top_level: %s", p.token_text(p.current()));

    TokenKind kind = p.current().kind;
	Node node;

	if (is_type(kind) || kind == TokenKind.TLOCAL)
	{
		node = parse_global(p)!;
		if (node.is_valid())
		{
			p.ast.top_level_nodes.push((uint)node);
			return;
		}
	}

    switch (kind)
    {
        case TokenKind.EOS:
            p.error("<EOS> appeared in parse_top_level");
            advance(p)!;
            return UNEXPECTED_EOS~;
		case TokenKind.CONTRACT:
			node = parse_contract(p)!;
			break;
		case TokenKind.EXTERN:
		{
			advance(p)!;
			switch (p.current().kind)
			{
				case TokenKind.CONST:
					node = parse_const_decl(p, true)!;
					break;
				case TokenKind.FN:
					node = parse_fn_decl(p, true)!;
					break;
				default:
					p.error("Unexpected token after extern");
					return UNEXPECTED_TOKEN~;
			}
			break;
		}
		case TokenKind.MODULE:
			node = parse_module(p, ws)!;
			break;
		case TokenKind.IMPORT:
			node = parse_import(p)!;
			break;
		case TokenKind.FN:
			node = parse_fn_decl(p)!;
			break;
		case TokenKind.MACRO:
			node = parse_macro_decl(p)!;
			break;
		case TokenKind.ALIAS:
			node = parse_alias(p)!;
			break;
		case TokenKind.TYPEDEF:
			node = parse_typedef(p)!;
			break;
		case TokenKind.STRUCT:
			node = parse_struct(p)!;
			break;
		case TokenKind.CONST:
			node = parse_const_decl(p)!;
			break;
        default:
			p.error("Couldn't find any matching top level declaration: %s", p.current());
    		return UNEXPECTED_TOKEN~;
    }

	if (node.is_valid())
	{
		p.ast.top_level_nodes.push((uint)node);
	}
}