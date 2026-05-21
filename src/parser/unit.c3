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

		uint ex = p.ast.push_extra_list(parts);
		return p.ast.add_node(PATH, start_pos, p.current_pos(), ex);
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

		ex = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};

	return p.ast.add_node(PATH, start_tok, p.current_pos(), ex);
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
					scratch.push((uint)parse_constant_expr(p)!);
					if (!consume(p, COMMA)!) break;
				}
				gen_args_list_ex = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
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
			continue; 
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
		if (consume(p, LBRACKET)!) 
		{
			if (p.is(ASTERISK) || p.is(RBRACKET)) 
			{
				array_size = (Node)0;
				if (p.is(ASTERISK)) advance(p)!;
			} 
			else 
			{
				array_size = parse_expr(p)!;
			}

			expect(p, RBRACKET)!;
			continue;
		}
		break;
	}

	uint[*] header = views::@data{TypeViewFields}
	(
		NAME, name_or_path, 
		PTR_COUNT, ptr_count, 
		ARRAY_SIZE, array_size, 
		GENERICS, gen_args_list_ex, 
		BASE_EXPR, base_expr, 
		FLAGS, flags,
	);

	uint ex = p.ast.push_extra_block(&header);
	return p.ast.add_node(TYPE_EXPR, start_tok, p.current_pos(), ex);
}

<*
	Parses Parameters
	@param [&inout] p
	@returns "Extra data index"
*>
fn Node? parse_parameter_list(Parser* p, ParseFlags flags = {}) => @with_scratch(; watermark)
{
	uint start_pos = p.current_pos();

	if (!flags.is_call && !flags.is_macro)
	{
		expect(p, LPAREN)!;
	}
	
	if (p.is(EOS))
	{
		return p.ast.add_empty(start_pos);
	}

	while (!p.is(RPAREN) && !p.eof())
	{
		Node param = parse_param_decl(p)!;
		scratch.push((uint)param);

		if (p.is(COMMA) || p.is(EOS))
		{
			advance(p)!;
			if (p.is(RPAREN)) break; 
		}
		else if (!p.is(RPAREN))
		{
			p.error("Expected ',' or ';' between parameters, found '%s'", p.token_text(p.current()));
			p.push_invalid_node(p.current_pos());
			p.skip_until({ RPAREN, EOS })!;
		}
	}

	if (!flags.is_call && !flags.is_macro)
	{
		expect(p, RPAREN)!;
	}
	uint count = (uint)scratch.len() - watermark;
	log::debug("Adding %s parameters", count);
	uint param_list = p.ast.push_extra_list(scratch_view(watermark, count));

	uint[*] data = views::@data{ParamsListViewFields}
	(
		PARAMS, param_list,
	);
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(PARAM_LIST, start_pos, p.current_pos(), ex);
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
        ex = p.ast.push_extra_list(scratch_view(watermark, count));
    };

    expect(p, RPAREN)!;
    return p.ast.add_node(INTERFACE_IMPL, start_pos, p.current_pos(), ex);
}

<*
	Parses a sequence of attributes and returns an ATTRIBUTE_LIST node.
	@param [&inout] p
*>
fn Node? parse_attributes(Parser* p, bool comma_seperated = false)
{
	if (!p.is(AT_IDENT) && !p.is(AT_TYPE_IDENT)) return {};

	uint start_pos = p.current_pos();
	Node attribute_list_node;

	@with_scratch(; base_watermark)
	{
		while (p.is(AT_IDENT) || p.is(AT_TYPE_IDENT))
		{
			uint attr_start = p.current_pos();
			String attr_name = p.token_text(p.current());
			advance(p)!;

			uint args_list_ex = 0;

			AttributeKind attr_kind = common::get_attribute_from_string(attr_name);

			if (attr_kind == OPERATOR || attr_kind == OPERATOR_R || attr_kind == OPERATOR_S)
			{
				expect(p, LPAREN)!;

				if (consume(p, AMP)!)
				{
					if (consume(p, LBRACKET)!) expect(p, RBRACKET)!;
				}
				else if (consume(p, LBRACKET)!)
				{
					expect(p, RBRACKET)!;
					consume(p, EQ)!;
				}
				else
				{
					p.advance()!;
				}

				// TODO: Actually save the good op
				uint[1] single_arg = { 1 };
				args_list_ex = p.ast.push_extra_list(&single_arg);
				expect(p, RPAREN)!;
			}
			// Standard argument list @attr(arg1, arg2)
			else if (consume(p, LPAREN)!)
			{
				@with_scratch(; watermark)
				{
					while (!p.eof())
					{
						Node expr = parse_attribute_argument(p)!;
						if (expr.is_valid()) scratch.push((uint)expr);

						if (consume(p, RPAREN)!) break;
						expect(p, COMMA)!;
					}
					uint count = (uint)scratch.len() - watermark;
					args_list_ex = p.ast.push_extra_list(scratch_view(watermark, count));
				};
			}
			// Short-hand string attribute @deprecated "message"
			else if (p.is(STRING))
			{
				Node msg_expr = parse_expr(p)!; 
				uint[1] single_arg = { (uint)msg_expr };
				args_list_ex = p.ast.push_extra_list(&single_arg);
			}

			uint[*] data = views::@data{AttributeViewFields}
			(
				KIND, attr_kind,
				ARGS, args_list_ex,
			);

			uint ex = p.ast.push_extra_block(&data);
			Node attr_node = p.ast.add_node(ATTRIBUTE, attr_start, p.previous_pos(), ex);
			scratch.push((uint)attr_node);

			// if comma_seperated, we need a comma to continue
			if (comma_seperated && !consume(p, COMMA)!) break;
		}

		// Wrap all found ATTRIBUTE nodes into one ATTRIBUTE_LIST
		uint total_attrs = (uint)scratch.len() - base_watermark;
		uint final_ex = p.ast.push_extra_list(scratch_view(base_watermark, total_attrs));

		uint[*] data = views::@data{AttributeListViewFields}
		(
			ATTRIBUTES, final_ex,
		);

		uint node_ex = p.ast.push_extra_block(&data);
		attribute_list_node = p.ast.add_node(ATTRIBUTE_LIST, start_pos, p.previous_pos(), node_ex);
	};

	return attribute_list_node;
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
			return p.ast.add_node(OP_OVERLOAD, curr.pos, p.current_pos(), (uint)kind);
		case AMP: // &[]
			if (p.peek(1).kind == LBRACKET) 
			{
				advance(p, 2)!;
				expect(p, RBRACKET)!;
				return p.ast.add_node(OP_OVERLOAD, curr.pos, p.current_pos(), (uint)OverloadKind.ELEMENT_REF);
			}
			else
			{
				advance(p)!;
				return p.ast.add_node(
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
				Node n = p.ast.add_node(
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
	Unified parser for:
	- Global variables (is_global)
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

	if (flags.is_var)
	{
		advance(p)!;
		type_node = p.ast.add_empty(p.current_pos());
	}

	if (is_type(p) && is_declaration_followup(p))
	{
		type_node = parse_type(p)!;
	}

	// if it is const, the type node is optional
	if (flags.is_const && !type_node.is_valid())
	{
		type_node = p.ast.add_empty(p.current_pos());
	}

	@with_scratch(; watermark)
	{
		while (true)
		{
			Token t = p.current();
			if (flags.is_const && t.kind != CONST_IDENT)
			{
				p.error("Constants must use a CONST_IDENT, found '%s'", p.token_text(t));
				return { };
			}
			if (!flags.is_const && t.kind != IDENT && !flags.is_local)
			{
				p.error("Global variables must use lower-case IDENT, found '%s'", p.token_text(t));
				return { };
			}

			uint name = p.pool.intern(p.token_text(t));
			advance(p)!;

			Node attr = parse_attributes(p)!;
			Node init_expr;

			if (consume(p, EQ)!)
			{
				if ((uint)scratch.len() > watermark)
				{
					p.error("Initializers are not allowed in multi-declarations");
					return UNEXPECTED_TOKEN~;
				}

				if (flags.is_extern)
				{
					p.error("a extern global cant have a initializer");
					return UNEXPECTED_TOKEN~;
				}
				init_expr = parse_expr(p)!;
			}
			else if (flags.is_const && !flags.is_extern)
			{
				p.error("Constants must be initialized");
			}

			VarDeclFlags packed_flags = {
				.is_extern = flags.is_extern,
				.is_const = flags.is_const,
				.is_inline = flags.is_inline,
				.is_local = flags.is_local,
				.is_thread_local = flags.is_thread_local,
				.is_static = flags.is_static,
			};

			uint[*] var_data = views::@data{VarDeclViewFields}
			(
				NAME, name,
				TYPE, type_node, // Same type node shared by all in the list
				INIT, init_expr,
				ATTRIBUTES, attr,
				FLAGS, packed_flags,
			);

			uint var_ex = p.ast.push_extra_block(&var_data);
			Node var_node = p.ast.add_node(VAR_DECL, t.pos, p.current_pos(), var_ex);
			scratch.push((uint)var_node);

			if (flags.is_expr) break;

			if (!consume(p, COMMA)!) break;
		}

		if (!flags.skip_eos)
		{
			expect(p, EOS)!;
		}

		uint count = (uint)scratch.len() - watermark;

		if (count == 1) 
		{
			return (Node)scratch.pop();
		}

		uint list_ex = p.ast.push_extra_list(scratch_view(watermark, count));

		uint[*] list_header = { list_ex };
		uint final_ex = p.ast.push_extra_block(&list_header);
		return p.ast.add_node(VAR_DECL_LIST, start_pos, p.current_pos(), final_ex);
	}; 
}	

fn Node? parse_local(Parser* p, uint start_pos, Node type_node, ParseFlags flags = {})
{
	if (!type_node.is_valid())
	{
		type_node = parse_type(p)!;
	}

	@with_scratch(; watermark)
	{
		while (true)
		{
			Token name_tok = p.current();
			advance(p)!;

			Node init;
			if (consume(p, EQ)!) 
			{
				init = parse_expr(p)!;
			}

			Node attr = parse_attributes(p)!;

			// Create the individual LOCAL_DECL
			uint name_sh = p.pool.intern(p.token_text(name_tok));

			uint[*] data = views::@data{LocalViewFields}
			(
				NAME, name_sh,
				TYPE, type_node,
				INIT, init,
				ATTRIBUTES, attr,
			);

			uint ex = p.ast.push_extra_list(&data);
			Node decl = p.ast.add_node(LOCAL_DECL, name_tok.pos, p.current_pos(), ex);

			scratch.push((uint)decl);

			if (init.is_valid()) break;
			if (!consume(p, COMMA)!) break;
		}

		expect(p, EOS)!;

		uint count = (uint)scratch.len() - watermark;

		// If just one, return the LOCAL_DECL directly (no wrapper)
		if (count == 1) return (Node)scratch.pop();

		// If multiple, wrap in a container
		uint list_ex = p.ast.push_extra_list(scratch_view(watermark, count));
		return p.ast.add_node(DECL_STMT_LIST, start_pos, p.current_pos(), list_ex);
	};
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
				advance(p)!;
				break;
			case "inout":
				mod = INOUT;
				advance(p)!;
				break;
			case "out":
				mod = OUT;
				advance(p)!;
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

	Node param_name;
	if (!p.is(IDENT) && 
		 !p.is(CT_IDENT) && 
		 !p.is(TYPE_IDENT) &&
		 !p.is(CT_TYPE_IDENT)) 
	{
		p.error("Expected parameter name after @param");
		p.push_invalid_node(p.current_pos());
	}
	else
	{
		// ident_expr
		param_name = parse_expr(p)!;
	}

	uint description;
	if (p.is(COLON))
	{
		description = p.pool.intern(p.current_text());
		advance(p)!;
	}
	else if (p.is(STRING))
	{
		p.error("Forgot colon after");
		p.push_invalid_node(p.current_pos());
	}

	uint[4] data = { (uint)param_name, description, (uint)flags, (uint)mod };
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(CONTRACT_PARAM, start, p.current_pos(), ex);
}

fn Node? parse_cond(Parser* p) => @with_scratch(; watermark)
{
	uint start_pos = p.current().pos;

	while (true)
	{
		if (p.is(TRY))
		{
			Node try_node = parse_try_unwrap_chain(p)!;
			scratch.push((uint)try_node);

			if (p.is(COMMA)) 
			{
				p.error("The 'try' must be placed last in the condition list.");
			}
			break; 
		}

		if (p.is(CATCH))
		{
			Node catch_node = parse_catch_unwrap(p)!;
			scratch.push((uint)catch_node);

			if (p.is(COMMA)) 
			{
				p.error("The 'catch' must be placed last in the condition list.");
			}
			break;
		}

		Node item = parse_decl_or_expr(p)!;
		scratch.push((uint)item);

		if (!consume(p, COMMA)!) break;
		if (p.eof()) break;
	}

	uint count = (uint)scratch.len() - watermark;
	uint ex = p.ast.push_extra_list(scratch_view(watermark, count));
	return p.ast.add_node(COND_EXPR, start_pos, p.previous_pos(), ex);
}

fn Node? parse_try_unwrap_chain(Parser* p) => @with_scratch(; watermark)
{
	uint start_pos = p.current_pos();

	Node first = parse_try_unwrap(p)!;
	scratch.push((uint)first);

	// Look for '&&' chains 
	while (consume(p, AND)!)
	{
		if (p.is(TRY))
		{
			// Another explicit 'try' (e.g., && try foo())
			scratch.push((uint)parse_try_unwrap(p)!);
		}
		else
		{
			// A regular expression in the chain (e.g., && bar == 2)
			scratch.push((uint)parse_expr(p)!);
		}
	}

	uint count = (uint)scratch.len() - watermark;
	uint ex = p.ast.push_extra_list(scratch_view(watermark, count));
	return p.ast.add_node(TRY_UNWRAP_CHAIN_EXPR, start_pos, p.previous_pos(), ex);
}

fn Node? parse_try_unwrap(Parser* p)
{
	uint pos = p.current_pos();
	expect(p, TRY)!;
	Node expr = parse_decl_or_expr(p)!;
	return p.ast.add_node(TRY_UNWRAP_EXPR, pos, p.previous_pos(), (uint)expr);
}

fn Node? parse_catch_unwrap(Parser* p) => @with_scratch(; watermark)
{
    uint start_pos = p.current_pos();
    advance(p)!; // consume 'catch'

    Node type_node;
    Node var_node;
    Node sub_expr = parse_expr(p)!;

    // Chain (catch expr1, expr2...)
    if (consume(p, COMMA)!)
    {
        scratch.push((uint)sub_expr);
        do 
		{
            scratch.push((uint)parse_expr(p)!);
        } 
		while (consume(p, COMMA)!);
        
        uint count = (uint)scratch.len() - watermark;
        uint ex = p.ast.push_extra_list(scratch_view(watermark, count));
        return p.ast.add_node(CATCH_UNWRAP_EXPR, start_pos, p.previous_pos(), ex);
    }

    if (p.ast.get_kind(sub_expr) == TYPE_EXPR) 
    {
        type_node = sub_expr;
        var_node = parse_expr(p)!;
    }
    else
    {
        var_node = sub_expr;
    }

    if (consume(p, EQ)!)
    {
        do 
		{
            scratch.push((uint)parse_expr(p)!);
        } 
		while (consume(p, COMMA)!);
    }

    uint count = (uint)scratch.len() - watermark;
    uint list_ex = p.ast.push_extra_list(scratch_view(watermark, count));
    
    uint[*] data = { (uint)type_node, (uint)var_node, list_ex };
    uint ex = p.ast.push_extra_block(&data);

    return p.ast.add_node(CATCH_UNWRAP_EXPR, start_pos, p.previous_pos(), ex);
}
