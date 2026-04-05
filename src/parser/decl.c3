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

    uint param_count = 0;
    uint generics_ex = parse_generics(p, &param_count)!;

    expect(p, TokenKind.EOS)!;

	PathView view = { p.ast, path_node };

    uint[3] data = { (uint)path_node, generics_ex, param_count };
    uint ex = ast::push_extra_block(p.ast, &data);

	log::debug("parsed module!");
    return ast::add_node(p.ast, NodeKind.MODULE_DECL, start, ex);
}

<*
    Parses: <T, V ...>
    Returns a list of parameter nodes or a single block index.
*>
fn uint? parse_generics(Parser* p, uint* out_count)
{
    if (!consume(p, TokenKind.LESS)!)
    {
        *out_count = 0;
        return 0;
    }

    List{uint} params;
    params.tinit(8);
    defer params.free();

    while (true)
    {
        Token t = p.current();
        if (!is_some_ident(t.kind))
        {
            p.error("Expected identifier in generic list, got %s", p.token_text(t));
            return 0;
        }

        uint id = p.pool.intern(p.token_text(t));
        params.push(id);
        advance(p)!;

        if (!consume(p, TokenKind.COMMA)!) break;
    }

    expect(p, TokenKind.GREATER)!;
    
    *out_count = (uint)params.len();
    return ast::push_extra_block(p.ast, params.array_view());
}

fn OverloadKind get_overload_from_token(TokenKind kind)
{
    switch (kind)
    {
        case TokenKind.PLUS:           return OverloadKind.PLUS;
		case TokenKind.PLUS_ASSIGN:    return OverloadKind.PLUS_ASSIGN;
		case TokenKind.MINUS:          return OverloadKind.MINUS;
		case TokenKind.MINUS_ASSIGN:   return OverloadKind.MINUS_ASSIGN;
		case TokenKind.ASTERISK:       return OverloadKind.MULTIPLY;
		case TokenKind.MULT_ASSIGN:    return OverloadKind.MULTIPLY_ASSIGN;
		case TokenKind.DIV:            return OverloadKind.DIVIDE;
		case TokenKind.DIV_ASSIGN:     return OverloadKind.DIVIDE_ASSIGN;
		case TokenKind.MOD:            return OverloadKind.REMINDER;
		case TokenKind.MOD_ASSIGN:         return OverloadKind.REMINDER_ASSIGN;
		case TokenKind.AMP:            return OverloadKind.AND;
		case TokenKind.BIT_AND_ASSIGN: return OverloadKind.AND_ASSIGN;
		case TokenKind.BIT_OR:         return OverloadKind.OR;
		case TokenKind.BIT_OR_ASSIGN:  return OverloadKind.OR_ASSIGN;
		case TokenKind.BIT_XOR:        return OverloadKind.XOR;
		case TokenKind.BIT_XOR_ASSIGN: return OverloadKind.XOR_ASSIGN;
		case TokenKind.LSHIFT:         return OverloadKind.SHL;
		case TokenKind.LSHIFT_ASSIGN:  return OverloadKind.SHL_ASSIGN;
		case TokenKind.RSHIFT:         return OverloadKind.SHR;
		case TokenKind.RSHIFT_ASSIGN:  return OverloadKind.SHR_ASSIGN;
		case TokenKind.BIT_NOT:        return OverloadKind.NEGATE;
		case TokenKind.EQEQ:           return OverloadKind.EQUAL;
		case TokenKind.NOT_EQUAL:      return OverloadKind.NOT_EQUAL;
        default:
            unreachable();
    }
}

fn Node? parse_attributes(Parser* p)
{
    if (!p.is(TokenKind.AT_IDENT) && !p.is(TokenKind.AT_CONST_IDENT) && !p.is(TokenKind.AT_TYPE_IDENT))
    {
        return {};
    }

    // The "Next" pointer for the linked list
    Node head;

    while (true)
    {
        Token t = p.current();
        if (t.kind != TokenKind.AT_IDENT && t.kind != TokenKind.AT_TYPE_IDENT) break;

        uint start_tok = p.pos;
        String attr_name = p.token_text(t);
        advance(p)!;

        uint arg_count = 0;
        uint args_ex = 0;

        if (consume(p, TokenKind.LPAREN)!)
        {
            List{uint} args;
            args.tinit(4);
            defer args.free();

            while (true)
            {
                Node expr = 0;
                Token curr = p.current();

                switch (curr.kind)
                {
                    case TokenKind.LBRACKET: // Handles [] and []=
                        advance(p)!;
                        expect(p, TokenKind.RBRACKET)!;
                        if (consume(p, TokenKind.EQ)!) 
                        {
                            expr = ast::add_node(p.ast, NodeKind.OP_OVERLOAD, curr.pos, (uint)OverloadKind.ELEMENT_SET);
                        }
                        else
                        {
                            expr = ast::add_node(p.ast, NodeKind.OP_OVERLOAD, curr.pos, (uint)OverloadKind.ELEMENT_AT);
                        }
                        break;
                    case TokenKind.AMP: // Handles &[]
                        if (p.peek(1).kind == TokenKind.LBRACKET) 
                        {
                            advance(p)!; // &
                            advance(p)!; // [
                            expect(p, TokenKind.RBRACKET)!;
                            expr = ast::add_node(p.ast, NodeKind.OP_OVERLOAD, curr.pos, (uint)OverloadKind.ELEMENT_REF);
                        } 
                        else
                        {
                            advance(p)!;
                            expr = ast::add_node(p.ast, NodeKind.OP_OVERLOAD, curr.pos, (uint)get_overload_from_token(curr.kind));
                        }
                        break;
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
                        // If the NEXT token is ')', it's an operator name, not an expression
                        if (p.peek(1).kind == TokenKind.RPAREN || p.peek(1).kind == TokenKind.COMMA) 
                        {
                            OverloadKind overload_kind = get_overload_from_token(curr.kind);
                            expr = ast::add_node(p.ast, NodeKind.OP_OVERLOAD, curr.pos, (uint)overload_kind);
                            advance(p)!;
                        } 
                        else
                        {
                            expr = parse_expr(p, 0)!;
                        }
                        break;
                    default:
                        // Standard constant expression (e.g., @doc("string"))
                        expr = parse_expr(p, 0)!;
                        break;
                }

                if (expr) args.push((uint)expr);
                if (consume(p, TokenKind.RPAREN)!) break;
                expect(p, TokenKind.COMMA)!;
            }

            arg_count = (uint)args.len();
            args_ex = ast::push_extra_block(p.ast, args.array_view());
        }

        uint[*] attr_block = {
            (uint)common::get_attribute_from_string(attr_name),
            args_ex,
            arg_count,
            (uint)head
        };
        uint ex = ast::push_extra_block(p.ast, &attr_block);
        head = ast::add_node(p.ast, NodeKind.ATTRIBUTE, start_tok, ex);
    }

    return head;
}

fn Node? parse_enum(Parser* p)
{
    uint start_tok = p.pos;
    expect(p, TokenKind.ENUM)!;

    Token name_tok = p.current();
    expect(p, TokenKind.TYPE_IDENT)!;
    uint name = p.pool.intern(p.token_text(name_tok));

    Node base_type;
    if (consume(p, TokenKind.COLON)!) base_type = parse_type(p)!;

    uint param_count = 0;
    Node params_start;
    if (p.is(TokenKind.LPAREN))
    {
        params_start = parse_parameter_list(p, &param_count)!;
    }

    Node attrs = parse_attributes(p)!;

    expect(p, TokenKind.LBRACE)!;

    List{uint} elements;
    elements.tinit(16);
    defer elements.free();
    
    while (!p.is(TokenKind.RBRACE) && !p.eof())
    {
        Token elem_tok = p.current();
        uint elem_name = p.pool.intern(p.token_text(elem_tok));
        advance(p)!;

        //  WAITING = 0
        Node explicit_val;
        if (consume(p, TokenKind.EQ)!) explicit_val = parse_expr(p, 0)!;

        // { "waiting" }
        Node assoc_init = 0;
        if (p.is(TokenKind.LBRACE)) assoc_init = parse_initializer_list(p)!;

        uint[3] member_data = { elem_name, (uint)explicit_val, (uint)assoc_init };
        elements.push(ast::push_extra_block(p.ast, &member_data));

        if (!consume(p, TokenKind.COMMA)!) break;
    }

    expect(p, TokenKind.RBRACE)!;

    uint element_count = (uint)elements.len();
    uint elements_ex = ast::push_extra_block(p.ast, elements.array_view());

    uint[*] decl_data = { 
        name, 
        (uint)base_type, 
        (uint)param_count,
        (uint)params_start,
        (uint)attrs, 
        elements_ex, 
        element_count 
    };
    uint ex = ast::push_extra_block(p.ast, &decl_data);
    return ast::add_node(p.ast, NodeKind.ENUM_DECL, start_tok, ex);
}

fn Node? parse_fn_decl(Parser* p, bool is_extern = false)
{
    uint start_tok = p.pos;

    expect(p, TokenKind.FN)!;
    log::debug("parse_fn_decl - parse_type");
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

    log::debug("parse_fn_decl - %s", p.pool.get(name));

    uint param_count = 0;
    Node params_start;
    params_start = parse_parameter_list(p, &param_count)!;

    log::debug("parse_fn_decl - parse_attributes");
    Node attr = parse_attributes(p)!;

    Node body;
    if (p.is(TokenKind.LBRACE)) 
    {
        log::debug("parse_fn_decl - parse_compound");
        body = parse_compound(p)!;
    } 
    else if (consume(p, TokenKind.IMPLIES)!) // Handle the => syntax
    {
        log::debug("parse_fn_decl - parse_short_body");
        body = parse_expr(p)!;
        expect(p, TokenKind.EOS)!;
    }
    else 
    {
        expect(p, TokenKind.EOS)!;
    }
    
    uint[7] final_block;
    final_block[0] = name;
    final_block[1] = method_type;
    final_block[2] = (uint)ret_type;
    final_block[3] = (uint)attr;
    final_block[4] = param_count;
    final_block[5] = (uint)params_start;
    final_block[6] = (uint)body;

    log::debug("parse_fn_decl - finished.. adding to ast");
    uint ex = ast::push_extra_block(p.ast, &final_block);
    return ast::add_node(p.ast, NodeKind.FN_DECL, start_tok, ex);
}

fn Node? parse_function_type(Parser* p)
{
    uint pos = p.current().pos;
    expect(p, TokenKind.FN)!;

    Node return_type = parse_type(p)!;

    uint param_count;
    Node params = parse_parameter_list(p, &param_count)!;

    uint[*] data = { (uint)return_type, param_count, (uint)params };
    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, NodeKind.TYPE_FUNCTION, pos, ex);
}

fn Node? parse_macro_decl(Parser* p)
{
    uint start_tok = p.pos;
    expect(p, TokenKind.MACRO)!;

	Node rtype = 0;
    Node method_type = 0;
	uint name; // name of fn

	///log::info("parse_macro_decl - current : %s", p.current().kind);
	///log::info("parse_macro_decl - 1 : %s", p.peek().kind);
	///log::info("parse_macro_decl - 2 : %s", p.peek(2).kind);

	if ((p.is(TokenKind.IDENT) || p.is(TokenKind.AT_IDENT)) && p.peek(1).kind != TokenKind.DOT)
    {
        name = p.pool.intern(p.token_text(p.current()));
        advance(p)!;
    }
    else 
    {
        rtype = parse_type(p)!;

        if (!p.is(TokenKind.DOT) && !p.is(TokenKind.IDENT) && !p.is(TokenKind.AT_IDENT))
        {
            method_type = parse_type(p)!;
        }

        if (consume(p, TokenKind.DOT)!)
        {
            if (!method_type.is_valid())
            {
                method_type = rtype;
                rtype = 0;
            }
        }

        if (!p.is(TokenKind.IDENT) && !p.is(TokenKind.AT_IDENT))
        {
            p.error("Expected macro name, got %s", p.token_text(p.current()));
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
        (uint)rtype, 
        (uint)method_type, 
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

fn Node? parse_var_decl(Parser* p)
{
    Token t = p.current();
    advance(p)!;

    Token name_tok = p.current();
    if (name_tok.kind != TokenKind.IDENT 
		&& name_tok.kind != TokenKind.CT_IDENT &&
		name_tok.kind != TokenKind.CT_TYPE_IDENT)
    {
        p.error("Expected identifier after 'var'");
        return 0;
    }
    advance(p)!;

    Node init = 0;
    if (p.current().kind == TokenKind.EQ)
    {
        advance(p)!; // consume '='
        init = parse_expr(p, 0)!;
    }

    expect(p, TokenKind.EOS)!;

    uint name_sh = p.pool.intern(p.token_text(name_tok));
    uint[2] data = { name_sh, (uint)init };
    uint ex = ast::push_extra_block(p.ast, &data);

    NodeKind nk = (name_tok.kind == TokenKind.CT_IDENT) 
                  ? NodeKind.CT_VAR_DECL 
                  : NodeKind.VAR_DECL;

    return ast::add_node(p.ast, nk, t.pos, ex);
}

<*
	TYPE_EXPR - unresolved type, parser only cares about the syntax
*>
fn Node? parse_type(Parser* p)
{
    uint start_tok = p.pos;
	Token current = p.current();
	TypeDescriptor desc;
	TypeFlags flags;

	// Check for Compile-Time
    if (current.kind == TokenKind.CT_TYPEOF || 
		current.kind == TokenKind.CT_TYPEFROM || 
        current.kind == TokenKind.CT_EVALTYPE)
    {
        advance(p)!;
        expect(p, TokenKind.LPAREN)!;
        desc.base_expr = parse_expr(p, 0)!;
        expect(p, TokenKind.RPAREN)!;
        flags.is_comptime = true;
    }
	else if (current.kind == TokenKind.CT_VATYPE)
	{
		advance(p)!;
        expect(p, TokenKind.LBRACKET)!;
        desc.base_expr = parse_expr(p, 0)!;
        expect(p, TokenKind.RBRACKET)!;
        flags.is_comptime = true;
	}
	else
	{
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
				desc.array_size = 0;
			}
            else if (p.is(TokenKind.RBRACKET))
            {
                desc.array_size = 0;
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
    Node new_node = ast::add_node(p.ast, NodeKind.TYPE_EXPR, start_tok, ex);

	return new_node;
}

<*
    typedef_declaration ::= ALIAS TYPE_IDENT attributes? '=' typedef_type ';'

    typedef_type ::= func_typedef | type generic_params?
    func_typedef ::= 'fn' optional_type parameter_type_list
*>
fn Node? parse_type_alias(Parser* p)
{
    uint start_tok = p.pos;
    expect(p, TokenKind.ALIAS)!;

	Token name_tok = p.current();
    
    if (!p.is(TokenKind.TYPE_IDENT))
    {
        p.error("Expected Type identifier");
        return UNEXPECTED_TOKEN~;
    }

    expect(p, TokenKind.TYPE_IDENT)!;
    uint name_sh = p.pool.intern(p.token_text(name_tok));

    Node attr = parse_attributes(p)!;

    expect(p, TokenKind.EQ)!;

    Node target_type;
    if (p.is(TokenKind.FN))
    {
        target_type = parse_function_type(p)!;
    }
    else
    {
        target_type = parse_type(p)!;
    }

    expect(p, TokenKind.EOS)!;

    uint[*] data = { name_sh, (uint)target_type, (uint)attr };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.TYPE_ALIAS_DECL, start_tok, ex);
}

<*
    define_ident ::= 'alias' (IDENT | CONST_IDENT | AT_IDENT) attributes? '=' (('module' path) | identifier_alias generic_params?)
    identifier_alias ::= path? (IDENT | CONST_IDENT | AT_IDENT)
*>
fn Node? parse_ident_alias(Parser* p)
{
    uint start_tok = p.pos;
    expect(p, TokenKind.ALIAS)!;

    TokenKind kind = p.current().kind;
    if (kind != TokenKind.IDENT && kind != TokenKind.CONST_IDENT && kind != TokenKind.AT_IDENT)
    {
        p.error("A type, variable, constant or attribute name was expected");
        return UNEXPECTED_TOKEN~;
    }

    uint name = p.pool.intern(p.token_text(p.current()));

    advance(p)!;

    Node attr = parse_attributes(p)!;

    expect(p, TokenKind.EQ)!;

    if (p.is(TokenKind.MODULE))
    {
        advance(p)!; // skip module

        Node path = parse_path(p)!;

        uint[*] data = { name, (uint)path, (uint)attr };
        uint ex = ast::push_extra_block(p.ast, &data);

        return ast::add_node(p.ast, NodeKind.PATH_ALIAS_DECL, start_tok, ex);
    }

    Node expr = parse_expr(p)!;
    
    uint[*] data = { name, (uint)expr, (uint)attr };
    uint ex = ast::push_extra_block(p.ast, &data);

    return ast::add_node(p.ast, NodeKind.TYPE_ALIAS_DECL, start_tok, ex);
}

fn Node? parse_alias(Parser* p)
{
    switch (p.peek(1).kind)
    {
        case TokenKind.TYPE_IDENT:
            return parse_type_alias(p);
        default:
            return parse_ident_alias(p);
    }
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