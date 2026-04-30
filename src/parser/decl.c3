module c3_parser::parser;
import c3_parser::ast;
import lexer;
import string_pool;

import c3_parser::common;
import c3_parser::registry;
import std::collections::list;
import c3_parser::workspace @norecurse;
import std::io;

fn Node? parse_contract(Parser* p)
{
	advance(p)!;

	return UNEXPECTED_TOKEN~;

	uint start = p.current_pos();
	if (!p.is(CONTRACT))
	{
		p.error("Expected a contract start here.");
		return UNEXPECTED_TOKEN~;
	}

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

	ContractLexer cl;
	cl.init(slice);

	while (try next = cl.next())
	{
		contract_tokens.push(next);
	}

	p.tokens = contract_tokens.array_view();
	p.pos = 0;

	List{uint} ensures;
	List{uint} requires;
	ensures.tinit();
	requires.tinit();

	while (!p.eof())
	{
		if (consume(p, AT_IDENT)!)
		{
			String tok_text = p.token_text(p.current());

			switch (tok_text)
			{
				case "ensure":
					{
						ensures.push((uint)parse_expr(p)!);
					}
				case "requires":
					{
						ensures.push((uint)parse_expr(p)!);
					}
			}

			Node condition = parse_expr(p)!;
		}
	}

	// uint ex = ast::push_extra_list(p.ast, );
	// return ast::add_node(p.ast, CONTRACT_DECL, start, ex);
	return { };
}

fn Node? parse_module(Parser* p, Workspace* ws)
{
	uint node_idx = p.ast.len();
	uint start = p.current_pos();
	expect(p, MODULE)!;

	String mod_name = "";
	uint pos = 0;
	while MOD_NAME: (true)
	{
		Token t = p.peek(pos);
		switch (t.kind)
		{
			case IDENT:
				String part = p.token_text(t);
				mod_name = mod_name.tconcat(part);
			case SCOPE:
				mod_name = mod_name.tconcat("::");
			case EOS:
				break MOD_NAME;
			default:
				return UNEXPECTED_TOKEN~;
		}

		pos++;
	}

	if (try ModuleSection* last_sec = p.sf.sections.last())
	{
		last_sec.end_node_idx = node_idx;
	}

	Node? path_node = parse_path(p);

	Module* mod = ws.get_or_create_module(mod_name);
	ModuleSection* sec = ws.get_or_create_section(mod, p.sf);
	p.mod = mod;
	sec.start_node_idx = node_idx;

	if (catch err = path_node)
	{
		p.error("failed to parse path for module: %s", err);
		return err~;
	}

	uint generics = parse_generics(p)!;
	uint attributes = parse_attributes(p)!;

	expect(p, EOS)!;

	PathView view = { p.ast, path_node };

	uint[*] data = { (uint)path_node, generics, attributes };
	uint ex = ast::push_extra_list(p.ast, &data);

	log::debug("parsed module!");
	return ast::add_node(p.ast, MODULE_DECL, start, p.current_pos(), ex);
}

fn OverloadKind get_overload_from_token(TokenKind kind)
{
	switch (kind)
	{
		case PLUS: return OverloadKind.PLUS;
		case PLUS_ASSIGN: return OverloadKind.PLUS_ASSIGN;
		case MINUS: return OverloadKind.MINUS;
		case MINUS_ASSIGN: return OverloadKind.MINUS_ASSIGN;
		case ASTERISK: return OverloadKind.MULTIPLY;
		case MULT_ASSIGN: return OverloadKind.MULTIPLY_ASSIGN;
		case DIV: return OverloadKind.DIVIDE;
		case DIV_ASSIGN: return OverloadKind.DIVIDE_ASSIGN;
		case MOD: return OverloadKind.REMINDER;
		case MOD_ASSIGN: return OverloadKind.REMINDER_ASSIGN;
		case AMP: return OverloadKind.AND;
		case BIT_AND_ASSIGN: return OverloadKind.AND_ASSIGN;
		case BIT_OR: return OverloadKind.OR;
		case BIT_OR_ASSIGN: return OverloadKind.OR_ASSIGN;
		case BIT_XOR: return OverloadKind.XOR;
		case BIT_XOR_ASSIGN: return OverloadKind.XOR_ASSIGN;
		case LSHIFT: return OverloadKind.SHL;
		case LSHIFT_ASSIGN: return OverloadKind.SHL_ASSIGN;
		case RSHIFT: return OverloadKind.SHR;
		case RSHIFT_ASSIGN: return OverloadKind.SHR_ASSIGN;
		case BIT_NOT: return OverloadKind.NEGATE;
		case EQEQ: return OverloadKind.EQUAL;
		case NOT_EQUAL: return OverloadKind.NOT_EQUAL;
		default:
			unreachable();
	}
}

fn Node? parse_enum(Parser* p, ParseFlags flags)
{
    uint start_tok = p.current_pos();
	if (!flags.is_constdef)
	{
    	expect(p, ENUM)!;
	}
	else
	{
		expect(p, CONSTDEF)!;
	}

    Token name_tok = p.current();
    expect(p, TYPE_IDENT)!;
    uint name = p.pool.intern(p.token_text(name_tok));

    Node base_type;
	bool is_inline_type;

    if (consume(p, COLON)!) 
	{
		if (consume(p, INLINE)!) 
		{
			is_inline_type = true;
		}

		base_type = parse_type(p)!;
	}

    uint params = 0;
    if (p.is(LPAREN)) params = parse_parameter_list(p)!;

    uint attrs = parse_attributes(p)!;

    expect(p, LBRACE)!;

    uint elements_ex = 0;

    @with_scratch(; watermark)
    {
        while (!p.is(RBRACE) && !p.eof())
        {
            Token elem_tok = p.current();
            uint elem_name = p.pool.intern(p.token_text(elem_tok));
            advance(p)!;

            Node explicit_val;
            if (consume(p, EQ)!) explicit_val = parse_expr(p, { })!;

            Node assoc_init;
            if (p.is(LBRACE)) assoc_init = parse_initializer_list(p)!;

            uint[3] member_data = { elem_name, (uint)explicit_val, (uint)assoc_init };
            uint m_ex = ast::push_extra_list(p.ast, &member_data);
            
            Node member_node = ast::add_node(p.ast, ENUM_MEMBER, elem_tok.pos, p.previous_pos(), m_ex);
            scratch.push((uint)member_node);

            if (!consume(p, COMMA)!) break;
        }
        
        uint count = (uint)scratch.len() - watermark;
        elements_ex = ast::push_extra_list(p.ast, scratch_view(watermark, count));
    };

    expect(p, RBRACE)!;

	uint packed_flags = 0;
	if (flags.is_constdef) packed_flags |= (1 << 0);
    if (is_inline_type)    packed_flags |= (1 << 1);

    uint[6] decl_data = { name, (uint)base_type, params, attrs, elements_ex, packed_flags };
    uint ex = ast::push_extra_list(p.ast, &decl_data);
    return ast::add_node(p.ast, ENUM_DECL, start_tok, p.current_pos(), ex);
}

fn Node? parse_fn_decl(Parser* p, ParseFlags flags) => @scratch()
{
	uint start_tok = p.current_pos();
	expect(p, FN)!;
	log::debug("parse_fn_decl - parse_type");
	Node ret_type = parse_type(p)!;

	uint name; // name of fn
	uint method_type; // if a method, the struct it belongs to, dont know what else to call it? class maybe? xD
	if (p.peek(1).kind == DOT)
	{
		if (!is_type(p.current().kind))
		{
			p.error("Expected method Type name");
			return UNEXPECTED_TOKEN~;
		}
		method_type = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
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
		advance(p)!;
	}

	log::debug("parse_fn_decl - %s", p.pool.get((StringHandle)name));

	uint params = parse_parameter_list(p)!;

	log::debug("parse_fn_decl - parse_attributes");
	uint attr = parse_attributes(p)!;

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
		expect(p, EOS)!;
	}
	else
	{
		expect(p, EOS)!;
	}

	uint[6] final_block;
	final_block[0] = name;
	final_block[1] = method_type;
	final_block[2] = (uint)ret_type;
	final_block[3] = attr;
	final_block[4] = params;
	final_block[5] = (uint)body;

	log::debug("parse_fn_decl - finished.. adding to ast");
	uint ex = ast::push_extra_list(p.ast, &final_block);
	return ast::add_node(p.ast, FN_DECL, start_tok, p.current_pos(), ex);
}

fn Node? parse_function_type(Parser* p)
{
	uint pos = p.current().pos;
	expect(p, FN)!;

	Node return_type = parse_type(p)!;

	uint params = parse_parameter_list(p)!;

	uint[*] data = { (uint)return_type, (uint)params };
	uint ex = ast::push_extra_list(p.ast, &data);
	return ast::add_node(p.ast, TYPE_FUNCTION, pos, p.current_pos(), ex);
}

fn Node? parse_macro_decl(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, MACRO)!;

	Node rtype;
	Node method_type;
	uint name; // name of fn

	// /log::info("parse_macro_decl - current : %s", p.current().kind);
	// /log::info("parse_macro_decl - 1 : %s", p.peek().kind);
	// /log::info("parse_macro_decl - 2 : %s", p.peek(2).kind);

	if ((p.is(IDENT) || p.is(AT_IDENT)) && p.peek(1).kind != DOT)
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
			p.error("Expected macro name, got %s", p.token_text(p.current()));
			return UNEXPECTED_TOKEN~;
		}

		name = p.pool.intern(p.token_text(p.current()));
		advance(p)!;
	}

	uint params;
	if (p.is(LPAREN))
	{
		params = parse_parameter_list(p)!;
	}

	uint attr = parse_attributes(p)!;

	Node body;
	if (p.is(IMPLIES))
	{
		advance(p)!;
		body = parse_expr(p)!;
		expect(p, EOS)!;
	}
	else if (p.is(LBRACE))
	{
		body = parse_statement(p)!;
	}

	uint[*] data = { name, (uint)rtype, (uint)method_type, attr, params, (uint)body };
	uint ex = ast::push_extra_list(p.ast, &data);

	return ast::add_node(p.ast, MACRO_DECL, start_tok, p.current_pos(), ex);
}

fn Node? parse_param_decl(Parser* p)
{
    uint start = p.current_pos();
    uint name = 0;
    Node type;
    Node init;
    bool is_variadic = false;
	uint flags = 0;

	if (consume(p, AMP)!)
    {
        flags |= 2;
    }

    if (consume(p, ELLIPSIS)!)
    {        
		flags |= 1;

        if (is_non_type_ident(p.current().kind) || p.current().kind == CT_TYPE_IDENT)
        {
            name = p.pool.intern(p.token_text(p.current()));
            advance(p)!;
        }
    }
    else
    {
		if (is_type(p.current().kind) || p.is(CT_TYPE_IDENT))
		{
        	type = parse_type(p)!;

			if (consume(p, ELLIPSIS)!)
            {
                flags |= 1;
            }
		}

		TokenKind k = p.current().kind;
		if (is_non_type_ident(k) || k == CT_TYPE_IDENT || k == CT_IDENT)
        {
            name = p.pool.intern(p.token_text(p.current()));
            advance(p)!;
        }
    }

    // Default Values ('=' expr)
    if (name != 0 && consume(p, EQ)!)
    {
        init = parse_expr(p)!;
    }

    uint[4] data = { name, (uint)type, (uint)init, flags };
    uint ex = ast::push_extra_list(p.ast, &data);

    return ast::add_node(p.ast, PARAM_DECL, start, p.current_pos(), ex);
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

	uint attr = parse_attributes(p)!;

	expect(p, EQ)!;

	Node target_type;
	if (p.is(FN))
	{
		target_type = parse_function_type(p)!;
	}
	else
	{
		target_type = parse_type(p)!;
	}

	uint end_tok = p.current_pos();
	expect(p, EOS)!;

	uint[*] data = { name_sh, (uint)target_type, attr };
	uint ex = ast::push_extra_list(p.ast, &data);

	return ast::add_node(p.ast, TYPE_ALIAS_DECL, start_tok, end_tok, ex);
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

	uint attr = parse_attributes(p)!;

	expect(p, EQ)!;

	if (p.is(MODULE))
	{
		advance(p)!; // skip module

		Node path = parse_path(p)!;

		uint[*] data = { name, (uint)path, (uint)attr };
		uint ex = ast::push_extra_list(p.ast, &data);

		return ast::add_node(p.ast, PATH_ALIAS_DECL, start_tok, p.current_pos(), ex);
	}

	Node expr = parse_expr(p)!;

	uint[*] data = { name, (uint)expr, attr };
	uint ex = ast::push_extra_list(p.ast, &data);

	return ast::add_node(p.ast, ALIAS_DECL, start_tok, p.current_pos(), ex);
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

fn Node? parse_typedef(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, TYPEDEF)!;

	Token name_tok = p.current();
	expect(p, TYPE_IDENT)!;
	uint name_sh = p.pool.intern(p.token_text(name_tok));

	Node inter = parse_interface_impl(p)!;

	expect(p, EQ)!;

	if (consume(p, INLINE)!)
	{
		// TODO:
	}

	Node base_type = parse_type(p)!;
	uint end_tok = p.current_pos();
	expect(p, EOS)!;

	uint[*] data = { name_sh, (uint)base_type, (uint)inter };
	uint ex = ast::push_extra_list(p.ast, &data);

	return ast::add_node(p.ast, TYPEDEF_DECL, start_tok, end_tok, ex);
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
			uint ex = ast::push_extra_list(p.ast, &link);
			parents_head = ast::add_node(p.ast, INTERFACE_PARENT, p.current_pos(), p.current_pos(), ex);

			if (!consume(p, COMMA)!) break;
			if (p.is(LBRACE))
			{
				p.warn("Trailing comma");
			}
		}
	}

	uint attrs = parse_attributes(p)!;

	expect(p, LBRACE)!;

	Node methods_head;
	while (!p.is(RBRACE) && !p.is(EOF))
	{
		if (!p.is(FN))
		{
			p.error("Interfaces can only contain function declarations.");
			return UNEXPECTED_TOKEN~;
		}

		Node method = parse_fn_decl(p, { .is_interface = true })!;

		uint[2] link = { (uint)method, (uint)methods_head };
		uint ex = ast::push_extra_list(p.ast, &link);
		methods_head = ast::add_node(p.ast, INTERFACE_METHOD, p.current_pos(), p.current_pos(), ex);
	}

	uint end_tok = p.current_pos();

	expect(p, RBRACE)!;

	uint[4] data = { name_id, (uint)parents_head, attrs, (uint)methods_head };

	uint ex = ast::push_extra_list(p.ast, &data);
	return ast::add_node(p.ast, INTERFACE_DECL, start_tok, end_tok, ex);
}

fn Node? parse_struct(Parser* p)
{
	uint start_tok = p.current_pos();

	expect(p, STRUCT)!;

	if (!p.is(TYPE_IDENT))
	{
		p.error("Expected struct name");
		return UNEXPECTED_TOKEN~;
	}
	uint name = p.pool.intern(p.token_text(p.current()));
	advance(p)!;

	Node interf_impl = parse_interface_impl(p)!;

	uint generic_params;
	if (p.is(LESS))
	{
		generic_params = parse_generics(p)!;
	}

	expect(p, LBRACE)!;

	List{uint} data;
	data.tinit(32);
	defer data.free();

	data.push(name);
	data.push((uint)interf_impl);
	data.push(generic_params);
	data.push(0); // Placeholder for field count at index [3]

	uint field_count = 0;
	while (!p.is(RBRACE))
	{
		Node field = parse_field_decl(p)!;
		if (field.is_valid())
		{
			data.push((uint)field);
			field_count++;
		}

		expect(p, EOS)!;
		consume(p, CONTRACT)!; // some contracts might be used as a doc
		if (!p.is(TYPE_IDENT) && !is_type(p.current().kind))
		{
			break;
		}
	}

	uint end_tok = p.current_pos();

	expect(p, RBRACE)!;

	data[3] = field_count;

	uint ex = ast::push_extra_list(p.ast, data.array_view());
	return ast::add_node(p.ast, STRUCT_DECL, start_tok, end_tok, ex);
}

fn Node? parse_field_decl(Parser* p)
{
	uint start_tok = p.current_pos();

	Node type_node = parse_type(p)!;

	if (!p.is(IDENT))
	{
		p.error("Expected field name");
		return UNEXPECTED_TOKEN~;
	}

	uint name = p.pool.intern(p.token_text(p.current()));

	uint end_tok = p.current_pos();
	advance(p)!;

	uint[2] data = { name, (uint)type_node };
	uint ex = ast::push_extra_list(p.ast, &data);

	return ast::add_node(p.ast, FIELD_DECL, start_tok, end_tok, ex);
}
