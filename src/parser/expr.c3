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
        case TokenKind.EQ:
        case TokenKind.PLUS_ASSIGN:
        case TokenKind.MINUS_ASSIGN:
        case TokenKind.DIV_ASSIGN:
            *lbp = 10; *rbp = 9; // Right-associative (RBP < LBP)
            break;

        case TokenKind.OR:
            *lbp = 22; *rbp = 23; // Left-associative (RBP > LBP)
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

    switch (t.kind)
    {	
		// getting the actual literal value is up to the semantic analysis
		case TokenKind.STRING:
			String text = p.token_text(t);
			uint sh = p.pool.intern(text);
			advance(p)!;
            return ast::add_node(p.ast, NodeKind.STRING_LITERAL, t.pos, sh);

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

        case TokenKind.IDENT:
			// path::call()
			if (p.peek().kind == TokenKind.SCOPE)
			{
				Node path = parse_path(p)!;
				return path;
			}
			advance(p)!;
            uint sh = p.pool.intern(p.token_text(t));
            return ast::add_node(p.ast, NodeKind.IDENT_EXPR, t.pos, sh);

		case TokenKind.BANG:
        case TokenKind.MINUS:
		case TokenKind.BIT_NOT:
			advance(p)!;
			// Unary operators usually have very high binding power
			Node rhs = parse_expr(p, 70)!;

			uint[2] data = { (uint)t.kind, (uint)rhs };
			uint ex = ast::push_extra_block(p.ast, &data);
			return ast::add_node(p.ast, NodeKind.UNARY_EXPR, t.pos, ex);

        case TokenKind.LPAREN:
			// Check if cast
			if (is_type(p.peek().kind))
			{
				advance(p)!;
				Node type = parse_type(p)!;
				expect(p, TokenKind.RPAREN)!;
				// A cast has very high precedence (Unary level)	
				Node operand = parse_expr(p, 70)!;

				unreachable("not implemented!");
			}
            Node expr = parse_expr(p, 0)!;
            expect(p, TokenKind.RPAREN)!;
            return expr;

        default:
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
        default:
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