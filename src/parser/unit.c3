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
	if (!p.is(IDENT) && p.peek().kind != SCOPE)
	{
		log::debug("not a valid path");
		return INVALID_PATH~;
	}

	uint start_tok = p.current_pos();
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

		expect(p, IDENT)!;
		if (!consume(p, SCOPE)!) break;
	}

	uint[PATH_MAX_LENGTH + 1] final_block;
	final_block[0] = count;

	// Copy the parts into the block
	for (uint i = 0; i < count; i++)
	{
		final_block[i + 1] = stack_parts[i];
	}
	uint ex = ast::push_extra_list(p.ast, &final_block);
	return ast::add_node(p.ast, PATH, start_tok, p.current_pos(), ex);
}

<*
 Parse an optional foo::bar::
 @param [&inout] p
*>
fn Node? parse_path_prefix(Parser* p)
{
	if (!is_some_ident(p.current().kind) && p.peek().kind != SCOPE)
	{
		log::error("not a valid path");
		return INVALID_PATH~;
	}

	uint start_tok = p.current_pos();
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

	uint[PATH_MAX_LENGTH + 1] final_block;
	final_block[0] = count;

	for (uint i = 0; i < count; i++)
	{
		final_block[i + 1] = stack_parts[i];
	}
	uint ex = ast::push_extra_list(p.ast, &final_block);
	return ast::add_node(p.ast, PATH, start_tok, p.current_pos(), ex);
}

<*
 TYPE_EXPR - unresolved type, parser only cares about the syntax
*>
fn Node? parse_type(Parser* p, ParseFlags parse_flags = { })
{
	uint start_tok = p.current_pos();
	Token current = p.current();
	TypeDescriptor desc;
	TypeFlags flags;

	// Check for Compile-Time
	if (current.kind == CT_TYPEOF || current.kind == CT_TYPEFROM)
	{
		advance(p)!;
		expect(p, LPAREN)!;
		desc.base_expr = parse_expr(p, { })!;
		expect(p, RPAREN)!;
		flags.is_comptime = true;
	}
	else
	{
		desc.name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;

		if (!parse_flags.no_generics)
		{
			if (consume(p, LBRACE)!)
			{
				while (!p.is(RBRACE))
				{
					desc.gen_args[desc.gen_count++] = parse_type(p)!;

					if (desc.gen_count >= common::MAX_GENERICS)
					{
						p.error("Too many generics");
						return TOO_MANY_GENERICS~;
					}
					if (!consume(p, COMMA)!) break;
				}
				expect(p, RBRACE)!;
			}
		}
	}

	while (true)
	{
		if (consume(p, LVEC)!)
		{
			flags.is_vector = true;
			if (consume(p, ASTERISK)!)
			{
				desc.array_size = { };
			}
			else
			{
				desc.array_size = parse_expr(p)!;
			}
			expect(p, RVEC)!;
			break;
		}
		if (consume(p, ASTERISK)!)
		{
			desc.ptr_count++;
			continue;
		}
		if (consume(p, QUESTION)!)
		{
			flags.is_optional = true;
			continue;
		}
		if (consume(p, LBRACKET)!)
		{
			if (consume(p, ASTERISK)!)
			{
				desc.array_size = { };
			}
			else if (p.is(RBRACKET))
			{
				desc.array_size = { };
			}
			else
			{
				desc.array_size = parse_expr(p)!;
			}
			expect(p, RBRACKET)!;
			continue;
		}
		break;
	}

	uint[common::MAX_GENERICS + 6] final_block;

	final_block[0] = (uint)desc.name;
	final_block[1] = (uint)desc.ptr_count;
	final_block[2] = (uint)desc.array_size;
	final_block[3] = (uint)desc.gen_count;
	final_block[4] = (uint)desc.base_expr;
	final_block[5] = (uint)flags;

	for (uint i = 0; i < desc.gen_count; i++)
	{
		final_block[7 + i] = (uint)desc.gen_args[i];
	}

	uint ex = ast::push_extra_list(p.ast, &final_block);
	Node new_node = ast::add_node(p.ast, TYPE_EXPR, start_tok, p.current_pos(), ex);

	return new_node;
}

<*
 Parses Parameters
 @param [&inout] p
 @returns "Extra data index"
*>
fn uint? parse_parameter_list(Parser* p) => @scratch()
{
	expect(p, LPAREN)!;
	scratch.push(0); // count

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
	scratch[0] = (uint)scratch.len() - 1;
	return ast::push_extra_list(p.ast, scratch.array_view());
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

    uint final_ex = 0;

    @with_scratch(; base_watermark)
    {
        while (p.is(AT_IDENT) || p.is(AT_TYPE_IDENT))
        {
            uint start_tok = p.current_pos();
            String attr_name = p.token_text(p.current());
            advance(p)!;

            uint arg_count = 0;
            uint args_ex = 0;

            // Handle Attribute Arguments
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
                    
                    uint count = (uint)scratch.len() - watermark;
                    arg_count = count;
                    args_ex = ast::push_extra_list(p.ast, scratch_view(watermark, count));
                };
            }

            uint[3] attr_block = { 
                (uint)common::get_attribute_from_string(attr_name), 
                args_ex, 
                arg_count 
            };

            uint ex = ast::push_extra_list(p.ast, &attr_block);
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

	Node init_expr = { };
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
	uint ex = ast::push_extra_list(p.ast, &data);
	return ast::add_node(p.ast, VAR_DECL, start_pos, end_tok, ex);
}
