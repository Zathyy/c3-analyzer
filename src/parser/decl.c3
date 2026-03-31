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

<*
	TYPE_EXPR - unresolved type, parser only cares about the syntax
*>
fn Node? parse_type(Parser* p)
{
    uint start_tok = p.pos;
	TypeDescriptor desc;
	TypeFlags flags;

    desc.name = p.strings.intern(p.token_text(p.current()));
	advance(p)!;

	if (consume(p, TokenKind.LBRACE)!) 
    {
        while (!p.is(TokenKind.RBRACE)) 
        {
            desc.gen_args[desc.gen_count++] = parse_type(p)!;
            
            if (desc.gen_count >= common::MAX_GENERICS) 
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
		if (consume(p, TokenKind.LVEC)!)
		{
			flags.is_vector = true;
			desc.array_size = parse_expr(p)!;
			expect(p, TokenKind.RVEC)!;
			break;
		}
        if (consume(p, TokenKind.ASTERISK)!) 
		{
            desc.ptr_count++;
            continue;
        }
        if (consume(p, TokenKind.LBRACKET)!) 
		{
            desc.array_size = parse_expr(p)!; 
            expect(p, TokenKind.RBRACKET)!;
            continue;
        }
        break;
    }

    uint[common::MAX_GENERICS + 5] final_block;
    
    final_block[0] = (uint)desc.name;
    final_block[1] = (uint)desc.ptr_count;
    final_block[2] = (uint)desc.array_size;
    final_block[3] = (uint)desc.gen_count;
    final_block[4] = (uint)flags;

    for (uint i = 0; i < desc.gen_count; i++) 
	{
        final_block[5 + i] = (uint)desc.gen_args[i];
    }

    uint ex = ast::push_extra_block(p.ast, &final_block);
    Node new_node = ast::add_node(p.ast, NodeKind.TYPE_EXPR, start_tok, ex);

	return new_node;
}

fn Node? parse_alias(Parser* p)
{
    uint start_tok = p.pos;
    expect(p, TokenKind.ALIAS)!;

	Token name_tok = p.current();
    expect(p, TokenKind.TYPE_IDENT)!;
    uint name_sh = p.strings.intern(p.token_text(name_tok));

    expect(p, TokenKind.EQ)!;

    Node target_type = parse_type(p)!;

    expect(p, TokenKind.EOS)!;

    uint[2] data = { name_sh, (uint)target_type };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.ALIAS_DECL, start_tok, ex);
}

fn Node? parse_typedef(Parser* p)
{
	uint start_tok = p.pos;
    expect(p, TokenKind.TYPEDEF)!;

	Token name_tok = p.current();
    expect(p, TokenKind.TYPE_IDENT)!;
    uint name_sh = p.strings.intern(p.token_text(name_tok));

    expect(p, TokenKind.EQ)!;

    Node base_type = parse_type(p)!;

    expect(p, TokenKind.EOS)!;

    uint[2] data = { name_sh, (uint)base_type };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.TYPEDEF_DECL, start_tok, ex);
}

fn Node? parse_global(Parser* p)
{
    uint start_tok = p.pos;
    GlobalFlags flags;

    if (consume(p, TokenKind.CONST)!)  flags.is_const = true;
	if (consume(p, TokenKind.TLOCAL)!) flags.is_thread_local = true;
    if (consume(p, TokenKind.EXTERN)!) flags.is_extern = true;

    Node type_node = parse_type(p)!;

    Token name_tok = p.current();
 	expect(p, TokenKind.IDENT)!;
    uint name_sh = p.strings.intern(p.token_text(name_tok));

    Node init_expr;
    if (consume(p, TokenKind.EQ)!)
    {
        init_expr = parse_expr(p, 0)!;
    }
    
    expect(p, TokenKind.EOS)!;

    log::debug("parse_global: %s", p.token_text(p.current()));


    uint[4] data = { (uint)flags, name_sh, (uint)type_node, (uint)init_expr };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.GLOBAL_DECL, start_tok, ex);
}