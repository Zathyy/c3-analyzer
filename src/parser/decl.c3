module c3_parser::parser;
import c3_parser::ast;
import lexer;

import c3_parser::common;
import c3_parser::registry;
import std::collections::list;
import c3_parser::workspace @norecurse;

// just skip contracts for now
// TODO:
fn Node? parse_contract(Parser* p)
{
	uint start = p.pos;
    expect(p, TokenKind.CONTRACT)!;

	return (Node){};
}

fn Node? parse_module(Parser* p, Workspace* ws)
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

	PathView view = { p.ast, path_node };

	uint[1] block = { (uint)path_node };
	uint ex = ast::push_extra_block(p.ast, &block);
	log::info("parsed module!");
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

fn Node? parse_attributes(Parser* p)
{
    Node head = 0; // Initialize to 0!

    while (true)
    {
        TokenKind k = p.current().kind;
        if (k != TokenKind.AT_IDENT && 
            k != TokenKind.AT_TYPE_IDENT && 
            k != TokenKind.AT_CONST_IDENT) 
        {
            break;
        }

        String attr_name = p.token_text(p.current());
        
        AttributeKind kind = common::get_attribute_from_string(attr_name);
        
        uint start_tok = p.pos;
        advance(p)!;

        Node expr_data = 0;
        if (consume(p, TokenKind.LPAREN)!)
        {
            @try(expr_data, parse_expr(p));
            expect(p, TokenKind.RPAREN)!;
        }

        uint[3] attr_block = { (uint)kind, (uint)expr_data, (uint)head };
        uint ex = ast::push_extra_block(p.ast, &attr_block);
        
        head = ast::add_node(p.ast, NodeKind.ATTRIBUTE, start_tok, ex);
    }

    return head;
}

fn Node? parse_fn_decl(Parser* p, bool is_extern = false)
{
    uint start_tok = p.pos;

    expect(p, TokenKind.FN)!;

    Node ret_type = parse_type(p)!;

	uint name; // name of fn
	uint method_type; // if a method, the struct it belongs to, dont know what else to call it? class maybe? xD
	if (p.peek(1).kind == TokenKind.DOT)
	{
		if (!is_type(p.current().kind))
		{
			p.error("Expected method Type name");
			return UNEXPECTED_TOKEN~;
		}
    	method_type = p.pool.intern(p.token_text(p.current()));
        advance(p)!;
		expect(p, TokenKind.DOT)!;
		if (!p.is(TokenKind.IDENT))
		{
			p.error("Expected member fn name");
			return UNEXPECTED_TOKEN~;
		}
		name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
	}
	else
	{
		if (!p.is(TokenKind.IDENT))
		{
			p.error("Expected fn name");
			return UNEXPECTED_TOKEN~;
		}

		name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
	}

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

    Node attr = parse_attributes(p)!;

    Node body;
    if (p.is(TokenKind.LBRACE)) 
    {
        body = parse_compound(p)!;
    } 
    else if (consume(p, TokenKind.IMPLIES)!) // Handle the => syntax
    {
        body = parse_expr(p)!;
        expect(p, TokenKind.EOS)!;
    }
    else 
    {
        expect(p, TokenKind.EOS)!; // Prototype
    }
    
    uint[40] final_block;
    final_block[0] = name;
    final_block[1] = method_type;
    final_block[2] = (uint)ret_type;
    final_block[3] = (uint)attr;
    final_block[4] = param_count;
    final_block[5] = (uint)body;
    for (uint i = 0; i < param_count; i++) 
	{
        final_block[6 + i] = param_stack[i];
    }

    uint ex = ast::push_extra_block(p.ast, &final_block);
    return ast::add_node(p.ast, NodeKind.FN_DECL, start_tok, ex);
}

fn Node? parse_macro_decl(Parser* p)
{
    uint start_tok = p.pos;
    expect(p, TokenKind.MACRO)!;

    Node type;
    if (is_type(p.current().kind) && 
        p.peek(1).kind != TokenKind.DOT && 
        p.peek(1).kind != TokenKind.LPAREN)
    {
        type = parse_type(p)!;
    }

	uint name; // name of fn
	uint macro_method_type; // if a method, the struct it belongs to, dont know what else to call it? class maybe? xD

	if (p.peek(1).kind == TokenKind.DOT)
	{
		macro_method_type = (uint)parse_type(p)!;
        expect(p, TokenKind.DOT)!;
        name = p.pool.intern(p.token_text(p.current()));
        advance(p)!;
	}
	else
	{
		if (!p.is(TokenKind.IDENT) && !p.is(TokenKind.AT_IDENT))
		{
			p.error("Expected macro name");
            log::error("Got %s", p.current_text());
			return UNEXPECTED_TOKEN~;
		}

		name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
	}

    uint param_count = 0;
    Node params_start;
    if (p.is(TokenKind.LPAREN))
    {
        params_start = parse_parameter_list(p, &param_count)!;
    }

    Node attr = parse_attributes(p)!;

    Node body;
    if (p.is(TokenKind.IMPLIES)) 
    {
        advance(p)!;
		body = parse_expr(p)!;
        expect(p, TokenKind.EOS)!;
    } 
    else if (p.is(TokenKind.LBRACE)) 
    {
        body = parse_statement(p)!;
    }

    uint[7] data = {
        name,
        macro_method_type, 
        (uint)type, 
        (uint)attr,
        (uint)params_start, 
        param_count, 
        (uint)body 
    };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.MACRO_DECL, start_tok, ex);
}

fn Node? parse_parameter_list(Parser* p, uint* out_count)
{
    expect(p, TokenKind.LPAREN)!;
    
    *out_count = 0;
    Node first_param = (Node)0;

    while (!p.is(TokenKind.RPAREN) && !p.eof())
    {
        Node param = parse_param_decl(p)!;
        
        if (*out_count == 0) first_param = param;
        (*out_count)++;

        if (p.is(TokenKind.COMMA))
        {
            advance(p)!;
        }
        else if (!p.is(TokenKind.RPAREN))
        {
            p.error("Expected ',' or ')' in parameter list");
            return UNEXPECTED_TOKEN~;
        }
    }

    expect(p, TokenKind.RPAREN)!;
    return first_param;
}

fn Node? parse_param_decl(Parser* p)
{
    uint start = p.pos;
    bool is_ref = false;
    uint name = 0;
    Node type = 0;

    // Handle Reference (&self)
    if (consume(p, TokenKind.AMP)!)
    {
        is_ref = true;
    }

    // optional type
    if (is_type(p.current().kind) && p.peek(1).kind != TokenKind.COMMA && p.peek(1).kind != TokenKind.RPAREN)
    {
        type = parse_type(p)!;
    }

    TokenKind k = p.current().kind;
    if (k == TokenKind.IDENT || k == TokenKind.CT_IDENT || k == TokenKind.CT_TYPE_IDENT
        || k == TokenKind.HASH_IDENT)
    {
        name = p.pool.intern(p.token_text(p.current()));
        advance(p)!;
    }
    
    // Handle Default Values
    Node init = 0;
    if (consume(p, TokenKind.EQ)!)
    {
        init = parse_expr(p, 0)!;
    }

    uint[4] data = { name, (uint)type, (uint)init, is_ref ? 1 : 0 };
    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, NodeKind.PARAM_DECL, start, ex);
}

<*
	TYPE_EXPR - unresolved type, parser only cares about the syntax
*>
fn Node? parse_type(Parser* p)
{
    uint start_tok = p.pos;
	TypeDescriptor desc;
	TypeFlags flags;

    desc.name = p.pool.intern(p.token_text(p.current()));
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
			if (consume(p, TokenKind.ASTERISK)!)
			{
				desc.array_size = 0;
			}
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
			if (consume(p, TokenKind.ASTERISK)!)
			{
				desc.array_size = 0;
			}
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
    uint name_sh = p.pool.intern(p.token_text(name_tok));

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
    uint name_sh = p.pool.intern(p.token_text(name_tok));

    expect(p, TokenKind.EQ)!;

	if (consume(p, TokenKind.INLINE)!)
	{
		//TODO:
	}

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
    uint name_sh = p.pool.intern(p.token_text(name_tok));

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

fn Node? parse_const_decl(Parser* p, bool is_extern = false)
{
	uint start_tok = p.pos;
	expect(p, TokenKind.CONST)!;

	Node type;
	if (is_type(p.current().kind))
	{
		type = parse_type(p)!;
	}

	if (!p.is(TokenKind.CONST_IDENT))
	{
		log::error("Unexpected token after 'const'");
		p.error("Expected a CONST_IDENT after 'const'");
		return UNEXPECTED_TOKEN~;
	}

	uint name = p.pool.intern(p.token_text(p.current()));
	advance(p)!; // skip CONST_IDENT

	Node init_expr;
	if (p.is(TokenKind.EQ))
	{
		advance(p)!;
		init_expr = parse_expr(p)!;
	}

	expect(p, TokenKind.EOS)!;

    uint[*] data = { name, (uint)type, (uint)init_expr };

    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, NodeKind.CONST_DECL, start_tok, ex);
}

fn Node? parse_struct(Parser* p)
{
    uint start_tok = p.pos;

    expect(p, TokenKind.STRUCT)!;

    if (!p.is(TokenKind.TYPE_IDENT))
    {
        p.error("Expected struct name");
        return UNEXPECTED_TOKEN~;
    }
    uint name = p.pool.intern(p.token_text(p.current()));
    advance(p)!;

	//TODO: Generics
	if (p.is(TokenKind.LESS))
	{
		while (!p.is(TokenKind.GREATER))
		{
			advance(p)!;
		}
		advance(p)!;
	}

    expect(p, TokenKind.LBRACE)!;

	List{ uint } fields;
	fields.tinit(100);
	defer fields.free();

	// push name
	fields.push(name);
	// push size
	fields.push(0);

    while (!p.is(TokenKind.RBRACE))
    {
        fields.push((uint)parse_field_decl(p)!);

        expect(p, TokenKind.EOS)!;
		if (!p.is(TokenKind.TYPE_IDENT) && !is_type(p.current().kind))
		{
			break;
		}
    }

    expect(p, TokenKind.RBRACE)!;

    fields[1] = (uint)fields.len() - 2;

    uint ex = ast::push_extra_block(p.ast, fields.array_view());
    return ast::add_node(p.ast, NodeKind.STRUCT_DECL, start_tok, ex);
}

fn Node? parse_field_decl(Parser* p)
{
    uint start_tok = p.pos;

    Node type_node = parse_type(p)!;

    if (!p.is(TokenKind.IDENT))
    {
        p.error("Expected field name");
        return UNEXPECTED_TOKEN~;
    }

    uint name = p.pool.intern(p.token_text(p.current()));
    advance(p)!;

    // Optional: handle field attributes or default values here
    uint[2] data = { name, (uint)type_node };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.FIELD_DECL, start_tok, ex);
}