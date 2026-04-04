module c3_parser::parser;

import c3_parser::ast;
import lexer;

import std::io;
import std::collections::list;

<*
	@param [&inout] lbp : "Left binding power"
	@param [&inout] rbp : "Right binding power"
*>
fn void get_binding_power(TokenKind type, int* lbp, int* rbp)
{
    switch (type)
    {
		case TokenKind.BUILTIN:
			*lbp = 90; *rbp = 91;
			break;
        case TokenKind.EQ:
        case TokenKind.PLUS_ASSIGN:
        case TokenKind.MINUS_ASSIGN:
        case TokenKind.DIV_ASSIGN:
            *lbp = 10; *rbp = 9; // Right-associative (RBP < LBP)
            break;
		
		case TokenKind.BIT_OR: // |
		case TokenKind.BIT_XOR: // ^
		case TokenKind.AMP: // &
		case TokenKind.BIT_NOT: // ~
			*lbp = 40; *rbp = 41; // Higher than logic, lower than add/sub
			break;

		case TokenKind.EQEQ: // ==
		case TokenKind.NOT_EQUAL: // !=
			*lbp = 30; *rbp = 31;
			break;

		case TokenKind.OR: // ||
			*lbp = 10; *rbp = 11;
			break;

		case TokenKind.AND:
			*lbp = 24; *rbp = 25;
            break;

        case TokenKind.PLUS:
        case TokenKind.MINUS:
            *lbp = 50; *rbp = 51;
            break;

        case TokenKind.ASTERISK:
        case TokenKind.DIV:
            *lbp = 60; *rbp = 61;
            break;

		case TokenKind.GREATER:
		case TokenKind.GREATER_EQ:
		case TokenKind.LESS:
		case TokenKind.LESS_EQ:
            *lbp = 30; *rbp = 31;
			break;

        case TokenKind.DOT:
        case TokenKind.LPAREN:   // Function call
        case TokenKind.LBRACKET: // Array index
            *lbp = 80; *rbp = 81;
            break;
		case TokenKind.QUESTION:
			*lbp = 20; *rbp = 19; // Right-associative
			break;
        default:
            *lbp = -1; *rbp = -1; // Not an infix operator
            break;
    }
}

fn Node? parse_prefix_expr(Parser* p)
{
    Token t = p.current();

	if (is_type(t.kind))
	{
		return parse_type(p)!;
	}

    switch (t.kind)
    {	
		case TokenKind.BUILTIN:
		{
			advance(p)!;
            Token next = p.current();

			// parse ident
            Node ident_node = parse_expr(p, 80)!; 

            uint[2] data = { (uint)t.kind, (uint)ident_node };
            uint ex = ast::push_extra_block(p.ast, &data);

            if (next.kind == TokenKind.CONST_IDENT)
            {
                return ast::add_node(p.ast, NodeKind.COMPILER_CONST_EXPR, t.pos, ex);
            }
            
            return ast::add_node(p.ast, NodeKind.BUILTIN_EXPR, t.pos, ex);
		}
		case TokenKind.IDENT:
		case TokenKind.CONST_IDENT:
		case TokenKind.TYPE_IDENT:
		case TokenKind.CT_IDENT:
		case TokenKind.CT_CONST_IDENT:
		case TokenKind.CT_TYPE_IDENT:
		case TokenKind.AT_IDENT:
		case TokenKind.AT_CONST_IDENT:
		case TokenKind.AT_TYPE_IDENT:
		case TokenKind.HASH_IDENT:
		case TokenKind.HASH_CONST_IDENT:
		case TokenKind.HASH_TYPE_IDENT:
        {
            // Handle namespaced paths like MyModule::my_var
            if (p.peek().kind == TokenKind.SCOPE)
            {
                return parse_path(p)!;
            }

            advance(p)!;
            uint sh = p.pool.intern(p.token_text(t));
            return ast::add_node(p.ast, NodeKind.IDENT_EXPR, t.pos, sh);
        }
		// getting the actual literal value is up to the semantic analysis
		case TokenKind.STRING:
			String text = p.token_text(t);
			uint sh = p.pool.intern(text);
			advance(p)!;
            return ast::add_node(p.ast, NodeKind.STRING_LITERAL, t.pos, sh);
		case TokenKind.TRUE:
        {
            advance(p)!;
            return ast::add_node(p.ast, NodeKind.BOOL_LITERAL, t.pos, 1);
        }
        case TokenKind.FALSE:
        {
            advance(p)!;
            return ast::add_node(p.ast, NodeKind.BOOL_LITERAL, t.pos, 0);
        }
		case TokenKind.REAL:
			String text = p.token_text(t);
			uint sh = p.pool.intern(text);
			advance(p)!;
            return ast::add_node(p.ast, NodeKind.FLOAT_LITERAL, t.pos, sh);

        case TokenKind.INTEGER:
			String text = p.token_text(t);
			uint sh = p.pool.intern(text);
			advance(p)!;
            return ast::add_node(p.ast, NodeKind.INT_LITERAL, t.pos, sh);
		case TokenKind.BANG:
        case TokenKind.MINUS:
		case TokenKind.BIT_NOT:
		case TokenKind.AMP:
		case TokenKind.ASTERISK:
			advance(p)!;
			// Unary operators usually have very high binding power
			Node rhs = parse_expr(p, 70)!;

			uint[2] data = { (uint)t.kind, (uint)rhs };
			uint ex = ast::push_extra_block(p.ast, &data);
			return ast::add_node(p.ast, NodeKind.UNARY_EXPR, t.pos, ex);

        case TokenKind.LPAREN:
			// Check if cast: (Type)operand
            if (is_type(p.peek().kind))
            {
                advance(p)!; // consume '('
                Node type = parse_type(p)!;
                expect(p, TokenKind.RPAREN)!;
                
                Node operand = parse_expr(p, 70)!;

                uint[2] data = { (uint)type, (uint)operand };
                uint ex = ast::push_extra_block(p.ast, &data);
                
                return ast::add_node(p.ast, NodeKind.CAST_EXPR, t.pos, ex);
            }
            // Grouped expression: (1 + 2)
            advance(p)!; // consume '('
            Node expr = parse_expr(p, 0)!;
            expect(p, TokenKind.RPAREN)!;
            return expr;
		case TokenKind.CT_VATYPE:
		case TokenKind.CT_EVALTYPE:
		case TokenKind.CT_TYPEFROM:
		case TokenKind.CT_TYPEOF:
		{
			advance(p)!;
			
			expect(p, TokenKind.LPAREN)!;
			Node expr_inside = parse_expr(p, 0)!; 
			expect(p, TokenKind.RPAREN)!;

			return ast::add_node(p.ast, NodeKind.TYPE_EXPR, t.pos, (uint)expr_inside);
		}
        default:
            log::error("Expected expression for token: (%s - %s)", p.token_text(p.current()), p.current().kind);
            p.error("Expected expression");
			return EXPECTED_EXPRESSION~;
    }
}

fn Node? parse_infix(Parser* p, Node left, int rbp)
{
    Token t = p.current();
    advance(p)!;

    switch (t.kind)
    {
        case TokenKind.PLUS:
        case TokenKind.MINUS:
        case TokenKind.ASTERISK:
        case TokenKind.DIV:
        case TokenKind.EQ:
        case TokenKind.GREATER:
        case TokenKind.GREATER_EQ:
        case TokenKind.LESS:
        case TokenKind.LESS_EQ:
        case TokenKind.AND:
        case TokenKind.OR:
		case TokenKind.BIT_OR:  // Added
        case TokenKind.BIT_XOR: // Added
        case TokenKind.AMP:     // Added (&)
        case TokenKind.EQEQ:    // Added (==)
        case TokenKind.NOT_EQUAL: // Added (!=)
        {
            Node right = parse_expr(p, rbp)!;
            
            uint[3] data = { (uint)left, (uint)right, (uint)t.kind };
            uint ex = ast::push_extra_block(p.ast, &data);
            return ast::add_node(p.ast, NodeKind.BINARY_EXPR, t.pos, ex);
        }
        case TokenKind.LPAREN: // Function Call
        {
            return parse_call(p, t, left)!; 
        }
		case TokenKind.QUESTION:
		{
			return parse_ternary(p, left, t, rbp);
		}
		case TokenKind.DOT:
        {
			if (p.peek().kind == TokenKind.LBRACKET)
			{
				advance(p)!;
				Node index = parse_expr(p, 0)!;
				expect(p, TokenKind.RBRACKET)!;

				uint[2] data = { (uint)left, (uint)index };
				uint ex = ast::push_extra_block(p.ast, &data);
				return ast::add_node(p.ast, NodeKind.DEREF_SUBSCRIPT_EXPR, t.pos, ex);
			}

            // after a dot expect a member name
            Token member_token = p.current();
            // ensure we just get the name
            expect(p, TokenKind.IDENT)!; 
            
            uint sh = p.pool.intern(p.token_text(member_token));
            Node member_node = ast::add_node(p.ast, NodeKind.IDENT_EXPR, member_token.pos, sh);

            uint[2] data = { (uint)left, (uint)member_node };
            uint ex = ast::push_extra_block(p.ast, &data);
			return ast::add_node(p.ast, NodeKind.ACCESS_EXPR, t.pos, ex);        
		}
        default:
			log::error("Unexpected infix token: %s", t.kind);
			p.error("Unexpected infix token: %s", t.kind);
            return UNEXPECTED_TOKEN~;
    }
}

<*
	parse expressions recursively using Pratt parsing
	using Binding power.
	@param [&inout] p
	@param min_bp : "Starting binding power, always call with 0, it will call itself recursively with other values"
*>
fn Node? parse_expr(Parser* p, uint min_bp = 0)
{
    Node left = parse_prefix_expr(p)!;

    while (true)
    {
        int lbp, rbp;
		get_binding_power(p.current().kind, &lbp, &rbp);

		// If the next operator doesn't bind strongly enough to the left, we stop
		if (lbp < min_bp) break;

        left = parse_infix(p, left, rbp)!;
    }

    return left;
}

fn Node? parse_expr_resuming_with_left(Parser* p, Node left, uint min_bp)
{
    while (true)
    {
        int lbp, rbp;
        get_binding_power(p.current().kind, &lbp, &rbp);
        if (lbp < min_bp) break;

        left = parse_infix(p, left, rbp)!;
    }
    return left;
}

fn Node? parse_ternary(Parser* p, Node condition, Token t, int rbp)
{
    Node then_expr = parse_expr(p, 0)!;
    expect(p, TokenKind.COLON)!;
    
    Node else_expr = parse_expr(p, rbp)!; 

    uint[3] data = { (uint)condition, (uint)then_expr, (uint)else_expr };
    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, NodeKind.TERNARY_EXPR, t.pos, ex);
}

fn Node? parse_call(Parser* p, Token t, Node callee)
{
    List{uint} args;
    args.tinit(18);
    defer args.free();

	// allocate slot 0 and 1 to callee and args length
	args.push(0);
	args.push(0);

    if (p.current().kind != TokenKind.RPAREN)
    {
        while (true)
        {
            Node arg = parse_expr(p)!;
            args.push((uint)arg);

            if (p.current().kind != TokenKind.COMMA) break;
            advance(p)!;
        }
    }

    expect(p, TokenKind.RPAREN)!;

    args[0] = (uint)callee;
    args[1] = (uint)args.len() - 2;

    uint ex = ast::push_extra_block(p.ast, args.array_view());

    return ast::add_node(p.ast, NodeKind.CALL_EXPR, t.pos, ex);
}