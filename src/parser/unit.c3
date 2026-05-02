<*
 unit.c3 - parsing things which arent any of (Decl, Stmt, Expr)
*>
module c3_parser::parser;

import c3_parser::ast;
import c3_parser::common;
import lexer;

import std::io;
import std::collections::list;

<*
	Parse a full path e.g. foo::bar::baz;
	@param [&inout] p
*>
fn Node? parse_path(Parser* p)
{
	uint start_pos = p.current_pos();

	if (!p.is(IDENT))
	{
		log::debug("not a valid path");
		return INVALID_PATH~;
	}

	@with_scratch(; watermark)
	{
		while (true)
		{
			Token t = p.current();
			
			uint sh = p.pool.intern(p.token_text(t));
			scratch.push(sh);
			
			advance(p)!;

			if (!consume(p, SCOPE)!) break;

			if (!is_some_ident(p.current().kind))
			{
				p.error("Expected identifier after '::'");
				return UNEXPECTED_TOKEN~;
			}
		}

		uint count = (uint)scratch.len() - watermark;
		uint[] parts = scratch_view(watermark, count);

		uint ex = ast::push_extra_list(p.ast, parts);
		return ast::add_node(p.ast, PATH, start_pos, p.current_pos(), ex);
	};
}

<*
 Parse an optional foo::bar::
 @param [&inout] p
*>
fn Node? parse_path_prefix(Parser* p)
{
	if (!is_some_ident(p.current().kind) && p.peek().kind != SCOPE)
	{
		return NOT_A_PATH~;
	}

    uint start_tok = p.current_pos();
    uint ex = 0;

    @with_scratch(; watermark) 
	{
        while (true) 
		{
            Token t = p.current();
            scratch.push((uint)p.pool.intern(p.token_text(t)));
            advance(p)!;

            if (p.is(SCOPE) && is_some_ident(p.peek().kind)) 
			{
                advance(p)!; // Consume '::'
            } 
			else 
			{
                break;
            }
        }

        ex = ast::push_extra_list(p.ast, scratch_view(watermark, (uint)scratch.len() - watermark));
    };

    return ast::add_node(p.ast, PATH, start_tok, p.current_pos(), ex);
}

<*
	TYPE_EXPR - unresolved type, parser only cares about the syntax
*>
fn Node? parse_type(Parser* p, ParseFlags parse_flags = { })
{
	uint start_tok = p.current_pos();
	uint name_or_path;
	Node base_expr;
	uint gen_args_list_ex;

	TypeFlags flags;
	uint ptr_count;
	Node array_size;

	if (p.is(CT_TYPEOF) || p.is(CT_TYPEFROM)) 
	{
		advance(p)!;
		expect(p, LPAREN)!;
		base_expr = parse_expr(p)!;
		expect(p, RPAREN)!;
		flags.is_comptime = true;
	} 
	else 
	{
		if (parse_flags.type_as_expression && p.peek().kind == SCOPE)
        {
            name_or_path = p.pool.intern(p.token_text(p.current()));
            advance(p)!;
        }
        else 
        {
            uint? path = (uint)parse_path_prefix(p);
            if (try path)
            {
                name_or_path = path;
            }
            else
            {
                name_or_path = p.pool.intern(p.token_text(p.current()));
                advance(p)!;
            }
        }

		if (!parse_flags.no_generics && consume(p, LBRACE)!) 
		{
			@with_scratch(; watermark) 
			{
				while (!p.is(RBRACE))
				{
					scratch.push((uint)parse_type(p)!);
					if (!consume(p, COMMA)!) break;
				}
				gen_args_list_ex = ast::push_extra_list(p.ast, scratch_view(watermark, (uint)scratch.len() - watermark));
			};
			expect(p, RBRACE)!;
		}
	}

	while (true) 
	{
		// Vector <*4>
        if (consume(p, LVEC)!)
		{ 
            flags.is_vector = true;
            array_size = consume(p, ASTERISK)! ? 0 : parse_expr(p)!;
            expect(p, RVEC)!;
            break; 
        }
        if (consume(p, ASTERISK)!) 
		{ 
			ptr_count++; continue; 
		}
        if (consume(p, QUESTION)!) 
		{
			flags.is_optional = true;
			continue; 
		}
		if (consume(p, LBRACKET)!) {
			array_size = (p.is(RBRACKET) || p.peek().kind == ASTERISK) ? 0 : parse_expr(p)!;
			if (p.is(ASTERISK)) advance(p)!;
			expect(p, RBRACKET)!;
			continue;
		}
		break;
	}

	uint[6] header = { 
		name_or_path, 
		ptr_count, 
		(uint)array_size, 
		gen_args_list_ex, 
		(uint)base_expr, 
		(uint)flags 
	};

	uint ex = ast::push_extra_block(p.ast, &header);
	return ast::add_node(p.ast, TYPE_EXPR, start_tok, p.current_pos(), ex);
}

<*
 Parses Parameters
 @param [&inout] p
 @returns "Extra data index"
*>
fn uint? parse_parameter_list(Parser* p) => @with_scratch(; watermark)
{
	expect(p, LPAREN)!;

	while (!p.is(RPAREN) && !p.eof())
	{
		Node param = parse_param_decl(p)!;
		scratch.push((uint)param);

		if (consume(p, COMMA)!) continue;
		if (!p.is(RPAREN))
		{
			p.error("Expected ')'");
			return 0;
		}
	}

	expect(p, RPAREN)!;
	uint count = (uint)scratch.len() - watermark;
	return ast::push_extra_list(p.ast, scratch_view(watermark, count));
}

<*
 implementing interfaces, e.g. struct Foo (MyInterface)

  INTERFACE_IMPL ::= '(' (type (',' type)* ','? )? ')'
 @param [&inout] p
*>
fn Node? parse_interface_impl(Parser* p)
{
    uint start_pos = p.current_pos();
    if (!consume(p, LPAREN)!) return {};
    // Handle empty list case: ()
    if (consume(p, RPAREN)!) return {};

    uint ex = 0;

    @with_scratch(; watermark)
    {
        while (true)
        {
            Node type_node = parse_type(p)!;
            scratch.push((uint)type_node);

            if (!consume(p, COMMA)!) break;
            if (p.is(RPAREN)) break;
        }

        uint count = (uint)scratch.len() - watermark;
        ex = ast::push_extra_list(p.ast, scratch_view(watermark, count));
    };

    expect(p, RPAREN)!;
    return ast::add_node(p.ast, INTERFACE_IMPL, start_pos, p.current_pos(), ex);
}

<*
	parse attributes
	@param [&inout] p
	@reutrn "extra index"
*>
fn uint? parse_attributes(Parser* p)
{
    if (!p.is(AT_IDENT) && !p.is(AT_TYPE_IDENT)) return 0;

    uint final_ex;

    @with_scratch(; base_watermark)
    {
        while (p.is(AT_IDENT) || p.is(AT_TYPE_IDENT))
        {
            uint start_tok = p.current_pos();
            String attr_name = p.token_text(p.current());
            advance(p)!;
            
            uint args_list_ex;

            if (consume(p, LPAREN)!)
            {
                @with_scratch(; watermark)
                {
                    while (!p.eof())
                    {
                        Node expr = parse_attribute_argument(p)!;
                        if (expr) scratch.push((uint)expr);
                        
                        if (consume(p, RPAREN)!) break;
                        expect(p, COMMA)!;
                    }
                    args_list_ex = ast::push_extra_list(p.ast, scratch_view(watermark, (uint)scratch.len() - watermark));
                };
            }
			else if (p.is(STRING))
			{
				Node msg_expr = parse_expr(p)!; 
				uint[1] single_arg = { (uint)msg_expr };
				args_list_ex = ast::push_extra_list(p.ast, &single_arg);
			}

            uint[2] attr_data = {
                (uint)common::get_attribute_from_string(attr_name), 
                args_list_ex, 
            };

            uint ex = ast::push_extra_block(p.ast, &attr_data);
            Node attr_node = ast::add_node(p.ast, ATTRIBUTE, start_tok, p.previous_pos(), ex);
            scratch.push((uint)attr_node);
        }

        uint total_attrs = (uint)scratch.len() - base_watermark;
        final_ex = ast::push_extra_list(p.ast, scratch_view(base_watermark, total_attrs));
    };

    return final_ex;
}

fn Node? parse_attribute_argument(Parser* p) 
{
	Token curr = p.current();

	switch (curr.kind) 
	{
		case LBRACKET: // []  []=
			advance(p)!;
			expect(p, RBRACKET)!;
			OverloadKind kind = consume(p, EQ)! ? OverloadKind.ELEMENT_SET : OverloadKind.ELEMENT_AT;
			return ast::add_node(p.ast, OP_OVERLOAD, curr.pos, p.current_pos(), (uint)kind);
		case AMP: // &[]
			if (p.peek(1).kind == LBRACKET) 
			{
				advance(p, 2)!;
				expect(p, RBRACKET)!;
				return ast::add_node(p.ast, OP_OVERLOAD, curr.pos, p.current_pos(), (uint)OverloadKind.ELEMENT_REF);
			}
			else
			{
				advance(p)!;
				return ast::add_node(p.ast, 
						OP_OVERLOAD, 
						curr.pos, 
						p.current_pos(), 
						(uint)get_overload_from_token(curr.kind));
			}
		case PLUS:
		case MINUS:
		case ASTERISK:
		case DIV:
		case MOD:
		case BIT_NOT:
		case BIT_OR:
		case BIT_XOR:
		case LSHIFT:
		case RSHIFT:
		case EQEQ:
		case NOT_EQUAL:
		case BIT_AND_ASSIGN:
		case BIT_OR_ASSIGN:
		case BIT_XOR_ASSIGN:
		case PLUS_ASSIGN:
		case MINUS_ASSIGN:
		case MULT_ASSIGN:
		case DIV_ASSIGN:
		case MOD_ASSIGN:
		case LSHIFT_ASSIGN:
		case RSHIFT_ASSIGN:
			if (p.peek(1).kind == RPAREN || p.peek(1).kind == COMMA) 
			{
				Node n = ast::add_node(p.ast, 
					OP_OVERLOAD,
					curr.pos, 
					p.current_pos(), 
					(uint)get_overload_from_token(curr.kind));

				advance(p)!;
				return n;
			}
			return parse_expr(p)!;
		default:
			break;
	}

	return parse_expr(p)!;
}

<*
 	Parses: <T, V ...>
    Returns the index into extra data
*>
fn uint? parse_generics(Parser* p)
{
    if (!consume(p, LESS)!) return 0;

    uint final_ex = 0;

    @with_scratch(; watermark)
    {
        while (true)
        {
            Token t = p.current();
            if (!is_some_ident(t.kind))
            {
                p.error("Expected identifier in generic list, got %s", p.token_text(t));
                return { };
            }

            uint name_id = p.pool.intern(p.token_text(t));
            advance(p)!;

            // Check for variadic generics: e.g., <T, V...>
            bool is_variadic = consume(p, ELLIPSIS)!;

            uint flags = is_variadic ? 1 : 0;
            uint[2] param_data = { name_id, flags };
            uint ex = ast::push_extra_list(p.ast, &param_data);
            
            Node param_node = ast::add_node(p.ast, GENERIC_PARAM, t.pos, p.previous_pos(), ex);
            
            scratch.push((uint)param_node);

            if (!consume(p, COMMA)!) break;
            if (p.is(GREATER)) break;
        }

        uint count = (uint)scratch.len() - watermark;
        final_ex = ast::push_extra_list(p.ast, scratch_view(watermark, count));
    };

    expect(p, GREATER)!;
    return final_ex;
}

<*
	Unified parser for:
	- Global variables (is_global)
	- Local variables (is_local)
	- Constants (is_const) 
*>
fn Node? parse_var_decl(Parser* p, ParseFlags flags)
{
	uint start_pos = p.current_pos();

	if (flags.is_local)
	{
		if (flags.is_extern)
		{
			p.error("a local variable cant have a extern modifier");
			return UNEXPECTED_TOKEN~;
		}

		if (flags.is_inline)
		{
			p.error("a local variable cant be inline");
			return UNEXPECTED_TOKEN~;
		}
	}

	if (flags.is_var)
	{
		advance(p)!;
	}

	Node type_node;
	if (is_type(p.current().kind)
		&& (p.peek().kind == IDENT || p.peek().kind == CONST_IDENT
			|| p.peek().kind == CT_IDENT))
	{
		type_node = parse_type(p)!;
	}

	Token t = p.current();
	if (flags.is_const)
	{
		if (t.kind != CONST_IDENT)
		{
			p.error("Constants must use a CONST_IDENT (e.g., MY_VALUE), found '%s'", p.token_text(t));
			return { };
		}
	}
	else
	{
		if (t.kind != IDENT && !flags.is_local)
		{
			p.error("Global variables must use a lower-case IDENT (e.g., my_var), found '%s'", p.token_text(t));
			return { };
		}
	}
	uint name = p.pool.intern(p.token_text(p.current()));
	advance(p)!;

	uint attr = parse_attributes(p)!;

	Node init_expr;
	if (consume(p, EQ)!)
	{
		if (flags.is_extern)
		{
			p.error("a extern global cant have a initializer expression");
			return UNEXPECTED_TOKEN~;
		}

		init_expr = parse_expr(p)!;
	}
	else if (flags.is_const && !flags.is_extern)
	{
		p.error("Constants must be initialized at declaration");
	}

	uint end_tok = p.current_pos();

	expect(p, EOS)!;

	VarDeclFlags packed_flags = {
		.is_extern = flags.is_extern,
		.is_const = flags.is_const,
		.is_inline = flags.is_inline,
		.is_local = flags.is_local,
		.is_thread_local = flags.is_thread_local
	};

	uint[*] data = { name, (uint)type_node, (uint)init_expr, attr, (uint)packed_flags };
	uint ex = ast::push_extra_block(p.ast, &data);
	return ast::add_node(p.ast, VAR_DECL, start_pos, end_tok, ex);
}

fn Node? parse_contract_param(Parser* p)
{
    uint start = p.current_pos();

	ContractParamFlags flags;
	InOutModifier mod;

	if (consume(p, LBRACKET)!)
	{
		flags.is_ref = consume(p, AMP)!;
		String modifer_name = p.current_text();
		switch (modifer_name)
		{
			case "in":
				mod = IN;
				break;
			case "inout":
				mod = INOUT;
				break;
			case "out":
				mod = OUT;
				break;
			default:
				p.error("'in', 'out' or 'inout' expected");
				p.push_invalid_node(p.current_pos());
		}

		if (!consume(p, RBRACKET)!)
		{
			p.error("Expected a closing ']'");
			p.push_invalid_node(p.current_pos());
		}
	}
    
    if (!p.is(IDENT)) 
    {
        p.error("Expected parameter name after @param");
        p.push_invalid_node(p.current_pos());
    }

	// ident_expr
    Node param_name = parse_expr(p)!;
    advance(p)!;

	uint description;
    if (p.is(COLON))
	{
		description = p.pool.intern(p.current_text());
		advance(p)!;
	}
	else
	{
		p.error("Forgot colon after");
		p.push_invalid_node(p.current_pos());
	}

    uint[4] data = { (uint)param_name, description, (uint)flags, (uint)mod };
    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, CONTRACT_PARAM, start, p.current_pos(), ex);
}