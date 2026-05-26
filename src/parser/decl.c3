module c3_parser::parser;
import c3_parser::ast;
import lexer;
import string_pool;

import c3_parser::common;
import c3_parser::constants;
import c3_parser::registry;
import std::collections::list;
import c3_parser::workspace @norecurse;
import std::io;

fn Node? parse_contract(ParseContext* ctx) => @pool()
{
	if (!ctx.is(CONTRACT))
	{
		ctx.error("Expected a contract start here.");
		return UNEXPECTED_TOKEN~;
	}

	Token contract_start_tok = ctx.current(); 
	uint global_offset = contract_start_tok.pos;	

	Token t = ctx.current();
	String slice = ctx.src[(Size)t.pos:t.len];

	// skip the contract for the parser
	advance(ctx)!;

	// store the "normal" tokens and index temporarly since
	// we need to swap them
	Token[] main_tokens = ctx.tokens;
	uint main_index = ctx.pos;
	defer
	{
		ctx.tokens = main_tokens;
		ctx.pos = main_index;
	}

	List{Token} contract_tokens;
	contract_tokens.tinit();

	ContractLexer cl; cl.init(slice);

	while (try next = cl.next())
	{
		// make return a identifier so the it can be parsed as expr
		if (next.kind == RETURN)
		{
			next.kind = IDENT;
		} 

		next.pos += global_offset;
		contract_tokens.push(next);

		log::debug("ContractLexer - added: %s", next.kind);
	}

	contract_tokens.push({ .kind = EOF, .pos = (contract_tokens.last().pos + contract_tokens.last().len) ?? 0, .len = 0 });

	ctx.tokens = contract_tokens.array_view();
	ctx.pos = 0;

	List{uint} ensures;  ensures.tinit();
	List{uint} requires; requires.tinit();
	List{uint} params;   params.tinit();
	List{uint} returns;  returns.tinit();
	ContractFlags flags;
	uint deprecated;
	uint return_desc;

	while (!ctx.eof())
	{
		String attr = ctx.token_text(ctx.current());
		log::debug("parse_contract - attribute = %s", attr);

		if (consume(ctx, AT_IDENT)!)
		{
			if (attr == constants::KW_AT_REQUIRE)
			{
				requires.push((uint)parse_contract_expr(ctx, false)!);
			}
			else if (attr == constants::KW_AT_ENSURE)
			{
				ensures.push((uint)parse_contract_expr(ctx, true)!);
			}
			else if (attr == constants::KW_AT_PARAM)
			{
				params.push((uint)parse_contract_param(ctx))!;
			}
			else if (attr == constants::KW_AT_DEPRECATED)
			{
				deprecated = (uint)parse_attributes(ctx)!;
			}
			else if (attr == constants::KW_AT_PURE)
			{
				flags.is_pure = true;
			}
			else if (attr == constants::KW_AT_RETURN)
			{
				if (ctx.is(QUESTION))
				{
					advance(ctx)!;
					while (!ctx.eof())
					{
						returns.push((uint)parse_expr(ctx)!);
						if (!consume(ctx, COMMA)!)
						{
							break;
						}
					}
				}
				else
				{	
					return_desc = (uint)parse_expr(ctx)!;
				}
			}
			else
			{
				if (catch advance(ctx)) break;
			}
		}
		else
		{
			if (catch advance(ctx)) break;
		}
	}

	uint req_idx = ctx.ast.push_extra_list(requires.array_view());
	uint ens_idx = ctx.ast.push_extra_list(ensures.array_view());
	uint params_idx = ctx.ast.push_extra_list(params.array_view());
	uint returns_idx = ctx.ast.push_extra_list(returns.array_view());

	uint[*] final_data = views::@data{ContractViewFields}
	(
	 REQUIRES, req_idx, 
	 ENSURES, ens_idx, 
	 PARAMS, params_idx, 
	 OPTIONAL_RETURNS, returns_idx, 
	 RETURN, return_desc, 
	 FLAGS, flags, 
	 DEPRECATED, deprecated 
	);

	uint ex = ctx.ast.push_extra_block(&final_data);
	return ctx.ast.add_node(CONTRACT_DECL, 0, ctx.current_pos(), ex);
}

fn Node? parse_module(ParseContext* ctx, Workspace* ws)
{
	uint node_idx = ctx.ast.len();
	uint start = ctx.current_pos();
	expect(ctx, MODULE)!;

	Node? path = parse_path(ctx)!;

	if (catch err = path)
	{
		ctx.error("Failed to parse path for module: %s", err);
		return err~;
	}

	if (try ModuleSection* last_sec = ctx.sf.sections.last())
	{
		last_sec.end_node_idx = node_idx;
	}

	PathView view = { ctx.ast, path };
	String mod_name = view.get_full(ctx.pool);

	Module* mod = ws.get_or_create_module(mod_name);
	ModuleSection* sec = ws.get_or_create_section(mod, ctx.sf);
	ctx.mod = mod;
	sec.start_node_idx = node_idx;

	Node generics = parse_generic_decl(ctx)!;
	Node attributes = parse_attributes(ctx)!;

	expect(ctx, EOS)!;

	log::debug("parsed module: %s", mod_name);

	// last is to reserve for contract (if any)
	uint[*] data = views::@data{ModuleViewFields}
	(
		PATH, path, 
		GENERICS, generics, 
		ATTRIBUTES, attributes, 
		CONTRACT, 0
	);
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(MODULE_DECL, start, ctx.current_pos(), ex);
}

fn Node? parse_enum(ParseContext* ctx, ParseFlags flags)
{
	uint start_tok = ctx.current_pos();

	if (flags.is_constdef) 
	{
		expect(ctx, CONSTDEF)!;
	} 
	else 
	{
		expect(ctx, ENUM)!;
	}

	uint name;
	if (ctx.is(TYPE_IDENT)) 
	{
		name = ctx.pool.intern(ctx.token_text(ctx.current()));
		advance(ctx)!;
	} 
	else 
	{
		ctx.error("Expected type identifier for enum name");
		ctx.push_invalid_node(ctx.previous_pos());
		ctx.skip_until({ COLON, LPAREN, LBRACE, EOS })!;
	}

	Node base_type;
	bool is_inline_type = false;
	if (consume(ctx, COLON)!) 
	{
		if (consume(ctx, INLINE)!) is_inline_type = true;
		if (ctx.is(LPAREN)) // if it is LPAREN, then there are no base types
		{
			base_type = ctx.ast.add_empty(ctx.current_pos());
		}
		else
		{
			base_type = parse_type(ctx, { .no_generics = true }) ?? ctx.ast.add_empty(ctx.current_pos());
		}
	}

	Node params = ctx.is(LPAREN) ? parse_parameter_list(ctx)! : {};
	Node attrs = parse_attributes(ctx)!;

	uint elements_ex = 0;
	if (consume(ctx, LBRACE)!) 
	{
		@with_scratch(; watermark)
		{
			while (!ctx.is(RBRACE) && !ctx.eof())
			{
				consume(ctx, CONTRACT)!;
				if (!ctx.is(CONST_IDENT)) 
				{
					ctx.error("Expected enum member name");
					ctx.push_invalid_node(ctx.previous_pos());
					ctx.skip_until({ COMMA, RBRACE })!;
					if (consume(ctx, COMMA)!) continue;
					break;
				}

				Token elem_tok = ctx.current();
				uint elem_name = ctx.pool.intern(ctx.token_text(elem_tok));
				advance(ctx)!;
				Node el_attrs = parse_attributes(ctx)!;

				Node explicit_val = consume(ctx, EQ)! ? (parse_expr(ctx)!) : 0;
				Node assoc_init = ctx.is(LBRACE) ? (parse_initializer_list(ctx)!) : 0;

				uint[*] member_data = views::@data{EnumMemberViewFields}
				(
				 NAME, elem_name, 
				 ATTRIBUTES, el_attrs,
				 EXPLICIT_VALUE, explicit_val, 
				 ASSOCIATED, assoc_init,
				);
				uint m_ex = ctx.ast.push_extra_block(&member_data);

				scratch.push((uint)ctx.ast.add_node(ENUM_MEMBER, elem_tok.pos, ctx.previous_pos(), m_ex));

				if (!consume(ctx, COMMA)!) break;
			}

			elements_ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
		};
		expect(ctx, RBRACE)!;
	}
	else
	{
		elements_ex = ctx.ast.push_extra_list({});
	}

	// TODO: bitstruct
	uint packed_flags = 0;
	if (flags.is_constdef) packed_flags |= (1 << 0);
	if (is_inline_type)	packed_flags |= (1 << 1);

	uint[*] decl_data = views::@data{EnumViewFields}
	( 
		NAME, name, 
		BASE_TYPE, base_type, 
		PARAMS, params, 
		ATTRIBUTES, attrs,
		CONTRACT, 0,
		MEMBERS, elements_ex, 
		FLAGS, packed_flags 
	);
	uint ex = ctx.ast.push_extra_block(&decl_data);
	return ctx.ast.add_node(ENUM_DECL, start_tok, ctx.current_pos(), ex);
}

<*
	FAULTDEF_DECL ::= FAULTDEF CONST_IDENT (',' CONST_IDENT)* ','? ';'
*>
fn Node? parse_faultdef_decl(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, FAULTDEF)!;

	uint fault_list_idx = 0;

	@with_scratch(; watermark)
	{
		while (!ctx.is(EOS) && !ctx.eof())
		{
			Token name_tok = ctx.current();
			expect(ctx, CONST_IDENT)!;
			uint name_sh = ctx.pool.intern(ctx.token_text(name_tok));
			scratch.push(name_sh);

			if (!consume(ctx, COMMA)!) break;
		}

		uint count = (uint)scratch.len() - watermark;
		if (count > 0)
		{
			fault_list_idx = ctx.ast.push_extra_list(scratch_view(watermark, count));
		}
	};

	Node attrs = parse_attributes(ctx)!;

	expect(ctx, EOS)!;

	uint[*] data = views::@data{FaultdefDeclViewFields}
	(
		FAULTS, fault_list_idx,
		ATTRIBUTES, attrs
	);

	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(FAULTDEF_DECL, start_tok, ctx.current_pos(), ex);
}

fn Node? parse_fn_decl(ParseContext* ctx, ParseFlags flags) => @scratch()
{
	uint start_tok = ctx.current_pos();
	expect(ctx, FN)!;
	log::debug("parse_fn_decl - parse_type");
	Node ret_type = parse_type(ctx)!;

	uint name; // name of fn
	Node method_type; // if a method, the struct it belongs to, dont know what else to call it? class maybe? xD
	if (is_type(ctx))
	{
		method_type = parse_type(ctx)!;
		expect(ctx, DOT)!;
		if (!ctx.is(IDENT))
		{
			ctx.error("Expected member fn name");
			return UNEXPECTED_TOKEN~;
		}
		name = ctx.pool.intern(ctx.token_text(ctx.current()));
		advance(ctx)!;
	}
	else
	{
		if (!ctx.is(IDENT))
		{
			ctx.error("Expected fn name");
			return UNEXPECTED_TOKEN~;
		}

		name = ctx.pool.intern(ctx.token_text(ctx.current()));
		log::debug(ctx.pool.get((StringHandle)name));
		advance(ctx)!;
	}

	log::debug("parse_fn_decl - %s", ctx.pool.get((StringHandle)name));

	Node params = parse_parameter_list(ctx)!;

	log::debug("parse_fn_decl - parse_generics");
	Node type_params = parse_generic_decl(ctx)!;

	log::debug("parse_fn_decl - parse_attributes");
	Node attr = parse_attributes(ctx)!;

	Node body;
	if (ctx.is(LBRACE))
	{
		if (flags.is_extern)
		{
			ctx.error("extern functions cant have a body");
			return UNEXPECTED_TOKEN~;
		}

		log::debug("parse_fn_decl - parse_compound");
		body = parse_compound(ctx)!;
	}
	else if (consume(ctx, IMPLIES)!) // Handle the => syntax
	{
		if (flags.is_extern)
		{
			ctx.error("extern functions cant have a body");
			return UNEXPECTED_TOKEN~;
		}

		log::debug("parse_fn_decl - parse_short_body");
		body = parse_expr(ctx)!;

		if (!node_ends_with_block(ctx, body))
		{
			expect(ctx, EOS)!;
		}
	}
	else
	{
		expect(ctx, EOS)!;
	}

	uint[*] final_block = views::@data{FnViewFields}
	(
		NAME, name,
		ASSOCIATED, method_type,
		RETURN_TYPE, ret_type,
		ATTRIBUTES, attr,
		PARAMS, params,
		GENERICS, type_params,
		CONTRACT, 0,
		BODY, body,
	);

	log::debug("parse_fn_decl - finished.. adding to ast");
	uint ex = ctx.ast.push_extra_block(&final_block);
	return ctx.ast.add_node(FN_DECL, start_tok, ctx.current_pos(), ex);
}

fn Node? parse_function_type(ParseContext* ctx)
{
	uint pos = ctx.current().pos;
	expect(ctx, FN)!;

	Node return_type = parse_type(ctx)!;

	Node params = parse_parameter_list(ctx)!;

	uint[*] data = views::@data{FnTypeViewFields}
	( 
		RETURN_TYPE, return_type, 
		PARAMS, (uint)params 
	);
	uint ex = ctx.ast.push_extra_list(&data);
	return ctx.ast.add_node(TYPE_FUNCTION, pos, ctx.current_pos(), ex);
}

fn Node? parse_macro_decl(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, MACRO)!;

	Node rtype;
	Node method_type;
	uint name;

	if IF: ((ctx.is(IDENT) || ctx.is(AT_IDENT)) && ctx.peek(1).kind != DOT)
	{
		name = ctx.pool.intern(ctx.token_text(ctx.current()));
		advance(ctx)!;
	}
	else
	{
		rtype = parse_type(ctx)!;

		if (!ctx.is(DOT) && !ctx.is(IDENT) && !ctx.is(AT_IDENT))
		{
			method_type = parse_type(ctx)!;
		}

		if (consume(ctx, DOT)!)
		{
			if (!method_type.is_valid())
			{
				method_type = rtype;
				rtype = { };
			}
		}

		if (!ctx.is(IDENT) && !ctx.is(AT_IDENT))
		{
			ctx.error("Expected macro name");
			ctx.push_invalid_node(ctx.current_pos());
			ctx.skip_until({ LPAREN, LBRACE, EOS })!;
			break IF;
		}

		name = ctx.pool.intern(ctx.token_text(ctx.current()));
		advance(ctx)!;
	}

	Node params = ctx.is(LPAREN) ? parse_macro_params(ctx)! : {};
	Node type_params = parse_generic_decl(ctx)!;
	Node attr = parse_attributes(ctx)!;

	Node body;
	if (consume(ctx, IMPLIES)!)
	{
		body = parse_expr(ctx)!;

		if (!node_ends_with_block(ctx, body))
		{
			expect(ctx, EOS)!;
		}
	}
	else if (ctx.is(LBRACE))
	{
		body = parse_statement(ctx)!;
	}
	else
	{
		expect(ctx, EOS)!;
	}

	uint[*] data = views::@data{MacroViewFields}
	(
		NAME, name,
		ASSOCIATED, method_type, 
		RETURN_TYPE, rtype, 
		ATTRIBUTES, attr, 
		PARAMS, params, 
		GENERICS, type_params,
		CONTRACT, 0,
		BODY, body,
	);

	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(MACRO_DECL, start_tok, ctx.current_pos(), ex);
}

fn Node? parse_macro_params(ParseContext* ctx)
{
	uint start_pos = ctx.current_pos();
	expect(ctx, LPAREN)!;

    // Parse the "regular" parameters (before eos)
    Node params = parse_parameter_list(ctx, { .is_macro = true, .skip_eos = true })!;
    Node body_param;
    
    if (consume(ctx, EOS)!)
    {
        uint start = ctx.current_pos();
        
        // This MUST be the @body part
        if (!ctx.is(AT_IDENT)) 
		{
            ctx.error("Expected @body after ';'");
            body_param = ctx.push_invalid_node(ctx.current_pos());
			ctx.skip_until({ RPAREN, EOS })!;
        }
        
        uint body_name = ctx.pool.intern(ctx.token_text(ctx.current()));
        advance(ctx)!; // Consume @ident

        Node inner_params;
        if (consume(ctx, LPAREN)!)
        {
            // Parse the parameters INSIDE the @ident(...)
            inner_params = parse_parameter_list(ctx, { .is_call = false, .is_macro = true })!;
            expect(ctx, RPAREN)!;
        }

		uint[*] data = views::@data{BodyParamViewFields}
		(
			NAME, body_name,
			INNER_PARAMS, inner_params,
		);
        
		uint ex = ctx.ast.push_extra_block(&data);
        body_param = ctx.ast.add_node(BODY_PARAM_DECL, start, ctx.current_pos(), ex);
    }

    expect(ctx, RPAREN)!;

	uint[*] data = views::@data{MacroParamsViewFields}
	(
		PARAMS, params,
		BODY_PARAMS, body_param,
	);
    
    uint ex = ctx.ast.push_extra_block(&data);
    return ctx.ast.add_node(MACRO_PARAMS, start_pos, ctx.current_pos(), ex);
}

fn Node? parse_param_decl(ParseContext* ctx)
{
	uint start = ctx.current_pos();
	uint name;
	Node type;
	Node init;
	uint flags;

	if (ctx.is(AT_IDENT))
	{
		name = ctx.pool.intern(ctx.current_text());
		advance(ctx)!;

		Node inner_params;
		if (consume(ctx, LPAREN)!)
		{
			inner_params = parse_parameter_list(ctx, { .is_macro = true })!;
			expect(ctx, RPAREN)!;
		}

		uint[*] data = views::@data{BodyParamViewFields}
		(
			NAME, name,
			INNER_PARAMS, inner_params
		);
		uint ex = ctx.ast.push_extra_block(&data);
		return ctx.ast.add_node(BODY_PARAM_DECL, start, ctx.current_pos(), ex);
	}

	if (consume(ctx, AMP)!) flags |= 2;
	bool ellipsis_prefix = consume(ctx, ELLIPSIS)!;

	if (is_type(ctx) || ctx.is(CT_TYPE_IDENT))
	{
		type = parse_type(ctx)!;
		// Check for "Type..."
		if (consume(ctx, ELLIPSIS)!) flags |= 1;
	}

	TokenKind k = ctx.current().kind;
	if (is_non_type_ident(k) || k == CT_TYPE_IDENT || k == CT_IDENT || k == HASH_IDENT)
	{
		name = ctx.pool.intern(ctx.token_text(ctx.current()));
		advance(ctx)!;

		// Check for "name..."
		if (consume(ctx, ELLIPSIS)!) flags |= 1;
	}

	Node attributes;
	if (ctx.is(AT_IDENT))
	{
		attributes = parse_attributes(ctx)!;
	}

	if (consume(ctx, EQ)!)
	{
		if (ctx.is(ELLIPSIS))
		{
			Token ellipsis_tok = ctx.peek();
			advance(ctx)!;
			init = ctx.ast.add_node(DEFAULT_ELLIPSIS, ellipsis_tok.pos, ctx.current_pos(), 0);
		}
		else
		{
			init = parse_expr(ctx)!;
		}
	}

	if (!type.is_valid() && name == 0 && !attributes.is_valid() && !ellipsis_prefix)
	{
		ctx.error("Expected parameter declaration");
		ctx.push_invalid_node(start);
	}

	uint[*] data = views::@data{ParamViewFields}
	( 
		NAME, name,
		TYPE, type,
		INIT, init,
		FLAGS, flags,
	);
	uint ex = ctx.ast.push_extra_block(&data);

	return ctx.ast.add_node(PARAM_DECL, start, ctx.current_pos(), ex);
}

<*
 TYPE_ALIAS_DECL ::= ALIAS TYPE_IDENT attributes? '=' typedef_type ';'
    TYPE_ALIAS_DECL ::= func_typedef | type generic_params?
*>
fn Node? parse_type_alias(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, ALIAS)!;

	Token name_tok = ctx.current();

	if (!ctx.is(TYPE_IDENT))
	{
		ctx.error("Expected Type identifier");
		return UNEXPECTED_TOKEN~;
	}

	expect(ctx, TYPE_IDENT)!;
	uint name_sh = ctx.pool.intern(ctx.token_text(name_tok));

	Node generics = parse_generic_decl(ctx)!;
	Node attr = parse_attributes(ctx)!;

	expect(ctx, EQ)!;

	Node target_type;
	if (ctx.is(FN))
	{
		target_type = parse_function_type(ctx)!;
	}
	else
	{
		target_type = parse_expr(ctx)!;
	}

	uint end_tok = ctx.current_pos();
	expect(ctx, EOS)!;

	Node type_attr = parse_attributes(ctx)!;

	uint[*] data = views::@data{TypeAliasViewFields}
	( 
		NAME, name_sh, 
		TARGET_TYPE, target_type, 
		GENERICS, generics,
		ATTRIBUTES, attr,
		TYPE_ATTRIBUTES, type_attr,
	);
	uint ex = ctx.ast.push_extra_list(&data);

	return ctx.ast.add_node(TYPE_ALIAS_DECL, start_tok, end_tok, ex);
}

<*
 	PATH_ALIAS_DECL ::= 'alias' (IDENT | CONST_IDENT | AT_IDENT) attributes? '=' (('module' path) | identifier_alias generic_params?)
    ALIAS_DECL ::= path? (IDENT | CONST_IDENT | AT_IDENT)
*>
fn Node? parse_ident_alias(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, ALIAS)!;

	TokenKind kind = ctx.current().kind;
	if (kind != IDENT && kind != CONST_IDENT && kind != AT_IDENT)
	{
		ctx.error("A type, variable, constant or attribute name was expected");
		return UNEXPECTED_TOKEN~;
	}

	uint name = ctx.pool.intern(ctx.token_text(ctx.current()));

	advance(ctx)!;

	Node attr = parse_attributes(ctx)!;

	expect(ctx, EQ)!;

	if (ctx.is(MODULE))
	{
		advance(ctx)!; // skip module

		Node path = parse_path(ctx)!;

		uint[*] data = views::@data{PathAliasViewFields}
		( 
		 NAME, name, 
		 PATH, path, 
		 ATTRIBUTES, attr,
		);
		uint ex = ctx.ast.push_extra_block(&data);

		return ctx.ast.add_node(PATH_ALIAS_DECL, start_tok, ctx.current_pos(), ex);
	}

	Node expr = parse_expr(ctx)!;

	expect(ctx, EOS)!;

	uint[*] data = views::@data{ExprAliasViewFields}
	( 
		NAME, name, 
		EXPR, expr, 
		ATTRIBUTES, attr,
	);
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(ALIAS_DECL, start_tok, ctx.current_pos(), ex);
}

fn Node? parse_alias(ParseContext* ctx)
{
	switch (ctx.peek(1).kind)
	{
		case TYPE_IDENT:
			return parse_type_alias(ctx);
		default:
			return parse_ident_alias(ctx);
	}
}

<*
	GENERIC_DECL ::= <...>
*>
fn Node? parse_generic_decl(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	if (!consume(ctx, LESS)!) return {};
	if (consume(ctx, GREATER)!)
	{
		ctx.error("Generic paramter list cannot be empty");
	}

	uint list;
	@with_scratch(; watermark)
	{
		while (true)
		{
			switch (ctx.current().kind)
			{
				case TYPE_IDENT:
				case CONST_IDENT:
					break;
				case COMMA:
					ctx.error("Unexpected ','");
					return {};
				case IDENT:
				case CT_IDENT:
				case CT_TYPE_IDENT:
					ctx.error("The generic parameter cannot be a $-prefixed name.");
					return {};
				default:
					ctx.error("Only generic parameters are allowed here.");
					return {};
			}

			uint name = ctx.pool.intern(ctx.current_text());
			scratch.push(name);
			advance(ctx)!;
			if (!consume(ctx, COMMA)!)
			{
				expect(ctx, GREATER)!;
				break;
			}
		}

		list = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};

	uint[*] data = views::@data{GenericDeclViewFields}
	(
		PARAMETERS, list 
	);
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(GENERIC_DECL, start_tok, ctx.current_pos(), ex);
}

<*
	TYPEDEF_DECL ::= 'typedef' TYPE_IDENT opt_interfaces attributes? '=' 'inline'? type ';'
*>
fn Node? parse_typedef(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, TYPEDEF)!;

	Token name_tok = ctx.current();
	expect(ctx, TYPE_IDENT)!;
	uint name_sh = ctx.pool.intern(ctx.token_text(name_tok));

	Node inter = parse_interface_impl(ctx)!;
	Node generics = parse_generic_decl(ctx)!;
	Node attr = parse_attributes(ctx)!;
	expect(ctx, EQ)!;

	if (consume(ctx, INLINE)!)
	{
		// TODO:
	}

	Node base_type = parse_type(ctx)!;
	Node type_attr = parse_attributes(ctx)!;
	uint end_tok = ctx.current_pos();
	expect(ctx, EOS)!;

	uint[*] data = views::@data{TypedefViewFields}
	(
		NAME, name_sh, 
		BASE_TYPE, base_type, 
		ATTRIBUTES, attr,
		INTERFACES, inter,
		GENERICS, generics,
		TYPE_ATTRIBUTES, type_attr,
	);
	uint ex = ctx.ast.push_extra_block(&data);

	return ctx.ast.add_node(TYPEDEF_DECL, start_tok, end_tok, ex);
}

<*
	TYPEDEF_DECL ::= 'typedef' TYPE_IDENT opt_interfaces attributes? '=' 'inline'? type ';'
*>
fn Node? parse_attrdef(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, ATTRDEF)!;

	Token name_tok = ctx.current();
	expect(ctx, AT_TYPE_IDENT)!;
	uint name_sh = ctx.pool.intern(ctx.token_text(name_tok));

	Node params;
	if (ctx.is(LPAREN))
	{
		params = parse_parameter_list(ctx)!;
	}
	else
	{
		params = ctx.ast.add_empty(ctx.current_pos());
	}
	Node attr = parse_attributes(ctx)!;
	expect(ctx, EQ)!;

	Node val_attrs = parse_attributes(ctx, comma_seperated: true)!;
	uint end_tok = ctx.current_pos();
	expect(ctx, EOS)!;

	uint[*] data = views::@data{AttrdefViewFields}
	(
		NAME, name_sh, 
		PARAMS, params,
		ATTRIBUTES, attr,
		VAL_ATTRIBUTES, val_attrs,
	);
	uint ex = ctx.ast.push_extra_block(&data);

	return ctx.ast.add_node(TYPEDEF_DECL, start_tok, end_tok, ex);
}

<*
	interface_declaration ::= 'interface' TYPE_IDENT (':' type (',' type)*)? attributes? interface_body
	interface_body        ::= '{' (fn_declaration)* '}'
*>
fn Node? parse_interface(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, INTERFACE)!;

	if (!ctx.is(TYPE_IDENT))
	{
		ctx.error("Expected interface name, found '%s'", ctx.token_text(ctx.current()));
		return UNEXPECTED_TOKEN~;
	}
	uint name_id = ctx.pool.intern(ctx.token_text(ctx.current()));
	advance(ctx)!;

	Node parents_head;
	if (consume(ctx, COLON)!)
	{
		while (true)
		{
			Node parent_type = parse_type(ctx, { .no_generics = true })!;

			uint[2] link = { (uint)parent_type, (uint)parents_head };
			uint ex = ctx.ast.push_extra_list(&link);
			parents_head = ctx.ast.add_node(INTERFACE_PARENT, ctx.current_pos(), ctx.current_pos(), ex);

			if (!consume(ctx, COMMA)!) break;
			if (ctx.is(LBRACE))
			{
				ctx.warn("Trailing comma");
			}
		}
	}

	Node attrs = parse_attributes(ctx)!;

	expect(ctx, LBRACE)!;

	Node methods_head;
	while (!ctx.is(RBRACE) && !ctx.is(EOF))
	{
		Node contract;
		if (ctx.is(CONTRACT))
		{
			contract = parse_contract(ctx)!;
		}

		if (!ctx.is(FN))
		{
			ctx.error("Interfaces can only contain function declarations.");
			return UNEXPECTED_TOKEN~;
		}

		Node method = parse_fn_decl(ctx, { .is_interface = true })!;

		uint[3] link = { (uint)method, (uint)contract, (uint)methods_head };
		uint ex = ctx.ast.push_extra_block(&link);
		methods_head = ctx.ast.add_node(INTERFACE_METHOD, ctx.current_pos(), ctx.current_pos(), ex);
	}

	uint end_tok = ctx.current_pos();

	expect(ctx, RBRACE)!;

	uint[*] data = views::@data{InterfaceViewFields}
	(
		NAME, name_id, 
		PARENTS, parents_head, 
		ATTRIBUTES, attrs, 
		METHODS, methods_head 
	);

	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(INTERFACE_DECL, start_tok, end_tok, ex);
}

<*
	struct_or_union TYPE_IDENT opt_interfaces opt_attributes struct_body
	TODO: wrap all fields in a FIELD_LISt
*>
fn Node? parse_struct(ParseContext* ctx, ParseFlags flags = { })
{
	uint start_tok = ctx.current_pos();
	bool is_struct = consume(ctx, STRUCT)!;
	if (!is_struct) consume(ctx, UNION)!;

	uint name;
	if (flags.is_local) // struct as a field
	{
		if (consume(ctx, IDENT)!)
		{
			name = ctx.pool.intern(ctx.current_text());
		}
	}
	else
	{
		name = parse_type_name(ctx, "struct")!;
	}

	Node interf_impl = parse_interface_impl(ctx)!;

	Node generic_params;
	if (ctx.is(LESS))
	{
		generic_params = parse_generic_decl(ctx)!;
	}

	Node attributes = parse_attributes(ctx)!;

	expect(ctx, LBRACE)!;

	bool is_first_field = true;
	uint fields_list_ex;
	@with_scratch(; watermark)
	{
		while (!ctx.is(RBRACE) && !ctx.eof())
		{
			consume(ctx, CONTRACT)!; 

			Node member;
			// Check if the next thing is a nested struct/union
			if (ctx.is(STRUCT) || ctx.is(UNION))
			{
				member = parse_struct(ctx, { .is_local = true })!; 
			}
			else if (ctx.is(BITSTRUCT))
			{
				member = parse_bitstruct_decl(ctx, { .is_local = true })!;
			}
			else
			{
				bool is_inline;
				if (is_first_field)
				{
					if (consume(ctx, INLINE)!)
					{
						is_inline = true;
					}
				}
				Node first_field = parse_field_decl(ctx, flags: is_inline ? 0 : 1)!;
				if (first_field.is_valid())
				{
					scratch.push((uint)first_field);

					FieldView view = { ctx.ast, first_field };
					Node shared_type = view.type_node();

					while (consume(ctx, COMMA)!)
					{
						Node next_field = parse_field_decl(ctx, shared_type)!;
						if (next_field.is_valid()) 
						{
							scratch.push((uint)next_field);
						}
					}
				}

				expect(ctx, EOS)!;
			}

			if (member.is_valid())
			{
				scratch.push((uint)member);
			}

			consume(ctx, CONTRACT)!; 
			is_first_field = false;
		}

		fields_list_ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};

	uint end_tok = ctx.current_pos();
	expect(ctx, RBRACE)!;

	uint[*] header = views::@data{StructViewFields}
	(
		NAME, name, 
		INTERFACES, interf_impl, 
		GENERICS, generic_params,
		ATTRIBUTES, attributes,
		FIELDS, fields_list_ex,
		CONTRACT, 0,
	);

	NodeKind kind = is_struct ? STRUCT_DECL : UNION_DECL;
	uint ex = ctx.ast.push_extra_block(&header);
	return ctx.ast.add_node(kind, start_tok, end_tok, ex);
}

<*
	BITSTRUCT_DECL ::= 'bitstruct' TYPE_IDENT ':' type bitstruct_body
*>
fn Node? parse_bitstruct_decl(ParseContext* ctx, ParseFlags flags = {})
{
	uint start_tok = ctx.current_pos();
	expect(ctx, BITSTRUCT)!;

	uint name;
	if (flags.is_local)
	{
		if (consume(ctx, IDENT)!)
		{
			name = ctx.pool.intern(ctx.current_text());
		}
	}
	else
	{
		name = parse_type_name(ctx, "bitstruct")!;
	}

	Node interfaces = parse_interface_impl(ctx)!;

	if (!consume(ctx, COLON)!)
	{
		ctx.error("':' followed by bitstruct type (e.g. 'int') was expected here.");
		ctx.skip_until({ RBRACE, EOF })!;
		return {};
	}

	Node type = parse_type(ctx, { .no_generics = true })!;

	if (!type.is_valid())
	{
		ctx.error("Failed to parse type");
		return {};
	}

	TypeView type_view = { ctx.ast, type };
	if (type_view.gen_count() > 0)
	{
		ctx.error("A bitstruct can't have an optional type.");
		return {};
	}

	Node attr = parse_attributes(ctx)!;

	Node fields = parse_bitstruct_body(ctx)!;

	uint[*] data = views::@data{BitstructViewFields}
	(
		NAME, name,
		INTERFACES, interfaces,
		TYPE, type,
		ATTRIBUTES, attr,
		FIELDS, fields,
	);

	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(BITSTRUCT_DECL, start_tok, ctx.current_pos(), ex);
}

<*
	bitstruct_body ::= '{' bitstruct_def* | bitstruct_simple_def* '}'
	
	bitstruct_def ::= base_type IDENT ':' constant_expr (DOTDOT constant_expr)? ';'
	bitstruct_simple_def ::= base_type IDENT ';'
*>
fn Node? parse_bitstruct_body(ParseContext* ctx)
{
    uint start_pos = ctx.current_pos();
    expect(ctx, LBRACE)!;

    bool is_consecutive = false;
    bool checked_style = false;

    @with_scratch(; watermark)
    {
        while (!ctx.is(RBRACE) && !ctx.is(EOF))
        {
            consume(ctx, CONTRACT)!;
            Node type = parse_type(ctx)!;

            if (ctx.is(CONST_IDENT) || ctx.is(TYPE_IDENT)) 
			{
                ctx.error("Expected a field name with an initial lower case.");
                return UNEXPECTED_TOKEN~;
            }
            Token name_tok = ctx.current();
			expect(ctx, IDENT)!;
            Node start_bit;
            Node end_bit;
            bool has_range = false;

            if (ctx.is(COLON))
            {
                if (checked_style && is_consecutive) 
				{
                    ctx.error("Cannot mix bit-range members with consecutive members.");
                    return UNEXPECTED_TOKEN~;
                }
                is_consecutive = false;
                checked_style = true;

                advance(ctx)!; // consume ':'
                start_bit = parse_expr(ctx)!;
                if (consume(ctx, DOTDOT)!) 
				{
                    end_bit = parse_expr(ctx)!;
                }
            }
            else
            {
                if (checked_style && !is_consecutive) 
				{
                    ctx.error("Expected bit range (':') for this member to match previous members.");
                    return UNEXPECTED_TOKEN~;
                }
                is_consecutive = true;
                checked_style = true;
            }

            Node attr = parse_attributes(ctx)!;
            expect(ctx, EOS)!;

            uint name_sh = ctx.pool.intern(ctx.token_text(name_tok));

			uint[*] data = views::@data{BitstructFieldViewFields}
			(
				NAME, name_sh,
				TYPE, type,
				START_BIT, start_bit,
				END_BIT, end_bit,
				ATTRIBUTES, attr,
			);

            uint m_ex = ctx.ast.push_extra_block(&data);
            scratch.push((uint)ctx.ast.add_node(BITSTRUCT_FIELD, name_tok.pos, ctx.current_pos(), m_ex));
        }

        expect(ctx, RBRACE)!;

        uint count = (uint)scratch.len() - watermark;
        uint list_ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
        
        Node body = ctx.ast.add_node(BITSTRUCT_FIELD_LIST, start_pos, ctx.current_pos(), list_ex);
        return body;
    };
}

fn Node? parse_field_decl(ParseContext* ctx, Node shared_type = {}, uint flags = 0)
{
	uint start_tok = ctx.current_pos();
	Node type_node;
	if (!shared_type.is_valid())
	{
		type_node = parse_type(ctx)!;
	}
	Token current = ctx.current();

	uint name;
	if (!ctx.is(IDENT))
	{
		expect(ctx, IDENT)!;
		name = (uint)ctx.push_invalid_node(ctx.current_pos());
	}
	else
	{
		name = ctx.pool.intern(ctx.token_text(ctx.current()));
	}

	advance(ctx)!;

	Node attr = parse_attributes(ctx)!;

	uint[*] data = views::@data{FieldViewFields}
	(
		NAME, name, 
		TYPE, type_node,
		ATTRIBUTES, attr,
		FLAGS, flags
	);
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(FIELD_DECL, start_tok, ctx.current_pos(), ex);
}

<*
	ct_expand_decl ::= $expand '(' const_expr ')' attributes?
*>
fn Node? parse_expand_decl(ParseContext* ctx)
{
	uint start_pos = ctx.current_pos();
	expect(ctx, CT_EXPAND)!;

	expect(ctx, LPAREN)!;
	Node expr = parse_constant_expr(ctx)!;
	expect(ctx, RPAREN)!;

	Node attributes = parse_attributes(ctx)!;

	uint[2] data = views::@data{ExpandDeclViewFields}(
		EXPR, expr,
		ATTRIBUTES, attributes,
	);
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(CT_EXPAND_DECL, start_pos, ctx.current_pos(), ex);
}