module c3_parser::parser;
import c3_parser::ast;
import lexer;

import c3_parser::common;
import c3_parser::registry;
import std::collections::list;

fn Node? parse_module(Parser* p)
{
	uint start = p.pos;
    expect(p, TokenKind.MODULE)!;

    Node? path_node = parse_path(p);
	if (catch err = path_node)
	{
		p.error("failed to parse path for module: %s", err);
		return err~;
	} 
    expect(p, TokenKind.EOS)!;

	uint[1] block = { (uint)path_node };
	uint ex = ast::push_extra_block(p.ast, &block);
    return ast::add_node(p.ast, NodeKind.MODULE_DECL, start, ex);
}

fn Node? parse_import(Parser* p)
{
	uint start = p.pos;
	expect(p, TokenKind.IMPORT)!;

   	Node? path_node = parse_path(p);
	if (catch err = path_node)
	{
		p.error("failed to parse path for module: %s", err);
		return err~;
	} 
   	expect(p, TokenKind.EOS)!;

	uint[1] block = { (uint)path_node };
	uint ex = ast::push_extra_block(p.ast, &block);
    return ast::add_node(p.ast, NodeKind.IMPORT_DECL, start, ex);
}

fn Node? parse_fn_decl(Parser* p)
{
    uint start_tok = p.pos;

    expect(p, TokenKind.FN)!;

    Node ret_type = parse_type(p)!;

    if (!p.is(TokenKind.IDENT))
	{
		p.error("Expected function name");
		return UNEXPECTED_TOKEN~;
	}
    uint name_sh = p.strings.intern(p.token_text(p.current()));
    advance(p)!; 

    expect(p, TokenKind.LPAREN)!;
    uint[32] param_stack;
    uint param_count = 0;

    if (!p.is(TokenKind.RPAREN))
    {
        while (true)
        {
            param_stack[param_count++] = (uint)parse_param_decl(p)!;
            if (!consume(p, TokenKind.COMMA)!) break;
        }
    }
    expect(p, TokenKind.RPAREN)!;

    Node body = 0;
    if (p.is(TokenKind.LBRACE)) 
	{
        body = parse_compound(p)!;
    } 
	else 
	{
        expect(p, TokenKind.EOS)!;
    }

    // Name, RetType, Count, Body, Params...
    uint total_slots = 4 + param_count;
    uint[36] final_block;
    
    final_block[0] = name_sh;
    final_block[1] = (uint)ret_type;
    final_block[2] = param_count;
    final_block[3] = (uint)body;

    for (uint i = 0; i < param_count; i++) 
	{
        final_block[4 + i] = param_stack[i];
    }

    uint ex = ast::push_extra_block(p.ast, &final_block);
    return ast::add_node(p.ast, NodeKind.FN_DECL, start_tok, ex);
}

fn Node? parse_param_decl(Parser* p)
{
    uint start_tok = p.pos;
    
    Node type = parse_type(p)!;
    
    if (!p.is(TokenKind.IDENT))
	{
		p.error("Expected parameter name");
		return UNEXPECTED_TOKEN~;
	}

    uint name_sh = p.strings.intern(p.token_text(p.current()));
    advance(p)!;

    uint[2] data = { (uint)type, name_sh };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.PARAM_DECL, start_tok, ex);
}

fn Node? parse_type(Parser* p)
{
    uint start_tok = p.pos;
	TypeKey key;

    key.name = (Node)p.strings.intern(p.token_text(p.current()));
	advance(p)!;

	if (consume(p, TokenKind.LBRACE)!) 
    {
        while (!p.is(TokenKind.RBRACE)) 
        {
            key.gen_args[key.gen_count++] = parse_type(p)!;
            
            if (key.gen_count >= common::MAX_GENERICS) 
			{
				p.error("Too many generics");
				return TOO_MANY_GENERICS~;
			}
            if (!consume(p, TokenKind.COMMA)!) break;
        }
        expect(p, TokenKind.RBRACE)!;
    }

	while (true)
	{
        if (consume(p, TokenKind.ASTERISK)!) 
		{
            key.ptr_count++;
            continue;
        }
        if (consume(p, TokenKind.LBRACKET)!) 
		{
            key.array_size = parse_expression(p)!; 
            expect(p, TokenKind.RBRACKET)!;
            continue;
        }
        break;
    }

	Node existing = p.registry.get_interned_type(&key);
    if (existing.is_valid()) return existing;

    // [Base, Ptrs, ArraySize, GenCount, ...GenArgs]
    uint total_slots = 4 + key.gen_count;
    uint[common::MAX_GENERICS + 4] final_block;
    
    final_block[0] = (uint)key.name;
    final_block[1] = key.ptr_count;
    final_block[2] = (uint)key.array_size;
    final_block[3] = key.gen_count;

    for (uint i = 0; i < key.gen_count; i++) 
	{
        final_block[4 + i] = (uint)key.gen_args[i];
    }

    uint ex = ast::push_extra_block(p.ast, &final_block);
    Node new_node = ast::add_node(p.ast, NodeKind.TYPE, start_tok, ex);

	p.registry.register_type_shape(&key, new_node);

	return new_node;
}