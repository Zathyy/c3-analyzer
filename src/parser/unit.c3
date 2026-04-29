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
	if (!p.is(TokenKind.IDENT) && p.peek().kind != TokenKind.SCOPE)
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
	return ast::add_node(p.ast, NodeKind.PATH, start_tok, p.current_pos(), ex);
}

<*
 Parse an optional foo::bar::
 @param [&inout] p
*>
fn Node? parse_path_prefix(Parser* p)
{
	if (!is_some_ident(p.current().kind) && p.peek().kind != TokenKind.SCOPE)
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

		if (p.is(TokenKind.SCOPE) && is_some_ident(p.peek().kind))
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
	uint ex = ast::push_extra_block(p.ast, &final_block);
	return ast::add_node(p.ast, NodeKind.PATH, start_tok, p.current_pos(), ex);
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
	if (current.kind == TokenKind.CT_TYPEOF || current.kind == TokenKind.CT_TYPEFROM)
	{
		advance(p)!;
		expect(p, TokenKind.LPAREN)!;
		desc.base_expr = parse_expr(p, { })!;
		expect(p, TokenKind.RPAREN)!;
		flags.is_comptime = true;
	}
	else
	{
		desc.name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;

		if (!parse_flags.no_generics)
		{
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
		}
	}

	while (true)
	{
		if (consume(p, TokenKind.LVEC)!)
		{
			flags.is_vector = true;
			if (consume(p, TokenKind.ASTERISK)!)
			{
				desc.array_size = { };
			}
			else
			{
				desc.array_size = parse_expr(p)!;
			}
			expect(p, TokenKind.RVEC)!;
			break;
		}
		if (consume(p, TokenKind.ASTERISK)!)
		{
			desc.ptr_count++;
			continue;
		}
		if (consume(p, TokenKind.QUESTION)!)
		{
			flags.is_optional = true;
			continue;
		}
		if (consume(p, TokenKind.LBRACKET)!)
		{
			if (consume(p, TokenKind.ASTERISK)!)
			{
				desc.array_size = { };
			}
			else if (p.is(TokenKind.RBRACKET))
			{
				desc.array_size = { };
			}
			else
			{
				desc.array_size = parse_expr(p)!;
			}
			expect(p, TokenKind.RBRACKET)!;
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

	uint ex = ast::push_extra_block(p.ast, &final_block);
	Node new_node = ast::add_node(p.ast, NodeKind.TYPE_EXPR, start_tok, p.current_pos(), ex);

	return new_node;
}

<*
 Parses Parameters
 @param [&inout] p
 @returns "Extra data index"
*>
fn uint? parse_parameter_list(Parser* p) => @scratch()
{
	expect(p, TokenKind.LPAREN)!;
	scratch.push(0); // count

	while (!p.is(TokenKind.RPAREN) && !p.eof())
	{
		Node param = parse_param_decl(p)!;
		scratch.push((uint)param);

		if (consume(p, TokenKind.COMMA)!) continue;
		if (!p.is(TokenKind.RPAREN))
		{
			p.error("Expected ')'");
			return 0;
		}
	}

	expect(p, TokenKind.RPAREN)!;
	scratch[0] = (uint)scratch.len() - 1;
	return ast::push_extra_block(p.ast, scratch.array_view());
}

<*
 implementing interfaces, e.g. struct Foo (MyInterface)

  NodeKind.INTERFACE_IMPL ::= '(' (type (',' type)* ','? )? ')'
 @param [&inout] p
*>
fn Node? parse_interface_impl(Parser* p)
{
    uint start_pos = p.current_pos();
    if (!consume(p, TokenKind.LPAREN)!) return {};
    // Handle empty list case: ()
    if (consume(p, TokenKind.RPAREN)!) return {};

    uint ex = 0;

    @with_scratch(; watermark)
    {
        while (true)
        {
            Node type_node = parse_type(p)!;
            scratch.push((uint)type_node);

            if (!consume(p, TokenKind.COMMA)!) break;
            if (p.is(TokenKind.RPAREN)) break;
        }

        uint count = (uint)scratch.len() - watermark;
        ex = ast::push_extra_block(p.ast, scratch_view(watermark, count));
    };

    expect(p, TokenKind.RPAREN)!;
    return ast::add_node(p.ast, NodeKind.INTERFACE_IMPL, start_pos, p.current_pos(), ex);
}

<*
	parse attributes
	@param [&inout] p
	@reutrn "extra index"
*>
fn uint? parse_attributes(Parser* p)
{
    if (!p.is(TokenKind.AT_IDENT) && !p.is(TokenKind.AT_TYPE_IDENT)) return 0;

    uint final_ex = 0;

    @with_scratch(; base_watermark)
    {
        while (p.is(TokenKind.AT_IDENT) || p.is(TokenKind.AT_TYPE_IDENT))
        {
            uint start_tok = p.current_pos();
            String attr_name = p.token_text(p.current());
            advance(p)!;

            uint arg_count = 0;
            uint args_ex = 0;

            // Handle Attribute Arguments
            if (consume(p, TokenKind.LPAREN)!)
            {
                @with_scratch(; watermark)
                {
                    while (!p.eof())
                    {
                        Node expr = parse_attribute_argument(p)!;
                        if (expr) scratch.push((uint)expr);
                        
                        if (consume(p, TokenKind.RPAREN)!) break;
                        expect(p, TokenKind.COMMA)!;
                    }
                    
                    uint count = (uint)scratch.len() - watermark;
                    arg_count = count;
                    args_ex = ast::push_extra_block(p.ast, scratch_view(watermark, count));
                };
            }

            uint[3] attr_block = { 
                (uint)common::get_attribute_from_string(attr_name), 
                args_ex, 
                arg_count 
            };

            uint ex = ast::push_extra_block(p.ast, &attr_block);
            Node attr_node = ast::add_node(p.ast, NodeKind.ATTRIBUTE, start_tok, p.previous_pos(), ex);

            scratch.push((uint)attr_node);
        }

        uint total_attrs = (uint)scratch.len() - base_watermark;
        final_ex = ast::push_extra_block(p.ast, scratch_view(base_watermark, total_attrs));
    };

    return final_ex;
}

fn Node? parse_attribute_argument(Parser* p) 
{
    Token curr = p.current();
    
    switch (curr.kind) 
	{
        case TokenKind.LBRACKET: // []  []=
            advance(p)!;
            expect(p, TokenKind.RBRACKET)!;
            OverloadKind kind = consume(p, TokenKind.EQ)! ? OverloadKind.ELEMENT_SET : OverloadKind.ELEMENT_AT;
            return ast::add_node(p.ast, NodeKind.OP_OVERLOAD, curr.pos, p.current_pos(), (uint)kind);
        case TokenKind.AMP: // &[]
            if (p.peek(1).kind == TokenKind.LBRACKET) 
			{
                advance(p, 2)!;
                expect(p, TokenKind.RBRACKET)!;
                return ast::add_node(p.ast, NodeKind.OP_OVERLOAD, curr.pos, p.current_pos(), (uint)OverloadKind.ELEMENT_REF);
            }
			else
			{
				advance(p)!;
				return ast::add_node(p.ast, 
						NodeKind.OP_OVERLOAD, 
						curr.pos, 
						p.current_pos(), 
						(uint)get_overload_from_token(curr.kind));
			}
		case TokenKind.PLUS:
		case TokenKind.MINUS:
		case TokenKind.ASTERISK:
		case TokenKind.DIV:
		case TokenKind.MOD:
		case TokenKind.BIT_NOT:
		case TokenKind.BIT_OR:
		case TokenKind.BIT_XOR:
		case TokenKind.LSHIFT:
		case TokenKind.RSHIFT:
		case TokenKind.EQEQ:
		case TokenKind.NOT_EQUAL:
		case TokenKind.BIT_AND_ASSIGN:
		case TokenKind.BIT_OR_ASSIGN:
		case TokenKind.BIT_XOR_ASSIGN:
		case TokenKind.PLUS_ASSIGN:
		case TokenKind.MINUS_ASSIGN:
		case TokenKind.MULT_ASSIGN:
		case TokenKind.DIV_ASSIGN:
		case TokenKind.MOD_ASSIGN:
		case TokenKind.LSHIFT_ASSIGN:
		case TokenKind.RSHIFT_ASSIGN:
            if (p.peek(1).kind == TokenKind.RPAREN || p.peek(1).kind == TokenKind.COMMA) 
			{
                Node n = ast::add_node(p.ast, 
					NodeKind.OP_OVERLOAD,
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
    Returns the first node in a Linked-List (if valid!)
*>
fn Node? parse_generics(Parser* p)
{
	if (!consume(p, TokenKind.LESS)!) return { };

	Node head;

	while (true)
	{
		Token t = p.current();
		if (!is_some_ident(t.kind))
		{
			p.error("Expected identifier in generic list, got %s", p.token_text(t));
			return { };
		}

		uint id = p.pool.intern(p.token_text(t));
		advance(p)!;

		uint[2] generic_block = { id, (uint)head };

		uint ex = ast::push_extra_block(p.ast, &generic_block);
		head = ast::add_node(p.ast, NodeKind.GENERIC_PARAM, t.pos, p.current_pos(), ex);

		if (!consume(p, TokenKind.COMMA)!) break;
		if (p.is(TokenKind.GREATER)) break;
	}

	expect(p, TokenKind.GREATER)!;

	return head;
}

/* *
 * Unified parser for:
 * - Global variables (is_global)
 * - Local variables (is_local)
 * - var
 * - Constants (is_const) */
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
		&& (p.peek().kind == TokenKind.IDENT || p.peek().kind == TokenKind.CONST_IDENT
			|| p.peek().kind == TokenKind.CT_IDENT))
	{
		type_node = parse_type(p)!;
	}

	Token t = p.current();
	if (flags.is_const)
	{
		if (t.kind != TokenKind.CONST_IDENT)
		{
			p.error("Constants must use a CONST_IDENT (e.g., MY_VALUE), found '%s'", p.token_text(t));
			return { };
		}
	}
	else
	{
		if (t.kind != TokenKind.IDENT && !flags.is_local)
		{
			p.error("Global variables must use a lower-case IDENT (e.g., my_var), found '%s'", p.token_text(t));
			return { };
		}
	}
	uint name = p.pool.intern(p.token_text(p.current()));
	advance(p)!;

	uint attr = parse_attributes(p)!;

	Node init_expr = { };
	if (consume(p, TokenKind.EQ)!)
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

	expect(p, TokenKind.EOS)!;

	uint[*] data = { name, (uint)type_node, (uint)init_expr, attr };
	uint ex = ast::push_extra_block(p.ast, &data);

	if (flags.is_const) return ast::add_node(p.ast, NodeKind.CONST_DECL, start_pos, end_tok, ex);
	if (flags.is_global) return ast::add_node(p.ast, NodeKind.GLOBAL_DECL, start_pos, end_tok, ex);

	return ast::add_node(p.ast, NodeKind.VAR_DECL, start_pos, end_tok, ex);
}
