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
	@param [&inout] ctx
*>
fn Node? parse_path(ParseContext* ctx)
{
	uint start_pos = ctx.current_pos();

	if (!ctx.is(IDENT))
	{
		log::debug("not a valid path");
		return INVALID_PATH~;
	}

	@with_scratch(; watermark)
	{
		while (true)
		{
			Token t = ctx.current();
			
			uint sh = ctx.pool.intern(ctx.token_text(t));
			scratch.push(sh);
			
			advance(ctx)!;

			if (!consume(ctx, SCOPE)!) break;

			if (!is_some_ident(ctx.current().kind))
			{
				ctx.error("Expected identifier after '::'");
				return UNEXPECTED_TOKEN~;
			}
		}

		uint count = (uint)scratch.len() - watermark;
		uint[] parts = scratch_view(watermark, count);

		uint ex = ctx.ast.push_extra_list(parts);
		return ctx.ast.add_node(PATH, start_pos, ctx.current_pos(), ex);
	};
}

<*
 Parse an optional foo::bar::
 @param [&inout] ctx
*>
fn Node? parse_path_prefix(ParseContext* ctx)
{
	if (!is_some_ident(ctx.current().kind) && ctx.peek().kind != SCOPE)
	{
		return NOT_A_PATH~;
	}

	uint start_tok = ctx.current_pos();
	uint ex = 0;

	@with_scratch(; watermark) 
	{
		while (true) 
		{
			Token t = ctx.current();
			scratch.push((uint)ctx.pool.intern(ctx.token_text(t)));
			advance(ctx)!;

			if (ctx.is(SCOPE) && is_some_ident(ctx.peek().kind)) 
			{
				advance(ctx)!; // Consume '::'
			} 
			else 
			{
				break;
			}
		}

		ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};

	return ctx.ast.add_node(PATH, start_tok, ctx.current_pos(), ex);
}

<*
	TYPE_EXPR - unresolved type, parser only cares about the syntax
*>
fn Node? parse_type(ParseContext* ctx, ParseFlags parse_flags = { })
{
	uint start_tok = ctx.current_pos();
	uint name_or_path;
	Node base_expr;
	uint gen_args_list_ex;

	TypeFlags flags;
	uint ptr_count;
	Node array_size;

	if (ctx.is(CT_TYPEOF) || ctx.is(CT_TYPEFROM)) 
	{
		advance(ctx)!;
		expect(ctx, LPAREN)!;
		base_expr = parse_expr(ctx)!;
		expect(ctx, RPAREN)!;
		flags.is_comptime = true;
	} 
	else 
	{
		if (parse_flags.type_as_expression && ctx.peek().kind == SCOPE)
		{
			name_or_path = ctx.pool.intern(ctx.token_text(ctx.current()));
			advance(ctx)!;
		}
		else 
		{
			uint? path = (uint)parse_path_prefix(ctx);
			if (try path)
			{
				name_or_path = path;
			}
			else
			{
				name_or_path = ctx.pool.intern(ctx.token_text(ctx.current()));
				advance(ctx)!;
			}
		}

		if (!parse_flags.no_generics && consume(ctx, LBRACE)!) 
		{
			@with_scratch(; watermark) 
			{
				while (!ctx.is(RBRACE))
				{
					scratch.push((uint)parse_constant_expr(ctx)!);
					if (!consume(ctx, COMMA)!) break;
				}
				gen_args_list_ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
			};
			expect(ctx, RBRACE)!;
		}
	}

	while (true) 
	{
		// Vector <*4>
		if (consume(ctx, LVEC)!)
		{ 
			flags.is_vector = true;
			array_size = consume(ctx, ASTERISK)! ? 0 : parse_expr(ctx)!;
			expect(ctx, RVEC)!;
			continue; 
		}
		if (consume(ctx, ASTERISK)!) 
		{ 
			ptr_count++; continue; 
		}
		if (consume(ctx, QUESTION)!) 
		{
			flags.is_optional = true;
			continue; 
		}
		if (consume(ctx, LBRACKET)!) 
		{
			if (ctx.is(ASTERISK) || ctx.is(RBRACKET)) 
			{
				array_size = (Node)0;
				if (ctx.is(ASTERISK)) advance(ctx)!;
			} 
			else 
			{
				array_size = parse_expr(ctx)!;
			}

			expect(ctx, RBRACKET)!;
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

	uint ex = ctx.ast.push_extra_block(&header);
	return ctx.ast.add_node(TYPE_EXPR, start_tok, ctx.current_pos(), ex);
}

<*
	Parses Parameters
	@param [&inout] ctx
	@returns "Extra data index"
*>
fn Node? parse_parameter_list(ParseContext* ctx, ParseFlags flags = {}) => @with_scratch(; watermark)
{
	uint start_pos = ctx.current_pos();

	if (!flags.is_call && !flags.is_macro)
	{
		expect(ctx, LPAREN)!;
	}
	
	if (ctx.is(EOS))
	{
		return ctx.ast.add_empty(start_pos);
	}

	while (!ctx.is(RPAREN) && !ctx.eof())
	{
		Node param = parse_param_decl(ctx)!;
		scratch.push((uint)param);

		if (ctx.is(COMMA) || ctx.is(EOS))
		{
			advance(ctx)!;
			if (ctx.is(RPAREN)) break; 
		}
		else if (!ctx.is(RPAREN))
		{
			ctx.error("Expected ',' or ';' between parameters, found '%s'", ctx.token_text(ctx.current()));
			ctx.push_invalid_node(ctx.current_pos());
			ctx.skip_until({ RPAREN, EOS })!;
		}
	}

	if (!flags.is_call && !flags.is_macro)
	{
		expect(ctx, RPAREN)!;
	}
	uint count = (uint)scratch.len() - watermark;
	log::debug("Adding %s parameters", count);
	uint param_list = ctx.ast.push_extra_list(scratch_view(watermark, count));

	uint[*] data = views::@data{ParamsListViewFields}
	(
		PARAMS, param_list,
	);
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(PARAM_LIST, start_pos, ctx.current_pos(), ex);
}

<*
	implementing interfaces, e.g. struct Foo (MyInterface)

	INTERFACE_IMPL ::= '(' (type (',' type)* ','? )? ')'
	@param [&inout] ctx
*>
fn Node? parse_interface_impl(ParseContext* ctx)
{
    uint start_pos = ctx.current_pos();
    if (!consume(ctx, LPAREN)!) return {};
    // Handle empty list case: ()
    if (consume(ctx, RPAREN)!) return {};

    uint ex = 0;

    @with_scratch(; watermark)
    {
        while (true)
        {
            Node type_node = parse_type(ctx)!;
            scratch.push((uint)type_node);

            if (!consume(ctx, COMMA)!) break;
            if (ctx.is(RPAREN)) break;
        }

        uint count = (uint)scratch.len() - watermark;
        ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
    };

    expect(ctx, RPAREN)!;
    return ctx.ast.add_node(INTERFACE_IMPL, start_pos, ctx.current_pos(), ex);
}

<*
	Parses a sequence of attributes and returns an ATTRIBUTE_LIST node.
	@param [&inout] ctx
*>
fn Node? parse_attributes(ParseContext* ctx, bool comma_seperated = false)
{
	if (!ctx.is(AT_IDENT) && !ctx.is(AT_TYPE_IDENT)) return {};

	uint start_pos = ctx.current_pos();
	Node attribute_list_node;

	@with_scratch(; base_watermark)
	{
		while (ctx.is(AT_IDENT) || ctx.is(AT_TYPE_IDENT))
		{
			uint attr_start = ctx.current_pos();
			String attr_name = ctx.token_text(ctx.current());
			advance(ctx)!;

			uint args_list_ex = 0;

			AttributeKind attr_kind = common::get_attribute_from_string(attr_name);

			if (attr_kind == OPERATOR || attr_kind == OPERATOR_R || attr_kind == OPERATOR_S)
			{
				expect(ctx, LPAREN)!;

				if (consume(ctx, AMP)!)
				{
					if (consume(ctx, LBRACKET)!) expect(ctx, RBRACKET)!;
				}
				else if (consume(ctx, LBRACKET)!)
				{
					expect(ctx, RBRACKET)!;
					consume(ctx, EQ)!;
				}
				else
				{
					ctx.advance()!;
				}

				// TODO: Actually save the good op
				uint[1] single_arg = { 1 };
				args_list_ex = ctx.ast.push_extra_list(&single_arg);
				expect(ctx, RPAREN)!;
			}
			// Standard argument list @attr(arg1, arg2)
			else if (consume(ctx, LPAREN)!)
			{
				@with_scratch(; watermark)
				{
					while (!ctx.eof())
					{
						Node expr = parse_attribute_argument(ctx)!;
						if (expr.is_valid()) scratch.push((uint)expr);

						if (consume(ctx, RPAREN)!) break;
						expect(ctx, COMMA)!;
					}
					uint count = (uint)scratch.len() - watermark;
					args_list_ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
				};
			}
			// Short-hand string attribute @deprecated "message"
			else if (ctx.is(STRING))
			{
				Node msg_expr = parse_expr(ctx)!; 
				uint[1] single_arg = { (uint)msg_expr };
				args_list_ex = ctx.ast.push_extra_list(&single_arg);
			}

			uint[*] data = views::@data{AttributeViewFields}
			(
				KIND, attr_kind,
				ARGS, args_list_ex,
			);

			uint ex = ctx.ast.push_extra_block(&data);
			Node attr_node = ctx.ast.add_node(ATTRIBUTE, attr_start, ctx.previous_pos(), ex);
			scratch.push((uint)attr_node);

			// if comma_seperated, we need a comma to continue
			if (comma_seperated && !consume(ctx, COMMA)!) break;
		}

		// Wrap all found ATTRIBUTE nodes into one ATTRIBUTE_LIST
		uint total_attrs = (uint)scratch.len() - base_watermark;
		uint final_ex = ctx.ast.push_extra_list(scratch_view(base_watermark, total_attrs));

		uint[*] data = views::@data{AttributeListViewFields}
		(
			ATTRIBUTES, final_ex,
		);

		uint node_ex = ctx.ast.push_extra_block(&data);
		attribute_list_node = ctx.ast.add_node(ATTRIBUTE_LIST, start_pos, ctx.previous_pos(), node_ex);
	};

	return attribute_list_node;
}

fn Node? parse_attribute_argument(ParseContext* ctx) 
{
	Token curr = ctx.current();

	switch (curr.kind) 
	{
		case LBRACKET: // []  []=
			advance(ctx)!;
			expect(ctx, RBRACKET)!;
			OverloadKind kind = consume(ctx, EQ)! ? OverloadKind.ELEMENT_SET : OverloadKind.ELEMENT_AT;
			return ctx.ast.add_node(OP_OVERLOAD, curr.pos, ctx.current_pos(), (uint)kind);
		case AMP: // &[]
			if (ctx.peek(1).kind == LBRACKET) 
			{
				advance(ctx, 2)!;
				expect(ctx, RBRACKET)!;
				return ctx.ast.add_node(OP_OVERLOAD, curr.pos, ctx.current_pos(), (uint)OverloadKind.ELEMENT_REF);
			}
			else
			{
				advance(ctx)!;
				return ctx.ast.add_node(
						OP_OVERLOAD, 
						curr.pos, 
						ctx.current_pos(), 
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
			if (ctx.peek(1).kind == RPAREN || ctx.peek(1).kind == COMMA) 
			{
				Node n = ctx.ast.add_node(
					OP_OVERLOAD,
					curr.pos, 
					ctx.current_pos(), 
					(uint)get_overload_from_token(curr.kind));

				advance(ctx)!;
				return n;
			}
			return parse_expr(ctx)!;
		default:
			break;
	}

	return parse_expr(ctx)!;
}

<*
	Unified parser for:
	- Global variables (is_global)
	- Constants (is_const) 
*>
fn Node? parse_var_decl(ParseContext* ctx, ParseFlags flags)
{
	uint start_pos = ctx.current_pos();

	if (flags.is_local)
	{
		if (flags.is_extern)
		{
			ctx.error("a local variable cant have a extern modifier");
			return UNEXPECTED_TOKEN~;
		}

		if (flags.is_inline)
		{
			ctx.error("a local variable cant be inline");
			return UNEXPECTED_TOKEN~;
		}
	}

	Node type_node;

	if (flags.is_var)
	{
		advance(ctx)!;
		type_node = ctx.ast.add_empty(ctx.current_pos());
	}

	if (is_type(ctx) && is_declaration_followup(ctx))
	{
		type_node = parse_type(ctx)!;
	}

	// if it is const, the type node is optional
	if (flags.is_const && !type_node.is_valid())
	{
		type_node = ctx.ast.add_empty(ctx.current_pos());
	}

	@with_scratch(; watermark)
	{
		while (true)
		{
			Token t = ctx.current();
			if (flags.is_const && t.kind != CONST_IDENT)
			{
				ctx.error("Constants must use a CONST_IDENT, found '%s'", ctx.token_text(t));
				return { };
			}
			if (!flags.is_const && t.kind != IDENT && !flags.is_local)
			{
				ctx.error("Global variables must use lower-case IDENT, found '%s'", ctx.token_text(t));
				return { };
			}

			uint name = ctx.pool.intern(ctx.token_text(t));
			advance(ctx)!;

			Node attr = parse_attributes(ctx)!;
			Node init_expr;

			if (consume(ctx, EQ)!)
			{
				if ((uint)scratch.len() > watermark)
				{
					ctx.error("Initializers are not allowed in multi-declarations");
					return UNEXPECTED_TOKEN~;
				}

				if (flags.is_extern)
				{
					ctx.error("a extern global cant have a initializer");
					return UNEXPECTED_TOKEN~;
				}
				init_expr = parse_expr(ctx)!;
			}
			else if (flags.is_const && !flags.is_extern)
			{
				ctx.error("Constants must be initialized");
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

			uint var_ex = ctx.ast.push_extra_block(&var_data);
			Node var_node = ctx.ast.add_node(VAR_DECL, t.pos, ctx.current_pos(), var_ex);
			scratch.push((uint)var_node);

			if (flags.is_expr) break;

			if (!consume(ctx, COMMA)!) break;
		}

		if (!flags.skip_eos)
		{
			expect(ctx, EOS)!;
		}

		uint count = (uint)scratch.len() - watermark;

		if (count == 1) 
		{
			return (Node)scratch.pop();
		}

		uint list_ex = ctx.ast.push_extra_list(scratch_view(watermark, count));

		uint[*] list_header = { list_ex };
		uint final_ex = ctx.ast.push_extra_block(&list_header);
		return ctx.ast.add_node(VAR_DECL_LIST, start_pos, ctx.current_pos(), final_ex);
	}; 
}	

fn Node? parse_local(ParseContext* ctx, uint start_pos, Node type_node, ParseFlags flags = {})
{
	if (!type_node.is_valid())
	{
		type_node = parse_type(ctx)!;
	}

	@with_scratch(; watermark)
	{
		while (true)
		{
			Token name_tok = ctx.current();
			advance(ctx)!;

			Node init;
			if (consume(ctx, EQ)!) 
			{
				init = parse_expr(ctx)!;
			}

			Node attr = parse_attributes(ctx)!;

			// Create the individual LOCAL_DECL
			uint name_sh = ctx.pool.intern(ctx.token_text(name_tok));

			uint[*] data = views::@data{LocalViewFields}
			(
				NAME, name_sh,
				TYPE, type_node,
				INIT, init,
				ATTRIBUTES, attr,
			);

			uint ex = ctx.ast.push_extra_list(&data);
			Node decl = ctx.ast.add_node(LOCAL_DECL, name_tok.pos, ctx.current_pos(), ex);

			scratch.push((uint)decl);

			if (init.is_valid()) break;
			if (!consume(ctx, COMMA)!) break;
		}

		expect(ctx, EOS)!;

		uint count = (uint)scratch.len() - watermark;

		// If just one, return the LOCAL_DECL directly (no wrapper)
		if (count == 1) return (Node)scratch.pop();

		// If multiple, wrap in a container
		uint list_ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
		return ctx.ast.add_node(DECL_STMT_LIST, start_pos, ctx.current_pos(), list_ex);
	};
}

fn Node? parse_contract_param(ParseContext* ctx)
{
	uint start = ctx.current_pos();

	ContractParamFlags flags;
	InOutModifier mod;

	if (consume(ctx, LBRACKET)!)
	{
		flags.is_ref = consume(ctx, AMP)!;
		String modifer_name = ctx.current_text();
		switch (modifer_name)
		{
			case "in":
				mod = IN;
				advance(ctx)!;
				break;
			case "inout":
				mod = INOUT;
				advance(ctx)!;
				break;
			case "out":
				mod = OUT;
				advance(ctx)!;
				break;
			default:
				ctx.error("'in', 'out' or 'inout' expected");
				ctx.push_invalid_node(ctx.current_pos());
		}

		if (!consume(ctx, RBRACKET)!)
		{
			ctx.error("Expected a closing ']'");
			ctx.push_invalid_node(ctx.current_pos());
		}
	}

	Node param_name;
	if (!ctx.is(IDENT) && 
		 !ctx.is(CT_IDENT) && 
		 !ctx.is(TYPE_IDENT) &&
		 !ctx.is(CT_TYPE_IDENT)) 
	{
		ctx.error("Expected parameter name after @param");
		ctx.push_invalid_node(ctx.current_pos());
	}
	else
	{
		// ident_expr
		param_name = parse_expr(ctx)!;
	}

	uint description;
	if (ctx.is(COLON))
	{
		description = ctx.pool.intern(ctx.current_text());
		advance(ctx)!;
	}
	else if (ctx.is(STRING))
	{
		ctx.error("Forgot colon after");
		ctx.push_invalid_node(ctx.current_pos());
	}

	uint[4] data = { (uint)param_name, description, (uint)flags, (uint)mod };
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(CONTRACT_PARAM, start, ctx.current_pos(), ex);
}

fn Node? parse_cond(ParseContext* ctx) => @with_scratch(; watermark)
{
	uint start_pos = ctx.current().pos;

	while (true)
	{
		if (ctx.is(TRY))
		{
			Node try_node = parse_try_unwrap_chain(ctx)!;
			scratch.push((uint)try_node);

			if (ctx.is(COMMA)) 
			{
				ctx.error("The 'try' must be placed last in the condition list.");
			}
			break; 
		}

		if (ctx.is(CATCH))
		{
			Node catch_node = parse_catch_unwrap(ctx)!;
			scratch.push((uint)catch_node);

			if (ctx.is(COMMA)) 
			{
				ctx.error("The 'catch' must be placed last in the condition list.");
			}
			break;
		}

		Node item = parse_decl_or_expr(ctx)!;
		scratch.push((uint)item);

		if (!consume(ctx, COMMA)!) break;
		if (ctx.eof()) break;
	}

	uint count = (uint)scratch.len() - watermark;
	uint ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
	return ctx.ast.add_node(COND_EXPR, start_pos, ctx.previous_pos(), ex);
}

fn Node? parse_try_unwrap_chain(ParseContext* ctx) => @with_scratch(; watermark)
{
	uint start_pos = ctx.current_pos();

	Node first = parse_try_unwrap(ctx)!;
	scratch.push((uint)first);

	// Look for '&&' chains 
	while (consume(ctx, AND)!)
	{
		if (ctx.is(TRY))
		{
			// Another explicit 'try' (e.g., && try foo())
			scratch.push((uint)parse_try_unwrap(ctx)!);
		}
		else
		{
			// A regular expression in the chain (e.g., && bar == 2)
			scratch.push((uint)parse_expr(ctx)!);
		}
	}

	uint count = (uint)scratch.len() - watermark;
	uint ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
	return ctx.ast.add_node(TRY_UNWRAP_CHAIN_EXPR, start_pos, ctx.previous_pos(), ex);
}

fn Node? parse_try_unwrap(ParseContext* ctx)
{
	uint pos = ctx.current_pos();
	expect(ctx, TRY)!;
	Node expr = parse_decl_or_expr(ctx)!;
	return ctx.ast.add_node(TRY_UNWRAP_EXPR, pos, ctx.previous_pos(), (uint)expr);
}

fn Node? parse_catch_unwrap(ParseContext* ctx) => @with_scratch(; watermark)
{
    uint start_pos = ctx.current_pos();
    advance(ctx)!; // consume 'catch'

    Node type_node;
    Node var_node;
    Node sub_expr = parse_expr(ctx)!;

    // Chain (catch expr1, expr2...)
    if (consume(ctx, COMMA)!)
    {
        scratch.push((uint)sub_expr);
        do 
		{
            scratch.push((uint)parse_expr(ctx)!);
        } 
		while (consume(ctx, COMMA)!);
        
        uint count = (uint)scratch.len() - watermark;
        uint ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
        return ctx.ast.add_node(CATCH_UNWRAP_EXPR, start_pos, ctx.previous_pos(), ex);
    }

    if (ctx.ast.get_kind(sub_expr) == TYPE_EXPR) 
    {
        type_node = sub_expr;
        var_node = parse_expr(ctx)!;
    }
    else
    {
        var_node = sub_expr;
    }

    if (consume(ctx, EQ)!)
    {
        do 
		{
            scratch.push((uint)parse_expr(ctx)!);
        } 
		while (consume(ctx, COMMA)!);
    }

    uint count = (uint)scratch.len() - watermark;
    uint list_ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
    
    uint[*] data = { (uint)type_node, (uint)var_node, list_ex };
    uint ex = ctx.ast.push_extra_block(&data);

    return ctx.ast.add_node(CATCH_UNWRAP_EXPR, start_pos, ctx.previous_pos(), ex);
}
