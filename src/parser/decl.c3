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

fn Node? parse_contract(Parser* p) => @pool()
{
	if (!p.is(CONTRACT))
	{
		p.error("Expected a contract start here.");
		return UNEXPECTED_TOKEN~;
	}

	Token contract_start_tok = p.current(); 
	uint global_offset = contract_start_tok.pos;	

	Token t = p.current();
	String slice = p.src[(Size)t.pos:t.len];

	// skip the contract for the parser
	advance(p)!;

	// store the "normal" tokens and index temporarly since
	// we need to swap them
	Token[] main_tokens = p.tokens;
	uint main_index = p.pos;
	defer
	{
		p.tokens = main_tokens;
		p.pos = main_index;
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

	p.tokens = contract_tokens.array_view();
	p.pos = 0;

	List{uint} ensures;  ensures.tinit();
	List{uint} requires; requires.tinit();
	List{uint} params;   params.tinit();
	List{uint} returns;  returns.tinit();
	ContractFlags flags;
	uint deprecated;
	uint return_desc;

	while (!p.eof())
	{
		String attr = p.token_text(p.current());
		log::debug("parse_contract - attribute = %s", attr);

		if (consume(p, AT_IDENT)!)
		{
			if (attr == constants::KW_AT_REQUIRE)
			{
				requires.push((uint)parse_contract_expr(p, false)!);
			}
			else if (attr == constants::KW_AT_ENSURE)
			{
				ensures.push((uint)parse_contract_expr(p, true)!);
			}
			else if (attr == constants::KW_AT_PARAM)
			{
				params.push((uint)parse_contract_param(p))!;
			}
			else if (attr == constants::KW_AT_DEPRECATED)
			{
				deprecated = (uint)parse_attributes(p)!;
			}
			else if (attr == constants::KW_AT_PURE)
			{
				flags.is_pure = true;
			}
			else if (attr == constants::KW_AT_RETURN)
			{
				if (p.is(QUESTION))
				{
					advance(p)!;
					while (!p.eof())
					{
						returns.push((uint)parse_expr(p)!);
						if (!consume(p, COMMA)!)
						{
							break;
						}
					}
				}
				else
				{	
					return_desc = (uint)parse_expr(p)!;
				}
			}
			else
			{
				if (catch advance(p)) break;
			}
		}
		else
		{
			if (catch advance(p)) break;
		}
	}

	uint req_idx = p.ast.push_extra_list(requires.array_view());
	uint ens_idx = p.ast.push_extra_list(ensures.array_view());
	uint params_idx = p.ast.push_extra_list(params.array_view());
	uint returns_idx = p.ast.push_extra_list(returns.array_view());

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

	uint ex = p.ast.push_extra_block(&final_data);
	return p.ast.add_node(CONTRACT_DECL, 0, p.current_pos(), ex);
}

fn Node? parse_module(Parser* p, Workspace* ws)
{
	uint node_idx = p.ast.len();
	uint start = p.current_pos();
	expect(p, MODULE)!;

	Node? path = parse_path(p)!;

	if (catch err = path)
	{
		p.error("Failed to parse path for module: %s", err);
		return err~;
	}

	if (try ModuleSection* last_sec = p.sf.sections.last())
	{
		last_sec.end_node_idx = node_idx;
	}

	PathView view = { p.ast, path };
	String mod_name = view.get_full(p.pool);

	Module* mod = ws.get_or_create_module(mod_name);
	ModuleSection* sec = ws.get_or_create_section(mod, p.sf);
	p.mod = mod;
	sec.start_node_idx = node_idx;

	Node generics = parse_generic_decl(p)!;
	Node attributes = parse_attributes(p)!;

	expect(p, EOS)!;

	log::debug("parsed module: %s", mod_name);

	// last is to reserve for contract (if any)
	uint[*] data = views::@data{ModuleViewFields}
	(
		PATH, path, 
		GENERICS, generics, 
		ATTRIBUTES, attributes, 
		CONTRACT, 0
	);
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(MODULE_DECL, start, p.current_pos(), ex);
}

fn Node? parse_enum(Parser* p, ParseFlags flags)
{
	uint start_tok = p.current_pos();

	if (flags.is_constdef) 
	{
		expect(p, CONSTDEF)!;
	} 
	else 
	{
		expect(p, ENUM)!;
	}

	uint name;
	if (p.is(TYPE_IDENT)) 
	{
		name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
	} 
	else 
	{
		p.error("Expected type identifier for enum name");
		p.push_invalid_node(p.previous_pos());
		p.skip_until({ COLON, LPAREN, LBRACE, EOS })!;
	}

	Node base_type;
	bool is_inline_type = false;
	if (consume(p, COLON)!) 
	{
		if (consume(p, INLINE)!) is_inline_type = true;
		if (p.is(LPAREN)) // if it is LPAREN, then there are no base types
		{
			base_type = p.ast.add_empty(p.current_pos());
		}
		else
		{
			base_type = parse_type(p, { .no_generics = true }) ?? p.ast.add_empty(p.current_pos());
		}
	}

	Node params = p.is(LPAREN) ? parse_parameter_list(p)! : {};
	Node attrs = parse_attributes(p)!;

	uint elements_ex = 0;
	if (consume(p, LBRACE)!) 
	{
		@with_scratch(; watermark)
		{
			while (!p.is(RBRACE) && !p.eof())
			{
				consume(p, CONTRACT)!;
				if (!p.is(CONST_IDENT)) 
				{
					p.error("Expected enum member name");
					p.push_invalid_node(p.previous_pos());
					p.skip_until({ COMMA, RBRACE })!;
					if (consume(p, COMMA)!) continue;
					break;
				}

				Token elem_tok = p.current();
				uint elem_name = p.pool.intern(p.token_text(elem_tok));
				advance(p)!;
				Node el_attrs = parse_attributes(p)!;

				Node explicit_val = consume(p, EQ)! ? (parse_expr(p)!) : 0;
				Node assoc_init = p.is(LBRACE) ? (parse_initializer_list(p)!) : 0;

				uint[*] member_data = views::@data{EnumMemberViewFields}
				(
				 NAME, elem_name, 
				 ATTRIBUTES, el_attrs,
				 EXPLICIT_VALUE, explicit_val, 
				 ASSOCIATED, assoc_init,
				);
				uint m_ex = p.ast.push_extra_block(&member_data);

				scratch.push((uint)p.ast.add_node(ENUM_MEMBER, elem_tok.pos, p.previous_pos(), m_ex));

				if (!consume(p, COMMA)!) break;
			}

			elements_ex = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
		};
		expect(p, RBRACE)!;
	}
	else
	{
		elements_ex = p.ast.push_extra_list({});
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
	uint ex = p.ast.push_extra_block(&decl_data);
	return p.ast.add_node(ENUM_DECL, start_tok, p.current_pos(), ex);
}

<*
	FAULTDEF_DECL ::= FAULTDEF CONST_IDENT (',' CONST_IDENT)* ','? ';'
*>
fn Node? parse_faultdef_decl(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, FAULTDEF)!;

	uint fault_list_idx = 0;

	@with_scratch(; watermark)
	{
		while (!p.is(EOS) && !p.eof())
		{
			Token name_tok = p.current();
			expect(p, CONST_IDENT)!;
			uint name_sh = p.pool.intern(p.token_text(name_tok));
			scratch.push(name_sh);

			if (!consume(p, COMMA)!) break;
		}

		uint count = (uint)scratch.len() - watermark;
		if (count > 0)
		{
			fault_list_idx = p.ast.push_extra_list(scratch_view(watermark, count));
		}
	};

	Node attrs = parse_attributes(p)!;

	expect(p, EOS)!;

	uint[*] data = views::@data{FaultdefDeclViewFields}
	(
		FAULTS, fault_list_idx,
		ATTRIBUTES, attrs
	);

	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(FAULTDEF_DECL, start_tok, p.current_pos(), ex);
}

fn Node? parse_fn_decl(Parser* p, ParseFlags flags) => @scratch()
{
	uint start_tok = p.current_pos();
	expect(p, FN)!;
	log::debug("parse_fn_decl - parse_type");
	Node ret_type = parse_type(p)!;

	uint name; // name of fn
	Node method_type; // if a method, the struct it belongs to, dont know what else to call it? class maybe? xD
	if (is_type(p))
	{
		method_type = parse_type(p)!;
		expect(p, DOT)!;
		if (!p.is(IDENT))
		{
			p.error("Expected member fn name");
			return UNEXPECTED_TOKEN~;
		}
		name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
	}
	else
	{
		if (!p.is(IDENT))
		{
			p.error("Expected fn name");
			return UNEXPECTED_TOKEN~;
		}

		name = p.pool.intern(p.token_text(p.current()));
		log::debug(p.pool.get((StringHandle)name));
		advance(p)!;
	}

	log::debug("parse_fn_decl - %s", p.pool.get((StringHandle)name));

	Node params = parse_parameter_list(p)!;

	log::debug("parse_fn_decl - parse_generics");
	Node type_params = parse_generic_decl(p)!;

	log::debug("parse_fn_decl - parse_attributes");
	Node attr = parse_attributes(p)!;

	Node body;
	if (p.is(LBRACE))
	{
		if (flags.is_extern)
		{
			p.error("extern functions cant have a body");
			return UNEXPECTED_TOKEN~;
		}

		log::debug("parse_fn_decl - parse_compound");
		body = parse_compound(p)!;
	}
	else if (consume(p, IMPLIES)!) // Handle the => syntax
	{
		if (flags.is_extern)
		{
			p.error("extern functions cant have a body");
			return UNEXPECTED_TOKEN~;
		}

		log::debug("parse_fn_decl - parse_short_body");
		body = parse_expr(p)!;

		if (!node_ends_with_block(p, body))
		{
			expect(p, EOS)!;
		}
	}
	else
	{
		expect(p, EOS)!;
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
	uint ex = p.ast.push_extra_block(&final_block);
	return p.ast.add_node(FN_DECL, start_tok, p.current_pos(), ex);
}

fn Node? parse_function_type(Parser* p)
{
	uint pos = p.current().pos;
	expect(p, FN)!;

	Node return_type = parse_type(p)!;

	Node params = parse_parameter_list(p)!;

	uint[*] data = views::@data{FnTypeViewFields}
	( 
		RETURN_TYPE, return_type, 
		PARAMS, (uint)params 
	);
	uint ex = p.ast.push_extra_list(&data);
	return p.ast.add_node(TYPE_FUNCTION, pos, p.current_pos(), ex);
}

fn Node? parse_macro_decl(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, MACRO)!;

	Node rtype;
	Node method_type;
	uint name;

	if IF: ((p.is(IDENT) || p.is(AT_IDENT)) && p.peek(1).kind != DOT)
	{
		name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
	}
	else
	{
		rtype = parse_type(p)!;

		if (!p.is(DOT) && !p.is(IDENT) && !p.is(AT_IDENT))
		{
			method_type = parse_type(p)!;
		}

		if (consume(p, DOT)!)
		{
			if (!method_type.is_valid())
			{
				method_type = rtype;
				rtype = { };
			}
		}

		if (!p.is(IDENT) && !p.is(AT_IDENT))
		{
			p.error("Expected macro name");
			p.push_invalid_node(p.current_pos());
			p.skip_until({ LPAREN, LBRACE, EOS })!;
			break IF;
		}

		name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
	}

	Node params = p.is(LPAREN) ? parse_macro_params(p)! : {};
	Node type_params = parse_generic_decl(p)!;
	Node attr = parse_attributes(p)!;

	Node body;
	if (consume(p, IMPLIES)!)
	{
		body = parse_expr(p)!;

		if (!node_ends_with_block(p, body))
		{
			expect(p, EOS)!;
		}
	}
	else if (p.is(LBRACE))
	{
		body = parse_statement(p)!;
	}
	else
	{
		expect(p, EOS)!;
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

	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(MACRO_DECL, start_tok, p.current_pos(), ex);
}

fn Node? parse_macro_params(Parser* p)
{
	uint start_pos = p.current_pos();
	expect(p, LPAREN)!;

    // Parse the "regular" parameters (before eos)
    Node params = parse_parameter_list(p, { .is_macro = true, .skip_eos = true })!;
    Node body_param;
    
    if (consume(p, EOS)!)
    {
        uint start = p.current_pos();
        
        // This MUST be the @body part
        if (!p.is(AT_IDENT)) 
		{
            p.error("Expected @body after ';'");
            body_param = p.push_invalid_node(p.current_pos());
			p.skip_until({ RPAREN, EOS })!;
        }
        
        uint body_name = p.pool.intern(p.token_text(p.current()));
        advance(p)!; // Consume @ident

        Node inner_params;
        if (consume(p, LPAREN)!)
        {
            // Parse the parameters INSIDE the @ident(...)
            inner_params = parse_parameter_list(p, { .is_call = false, .is_macro = true })!;
            expect(p, RPAREN)!;
        }

		uint[*] data = views::@data{BodyParamViewFields}
		(
			NAME, body_name,
			INNER_PARAMS, inner_params,
		);
        
		uint ex = p.ast.push_extra_block(&data);
        body_param = p.ast.add_node(BODY_PARAM_DECL, start, p.current_pos(), ex);
    }

    expect(p, RPAREN)!;

	uint[*] data = views::@data{MacroParamsViewFields}
	(
		PARAMS, params,
		BODY_PARAMS, body_param,
	);
    
    uint ex = p.ast.push_extra_block(&data);
    return p.ast.add_node(MACRO_PARAMS, start_pos, p.current_pos(), ex);
}

fn Node? parse_param_decl(Parser* p)
{
	uint start = p.current_pos();
	uint name;
	Node type;
	Node init;
	uint flags;

	if (p.is(AT_IDENT))
	{
		name = p.pool.intern(p.current_text());
		advance(p)!;

		Node inner_params;
		if (consume(p, LPAREN)!)
		{
			inner_params = parse_parameter_list(p, { .is_macro = true })!;
			expect(p, RPAREN)!;
		}

		uint[*] data = views::@data{BodyParamViewFields}
		(
			NAME, name,
			INNER_PARAMS, inner_params
		);
		uint ex = p.ast.push_extra_block(&data);
		return p.ast.add_node(BODY_PARAM_DECL, start, p.current_pos(), ex);
	}

	if (consume(p, AMP)!) flags |= 2;
	bool ellipsis_prefix = consume(p, ELLIPSIS)!;

	if (is_type(p) || p.is(CT_TYPE_IDENT))
	{
		type = parse_type(p)!;
		// Check for "Type..."
		if (consume(p, ELLIPSIS)!) flags |= 1;
	}

	TokenKind k = p.current().kind;
	if (is_non_type_ident(k) || k == CT_TYPE_IDENT || k == CT_IDENT || k == HASH_IDENT)
	{
		name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;

		// Check for "name..."
		if (consume(p, ELLIPSIS)!) flags |= 1;
	}

	Node attributes;
	if (p.is(AT_IDENT))
	{
		attributes = parse_attributes(p)!;
	}

	if (consume(p, EQ)!)
	{
		if (p.is(ELLIPSIS))
		{
			Token ellipsis_tok = p.peek();
			advance(p)!;
			init = p.ast.add_node(DEFAULT_ELLIPSIS, ellipsis_tok.pos, p.current_pos(), 0);
		}
		else
		{
			init = parse_expr(p)!;
		}
	}

	if (!type.is_valid() && name == 0 && !attributes.is_valid() && !ellipsis_prefix)
	{
		p.error("Expected parameter declaration");
		p.push_invalid_node(start);
	}

	uint[*] data = views::@data{ParamViewFields}
	( 
		NAME, name,
		TYPE, type,
		INIT, init,
		FLAGS, flags,
	);
	uint ex = p.ast.push_extra_block(&data);

	return p.ast.add_node(PARAM_DECL, start, p.current_pos(), ex);
}

<*
 TYPE_ALIAS_DECL ::= ALIAS TYPE_IDENT attributes? '=' typedef_type ';'
    TYPE_ALIAS_DECL ::= func_typedef | type generic_params?
*>
fn Node? parse_type_alias(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, ALIAS)!;

	Token name_tok = p.current();

	if (!p.is(TYPE_IDENT))
	{
		p.error("Expected Type identifier");
		return UNEXPECTED_TOKEN~;
	}

	expect(p, TYPE_IDENT)!;
	uint name_sh = p.pool.intern(p.token_text(name_tok));

	Node generics = parse_generic_decl(p)!;
	Node attr = parse_attributes(p)!;

	expect(p, EQ)!;

	Node target_type;
	if (p.is(FN))
	{
		target_type = parse_function_type(p)!;
	}
	else
	{
		target_type = parse_expr(p)!;
	}

	uint end_tok = p.current_pos();
	expect(p, EOS)!;

	Node type_attr = parse_attributes(p)!;

	uint[*] data = views::@data{TypeAliasViewFields}
	( 
		NAME, name_sh, 
		TARGET_TYPE, target_type, 
		GENERICS, generics,
		ATTRIBUTES, attr,
		TYPE_ATTRIBUTES, type_attr,
	);
	uint ex = p.ast.push_extra_list(&data);

	return p.ast.add_node(TYPE_ALIAS_DECL, start_tok, end_tok, ex);
}

<*
 	PATH_ALIAS_DECL ::= 'alias' (IDENT | CONST_IDENT | AT_IDENT) attributes? '=' (('module' path) | identifier_alias generic_params?)
    ALIAS_DECL ::= path? (IDENT | CONST_IDENT | AT_IDENT)
*>
fn Node? parse_ident_alias(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, ALIAS)!;

	TokenKind kind = p.current().kind;
	if (kind != IDENT && kind != CONST_IDENT && kind != AT_IDENT)
	{
		p.error("A type, variable, constant or attribute name was expected");
		return UNEXPECTED_TOKEN~;
	}

	uint name = p.pool.intern(p.token_text(p.current()));

	advance(p)!;

	Node attr = parse_attributes(p)!;

	expect(p, EQ)!;

	if (p.is(MODULE))
	{
		advance(p)!; // skip module

		Node path = parse_path(p)!;

		uint[*] data = views::@data{PathAliasViewFields}
		( 
		 NAME, name, 
		 PATH, path, 
		 ATTRIBUTES, attr,
		);
		uint ex = p.ast.push_extra_block(&data);

		return p.ast.add_node(PATH_ALIAS_DECL, start_tok, p.current_pos(), ex);
	}

	Node expr = parse_expr(p)!;

	expect(p, EOS)!;

	uint[*] data = views::@data{ExprAliasViewFields}
	( 
		NAME, name, 
		EXPR, expr, 
		ATTRIBUTES, attr,
	);
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(ALIAS_DECL, start_tok, p.current_pos(), ex);
}

fn Node? parse_alias(Parser* p)
{
	switch (p.peek(1).kind)
	{
		case TYPE_IDENT:
			return parse_type_alias(p);
		default:
			return parse_ident_alias(p);
	}
}

<*
	GENERIC_DECL ::= <...>
*>
fn Node? parse_generic_decl(Parser* p)
{
	uint start_tok = p.current_pos();
	if (!consume(p, LESS)!) return {};
	if (consume(p, GREATER)!)
	{
		p.error("Generic paramter list cannot be empty");
	}

	uint list;
	@with_scratch(; watermark)
	{
		while (true)
		{
			switch (p.current().kind)
			{
				case TYPE_IDENT:
				case CONST_IDENT:
					break;
				case COMMA:
					p.error("Unexpected ','");
					return {};
				case IDENT:
				case CT_IDENT:
				case CT_TYPE_IDENT:
					p.error("The generic parameter cannot be a $-prefixed name.");
					return {};
				default:
					p.error("Only generic parameters are allowed here.");
					return {};
			}

			uint name = p.pool.intern(p.current_text());
			scratch.push(name);
			advance(p)!;
			if (!consume(p, COMMA)!)
			{
				expect(p, GREATER)!;
				break;
			}
		}

		list = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};

	uint[*] data = views::@data{GenericDeclViewFields}
	(
		PARAMETERS, list 
	);
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(GENERIC_DECL, start_tok, p.current_pos(), ex);
}

<*
	TYPEDEF_DECL ::= 'typedef' TYPE_IDENT opt_interfaces attributes? '=' 'inline'? type ';'
*>
fn Node? parse_typedef(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, TYPEDEF)!;

	Token name_tok = p.current();
	expect(p, TYPE_IDENT)!;
	uint name_sh = p.pool.intern(p.token_text(name_tok));

	Node inter = parse_interface_impl(p)!;
	Node generics = parse_generic_decl(p)!;
	Node attr = parse_attributes(p)!;
	expect(p, EQ)!;

	if (consume(p, INLINE)!)
	{
		// TODO:
	}

	Node base_type = parse_type(p)!;
	Node type_attr = parse_attributes(p)!;
	uint end_tok = p.current_pos();
	expect(p, EOS)!;

	uint[*] data = views::@data{TypedefViewFields}
	(
		NAME, name_sh, 
		BASE_TYPE, base_type, 
		ATTRIBUTES, attr,
		INTERFACES, inter,
		GENERICS, generics,
		TYPE_ATTRIBUTES, type_attr,
	);
	uint ex = p.ast.push_extra_block(&data);

	return p.ast.add_node(TYPEDEF_DECL, start_tok, end_tok, ex);
}

<*
	TYPEDEF_DECL ::= 'typedef' TYPE_IDENT opt_interfaces attributes? '=' 'inline'? type ';'
*>
fn Node? parse_attrdef(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, ATTRDEF)!;

	Token name_tok = p.current();
	expect(p, AT_TYPE_IDENT)!;
	uint name_sh = p.pool.intern(p.token_text(name_tok));

	Node params;
	if (p.is(LPAREN))
	{
		params = parse_parameter_list(p)!;
	}
	else
	{
		params = p.ast.add_empty(p.current_pos());
	}
	Node attr = parse_attributes(p)!;
	expect(p, EQ)!;

	Node val_attrs = parse_attributes(p, comma_seperated: true)!;
	uint end_tok = p.current_pos();
	expect(p, EOS)!;

	uint[*] data = views::@data{AttrdefViewFields}
	(
		NAME, name_sh, 
		PARAMS, params,
		ATTRIBUTES, attr,
		VAL_ATTRIBUTES, val_attrs,
	);
	uint ex = p.ast.push_extra_block(&data);

	return p.ast.add_node(TYPEDEF_DECL, start_tok, end_tok, ex);
}

<*
	interface_declaration ::= 'interface' TYPE_IDENT (':' type (',' type)*)? attributes? interface_body
	interface_body        ::= '{' (fn_declaration)* '}'
*>
fn Node? parse_interface(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, INTERFACE)!;

	if (!p.is(TYPE_IDENT))
	{
		p.error("Expected interface name, found '%s'", p.token_text(p.current()));
		return UNEXPECTED_TOKEN~;
	}
	uint name_id = p.pool.intern(p.token_text(p.current()));
	advance(p)!;

	Node parents_head;
	if (consume(p, COLON)!)
	{
		while (true)
		{
			Node parent_type = parse_type(p, { .no_generics = true })!;

			uint[2] link = { (uint)parent_type, (uint)parents_head };
			uint ex = p.ast.push_extra_list(&link);
			parents_head = p.ast.add_node(INTERFACE_PARENT, p.current_pos(), p.current_pos(), ex);

			if (!consume(p, COMMA)!) break;
			if (p.is(LBRACE))
			{
				p.warn("Trailing comma");
			}
		}
	}

	Node attrs = parse_attributes(p)!;

	expect(p, LBRACE)!;

	Node methods_head;
	while (!p.is(RBRACE) && !p.is(EOF))
	{
		Node contract;
		if (p.is(CONTRACT))
		{
			contract = parse_contract(p)!;
		}

		if (!p.is(FN))
		{
			p.error("Interfaces can only contain function declarations.");
			return UNEXPECTED_TOKEN~;
		}

		Node method = parse_fn_decl(p, { .is_interface = true })!;

		uint[3] link = { (uint)method, (uint)contract, (uint)methods_head };
		uint ex = p.ast.push_extra_block(&link);
		methods_head = p.ast.add_node(INTERFACE_METHOD, p.current_pos(), p.current_pos(), ex);
	}

	uint end_tok = p.current_pos();

	expect(p, RBRACE)!;

	uint[*] data = views::@data{InterfaceViewFields}
	(
		NAME, name_id, 
		PARENTS, parents_head, 
		ATTRIBUTES, attrs, 
		METHODS, methods_head 
	);

	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(INTERFACE_DECL, start_tok, end_tok, ex);
}

<*
	struct_or_union TYPE_IDENT opt_interfaces opt_attributes struct_body
	TODO: wrap all fields in a FIELD_LISt
*>
fn Node? parse_struct(Parser* p, ParseFlags flags = { })
{
	uint start_tok = p.current_pos();
	bool is_struct = consume(p, STRUCT)!;
	if (!is_struct) consume(p, UNION)!;

	uint name;
	if (flags.is_local) // struct as a field
	{
		if (consume(p, IDENT)!)
		{
			name = p.pool.intern(p.current_text());
		}
	}
	else
	{
		name = parse_type_name(p, "struct")!;
	}

	Node interf_impl = parse_interface_impl(p)!;

	Node generic_params;
	if (p.is(LESS))
	{
		generic_params = parse_generic_decl(p)!;
	}

	Node attributes = parse_attributes(p)!;

	expect(p, LBRACE)!;

	bool is_first_field = true;
	uint fields_list_ex;
	@with_scratch(; watermark)
	{
		while (!p.is(RBRACE) && !p.eof())
		{
			consume(p, CONTRACT)!; 

			Node member;
			// Check if the next thing is a nested struct/union
			if (p.is(STRUCT) || p.is(UNION))
			{
				member = parse_struct(p, { .is_local = true })!; 
			}
			else if (p.is(BITSTRUCT))
			{
				member = parse_bitstruct_decl(p, { .is_local = true })!;
			}
			else
			{
				bool is_inline;
				if (is_first_field)
				{
					if (consume(p, INLINE)!)
					{
						is_inline = true;
					}
				}
				Node first_field = parse_field_decl(p, flags: is_inline ? 0 : 1)!;
				if (first_field.is_valid())
				{
					scratch.push((uint)first_field);

					FieldView view = { p.ast, first_field };
					Node shared_type = view.type_node();

					while (consume(p, COMMA)!)
					{
						Node next_field = parse_field_decl(p, shared_type)!;
						if (next_field.is_valid()) 
						{
							scratch.push((uint)next_field);
						}
					}
				}

				expect(p, EOS)!;
			}

			if (member.is_valid())
			{
				scratch.push((uint)member);
			}

			consume(p, CONTRACT)!; 
			is_first_field = false;
		}

		fields_list_ex = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};

	uint end_tok = p.current_pos();
	expect(p, RBRACE)!;

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
	uint ex = p.ast.push_extra_block(&header);
	return p.ast.add_node(kind, start_tok, end_tok, ex);
}

<*
	BITSTRUCT_DECL ::= 'bitstruct' TYPE_IDENT ':' type bitstruct_body
*>
fn Node? parse_bitstruct_decl(Parser* p, ParseFlags flags = {})
{
	uint start_tok = p.current_pos();
	expect(p, BITSTRUCT)!;

	uint name;
	if (flags.is_local)
	{
		if (consume(p, IDENT)!)
		{
			name = p.pool.intern(p.current_text());
		}
	}
	else
	{
		name = parse_type_name(p, "bitstruct")!;
	}

	Node interfaces = parse_interface_impl(p)!;

	if (!consume(p, COLON)!)
	{
		p.error("':' followed by bitstruct type (e.g. 'int') was expected here.");
		p.skip_until({ RBRACE, EOF })!;
		return {};
	}

	Node type = parse_type(p, { .no_generics = true })!;

	if (!type.is_valid())
	{
		p.error("Failed to parse type");
		return {};
	}

	TypeView type_view = { p.ast, type };
	if (type_view.gen_count() > 0)
	{
		p.error("A bitstruct can't have an optional type.");
		return {};
	}

	Node attr = parse_attributes(p)!;

	Node fields = parse_bitstruct_body(p)!;

	uint[*] data = views::@data{BitstructViewFields}
	(
		NAME, name,
		INTERFACES, interfaces,
		TYPE, type,
		ATTRIBUTES, attr,
		FIELDS, fields,
	);

	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(BITSTRUCT_DECL, start_tok, p.current_pos(), ex);
}

<*
	bitstruct_body ::= '{' bitstruct_def* | bitstruct_simple_def* '}'
	
	bitstruct_def ::= base_type IDENT ':' constant_expr (DOTDOT constant_expr)? ';'
	bitstruct_simple_def ::= base_type IDENT ';'
*>
fn Node? parse_bitstruct_body(Parser* p)
{
    uint start_pos = p.current_pos();
    expect(p, LBRACE)!;

    bool is_consecutive = false;
    bool checked_style = false;

    @with_scratch(; watermark)
    {
        while (!p.is(RBRACE) && !p.is(EOF))
        {
            consume(p, CONTRACT)!;
            Node type = parse_type(p)!;

            if (p.is(CONST_IDENT) || p.is(TYPE_IDENT)) 
			{
                p.error("Expected a field name with an initial lower case.");
                return UNEXPECTED_TOKEN~;
            }
            Token name_tok = p.current();
			expect(p, IDENT)!;
            Node start_bit;
            Node end_bit;
            bool has_range = false;

            if (p.is(COLON))
            {
                if (checked_style && is_consecutive) 
				{
                    p.error("Cannot mix bit-range members with consecutive members.");
                    return UNEXPECTED_TOKEN~;
                }
                is_consecutive = false;
                checked_style = true;

                advance(p)!; // consume ':'
                start_bit = parse_expr(p)!;
                if (consume(p, DOTDOT)!) 
				{
                    end_bit = parse_expr(p)!;
                }
            }
            else
            {
                if (checked_style && !is_consecutive) 
				{
                    p.error("Expected bit range (':') for this member to match previous members.");
                    return UNEXPECTED_TOKEN~;
                }
                is_consecutive = true;
                checked_style = true;
            }

            Node attr = parse_attributes(p)!;
            expect(p, EOS)!;

            uint name_sh = p.pool.intern(p.token_text(name_tok));

			uint[*] data = views::@data{BitstructFieldViewFields}
			(
				NAME, name_sh,
				TYPE, type,
				START_BIT, start_bit,
				END_BIT, end_bit,
				ATTRIBUTES, attr,
			);

            uint m_ex = p.ast.push_extra_block(&data);
            scratch.push((uint)p.ast.add_node(BITSTRUCT_FIELD, name_tok.pos, p.current_pos(), m_ex));
        }

        expect(p, RBRACE)!;

        uint count = (uint)scratch.len() - watermark;
        uint list_ex = p.ast.push_extra_list(scratch_view(watermark, count));
        
        Node body = p.ast.add_node(BITSTRUCT_FIELD_LIST, start_pos, p.current_pos(), list_ex);
        return body;
    };
}

fn Node? parse_field_decl(Parser* p, Node shared_type = {}, uint flags = 0)
{
	uint start_tok = p.current_pos();
	Node type_node;
	if (!shared_type.is_valid())
	{
		type_node = parse_type(p)!;
	}
	Token current = p.current();

	uint name;
	if (!p.is(IDENT))
	{
		expect(p, IDENT)!;
		name = (uint)p.push_invalid_node(p.current_pos());
	}
	else
	{
		name = p.pool.intern(p.token_text(p.current()));
	}

	advance(p)!;

	Node attr = parse_attributes(p)!;

	uint[*] data = views::@data{FieldViewFields}
	(
		NAME, name, 
		TYPE, type_node,
		ATTRIBUTES, attr,
		FLAGS, flags
	);
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(FIELD_DECL, start_tok, p.current_pos(), ex);
}
