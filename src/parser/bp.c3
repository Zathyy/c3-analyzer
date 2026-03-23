module c3_parser::parser;

import c3::lexer;
import c3_parser::ast;
import c3_parser::common;

<*
	@param [&inout] lbp : "Left binding power"
	@param [&inout] rbp : "Right binding power"
*>
fn void get_binding_power(TokenType type, int* lbp, int* rbp)
{
    switch (type)
    {
        case TokenType.EQ:
        case TokenType.PLUS_ASSIGN:
        case TokenType.MINUS_ASSIGN:
        case TokenType.DIV_ASSIGN:
            *lbp = 10; *rbp = 9; // Right-associative (RBP < LBP)
            break;

        case TokenType.OR:
            *lbp = 22; *rbp = 23; // Left-associative (RBP > LBP)
            break;
		
		case TokenType.AND:
			*lbp = 24; *rbp = 25;
            break;

        case TokenType.PLUS:
        case TokenType.MINUS:
            *lbp = 50; *rbp = 51;
            break;

        case TokenType.STAR:
        case TokenType.DIV:
            *lbp = 60; *rbp = 61;
            break;

		case TokenType.GREATER:
		case TokenType.GREATER_EQ:
		case TokenType.LESS:
		case TokenType.LESS_EQ:
            *lbp = 30; *rbp = 31;
			break;

        case TokenType.DOT:
        case TokenType.LPAREN:   // Function call
        case TokenType.LBRACKET: // Array index
            *lbp = 80; *rbp = 81;
            break;
		case TokenType.QUESTION:
			*lbp = 20; *rbp = 19; // Right-associative
			break;
        default:
            *lbp = -1; *rbp = -1; // Not an infix operator
            break;
    }
}

<*
	@ensure return != null
*>
fn Expr*? parse_infix(Parser* p, Expr* left, int rbp)
{
    TokenType type = p.current().type;
    SourceSpan start_span = left.span;

    switch (type)
    {
        case TokenType.PLUS:
        case TokenType.MINUS:
        case TokenType.STAR:
        case TokenType.DIV:
        case TokenType.EQ:
        case TokenType.GREATER:
        case TokenType.GREATER_EQ:
        case TokenType.LESS:
        case TokenType.LESS_EQ:
        case TokenType.AND:
        case TokenType.OR:
        {
            advance(p)!;
            Expr* right = parse_expr(p, rbp)!;
            return make_binary_expr(left, type, right);
        }

        case TokenType.LPAREN:
        {
            return parse_call(p, left)!;
        }
        case TokenType.QUESTION:
        {
            return parse_ternary(p, left, rbp)!;
        }

        default:
            p.error("Unexpected infix token: %s", type);
            return UNEXPECTED_TOKEN~;
    }
}

<*
	@ensure return != null
*>
fn Expr*? parse_prefix(Parser* p)
{
    TokenType type = p.current().type;
	SourceSpan op_span = p.span();

	if (is_type_start(type))
	{
		TypeInfo* info = parse_type(p)!;
        return make_type_expr(info);
	}

    switch (type)
    {
        case TokenType.IDENT: 
			return parse_ident(p)!;
        case TokenType.INTEGER:
		case TokenType.REAL:
		case TokenType.STRING:
			return parse_literal(p)!;
        
        case TokenType.BANG:
        case TokenType.MINUS:
        case TokenType.BIT_NOT:
		{
			advance(p)!;
			// Grab the operand with high "Right Binding Power"
			Expr* rhs = parse_expr(p, 70)!;
			return make_unary_expr(type, rhs, op_span);
		}
        case TokenType.LPAREN:
		{ 
			// check if Cast
			if (is_type_start(p.peek().type))
			{
				advance(p)!;
				TypeInfo* target_type = parse_type(p)!;
				expect(p, TokenType.RPAREN)!;
				// A cast has very high precedence (Unary level)
				Expr* operand = parse_expr(p, 70)!;
				return make_cast_expr(target_type, operand);
			}

			advance(p)!;
			Expr* e = parse_expr(p, 0)!; // Reset to 0 inside parens
			expect(p, TokenType.RPAREN)!;
			return e;
		}
        default:
            return UNEXPECTED_TOKEN~;
    }
}