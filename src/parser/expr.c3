<*
	Pratt parsing using Binding power
	
	Resources for Binding power pratt parsing:
	- https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html
*>
module c3_parser::parser;

import c3_parser::ast;
import lexer;

import std::io;
import std::collections::list;

<*
	Should be aligned to C3C
	According to: https://c3-lang.org/language-rules/precedence/
*>
constdef Precedence : inline int
{
    NONE       = -1,
	LOWEST     = 0,
    ASSIGN     = 10, // Level 11
    TERNARY    = 20, // Level 10 (?: , ??)
    LOGIC_OR   = 30, // Level 9  (||)
    LOGIC_AND  = 40, // Level 8  (&&)
    COMPARE    = 50, // Level 7  (==, <, etc)
    SUM        = 60, // Level 6  (+, -)
    BITWISE    = 70, // Level 5  (&, |, ^)
    SHIFT      = 80, // Level 4  (<<, >>)
    PRODUCT    = 90, // Level 3  (*, /, %)
    UNARY      = 100,// Level 2  (prefix -, !, ~, etc)
    CALL       = 110,// Level 1  (., (), [], !!)
}

<*
	@param [&inout] lbp : "How strongly the operator pulls on the expression to its left."
	@param [&inout] rbp : "How strongly it pulls on the expression to its right."
*>
fn void get_binding_power(TokenKind type, int* lbp, int* rbp)
{
    switch (type)
    {
        // Assignment (Right-associative)
        case TokenKind.EQ:
        case TokenKind.PLUS_ASSIGN:
        case TokenKind.MINUS_ASSIGN:
        case TokenKind.BIT_OR_ASSIGN:
        case TokenKind.BIT_XOR_ASSIGN:
        case TokenKind.DIV_ASSIGN:
        case TokenKind.MOD_ASSIGN:
        case TokenKind.BIT_AND_ASSIGN:
        case TokenKind.LSHIFT_ASSIGN:
        case TokenKind.RSHIFT_ASSIGN:
            *lbp = Precedence.ASSIGN; 
            *rbp = Precedence.ASSIGN - 1; 
            break;

        case TokenKind.QUESTION:
        case TokenKind.QUESTQUEST:
		case TokenKind.ELVIS:
            *lbp = Precedence.TERNARY; 
            *rbp = Precedence.TERNARY - 1;
            break;

        case TokenKind.OR:
        case TokenKind.CT_TERNARY:
            *lbp = Precedence.LOGIC_OR; 
            *rbp = Precedence.LOGIC_OR + 1;
            break;

        case TokenKind.AND:
        case TokenKind.CT_AND_OP:
            *lbp = Precedence.LOGIC_AND;
            *rbp = Precedence.LOGIC_AND + 1;
            break;

        // Comparison
        case TokenKind.EQEQ:
        case TokenKind.NOT_EQUAL:
        case TokenKind.GREATER:
        case TokenKind.GREATER_EQ:
        case TokenKind.LESS:
        case TokenKind.LESS_EQ:
            *lbp = Precedence.COMPARE; 
            *rbp = Precedence.COMPARE + 1;
            break;

        // Sum
        case TokenKind.PLUS:
        case TokenKind.MINUS:
        case TokenKind.CT_CONCAT_OP:
            *lbp = Precedence.SUM; 
            *rbp = Precedence.SUM + 1;
            break;

        // Bitwise
        case TokenKind.BIT_OR:
        case TokenKind.BIT_XOR:
        case TokenKind.AMP: // Bitwise AND
            *lbp = Precedence.BITWISE; 
            *rbp = Precedence.BITWISE + 1;
            break;

        // Shift
        case TokenKind.RSHIFT:
        case TokenKind.LSHIFT:
            *lbp = Precedence.SHIFT; 
            *rbp = Precedence.SHIFT + 1;
            break;

        // Product
        case TokenKind.ASTERISK:
        case TokenKind.DIV:
        case TokenKind.MOD:
            *lbp = Precedence.PRODUCT; 
            *rbp = Precedence.PRODUCT + 1;
            break;

        // Access and Postfix
        case TokenKind.DOT:
        case TokenKind.LPAREN:
        case TokenKind.LBRACKET:
        case TokenKind.BANGBANG:
        case TokenKind.PLUSPLUS:
        case TokenKind.MINUSMINUS:
        case TokenKind.BANG:
		case TokenKind.BIT_NOT:
            *lbp = Precedence.CALL;
            *rbp = Precedence.LOWEST; // Postfix has no RHS to pull
            break;

        default:
            *lbp = Precedence.NONE; 
            *rbp = Precedence.NONE;
            break;
    }
}

<*
	parse_prefix (Nud) 
	Handles tokens that start an expression (e.g., -5, (expr), !true)
	It has no "left" side to worry about.
*>
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
            Node ident_node = parse_expr(p, Precedence.PRODUCT)!; 

            uint[2] data = { (uint)t.kind, (uint)ident_node };
            uint ex = ast::push_extra_block(p.ast, &data);

            if (next.kind == TokenKind.CONST_IDENT)
            {
                return ast::add_node(p.ast, NodeKind.COMPILER_CONST_EXPR, t.pos, ex);
            }
            
            return ast::add_node(p.ast, NodeKind.BUILTIN_EXPR, t.pos, ex);
		}
		case TokenKind.NULL:
		{
			uint pos = t.pos;
			advance(p)!;
			return ast::add_node(p.ast, NodeKind.NULL_LITERAL, pos, 0); 
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
                return parse_path_prefix(p)!;
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
			Node rhs = parse_expr(p, Precedence.UNARY)!;

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
                
                Node operand = parse_expr(p, Precedence.UNARY)!;

                uint[2] data = { (uint)type, (uint)operand };
                uint ex = ast::push_extra_block(p.ast, &data);
                
                return ast::add_node(p.ast, NodeKind.CAST_EXPR, t.pos, ex);
            }
            // Grouped expression: (1 + 2)
            advance(p)!; // consume '('
            Node expr = parse_expr(p)!;
            expect(p, TokenKind.RPAREN)!;
            return expr;
		case TokenKind.CT_VATYPE:
		case TokenKind.CT_EVALTYPE:
		case TokenKind.CT_TYPEFROM:
		case TokenKind.CT_TYPEOF:
		{
			advance(p)!;
			
			expect(p, TokenKind.LPAREN)!;
			Node expr_inside = parse_expr(p)!; 
			expect(p, TokenKind.RPAREN)!;

			return ast::add_node(p.ast, NodeKind.TYPE_EXPR, t.pos, (uint)expr_inside);
		}
		case TokenKind.LBRACE:
			return parse_initializer_list(p)!;
		case TokenKind.MINUSMINUS:
		case TokenKind.PLUSPLUS:
		{
			advance(p)!;
			Node right = parse_expr(p, Precedence.CALL)!;
			uint[2] data = { 
				(uint)t.kind, 
				(uint)right 
			};
			
			uint ex = ast::push_extra_block(p.ast, &data);
			return ast::add_node(p.ast, NodeKind.PRE_UNARY_EXPR, t.pos, ex);
		}
        default:
            log::error("parse_prefix_expr - Expected expression for token: (%s - %s)", p.token_text(p.current()), p.current().kind);
            p.error("Expected expression");
			return EXPECTED_EXPRESSION~;
    }
}

<*
	parse_infix (Led)
	Handles tokens that connect expressions (e.g. 1 + 2, obj.prop, arr[0])
	It takes a pre-parsed "left" node and attaches a "right" side to it.
*>
fn Node? parse_infix(Parser* p, Node left, Precedence rbp)
{
    Token t = p.current();

    switch (t.kind)
    {
        case TokenKind.PLUS:
        case TokenKind.PLUS_ASSIGN:
        case TokenKind.MINUS:
        case TokenKind.MINUS_ASSIGN:
        case TokenKind.ASTERISK:
        case TokenKind.MULT_ASSIGN:
        case TokenKind.DIV:
        case TokenKind.DIV_ASSIGN:
        case TokenKind.MOD:
        case TokenKind.MOD_ASSIGN:
        case TokenKind.EQ:
        case TokenKind.GREATER:
        case TokenKind.GREATER_EQ:
        case TokenKind.LESS:
        case TokenKind.LESS_EQ:
        case TokenKind.AND:
        case TokenKind.OR:
        case TokenKind.BIT_OR:
        case TokenKind.BIT_XOR:
        case TokenKind.BIT_XOR_ASSIGN:
        case TokenKind.BIT_OR_ASSIGN:
        case TokenKind.AMP:
        case TokenKind.BIT_AND_ASSIGN:
        case TokenKind.EQEQ:
        case TokenKind.NOT_EQUAL:
        case TokenKind.RSHIFT:
        case TokenKind.LSHIFT:
        {
            advance(p)!;
            Node right = parse_expr(p, rbp)!;
            
            uint[3] data = { (uint)left, (uint)right, (uint)t.kind };
            uint ex = ast::push_extra_block(p.ast, &data);
            return ast::add_node(p.ast, NodeKind.BINARY_EXPR, t.pos, ex);
        }
		case TokenKind.PLUSPLUS:
		case TokenKind.MINUSMINUS:
		case TokenKind.BANG:
		case TokenKind.BANGBANG:
		{
			advance(p)!;
			uint[2] data = { 
				(uint)t.kind, 
				(uint)left 
			};
			
			uint ex = ast::push_extra_block(p.ast, &data);
			return ast::add_node(p.ast, NodeKind.POST_UNARY_EXPR, t.pos, ex);
		}
        case TokenKind.LPAREN: 
        {
            advance(p)!;
            return parse_call(p, t, left)!; 
        }
        case TokenKind.QUESTION:
        {
            advance(p)!;
            return parse_ternary(p, left, t, rbp);
        }
        case TokenKind.DOT:
        {
            advance(p)!;
            Token member_token = p.current();
            if ((!is_type(member_token.kind)) && member_token.kind != TokenKind.IDENT && member_token.kind != TokenKind.CONST_IDENT)
            {
                p.error("Expected identifier after '.' got: %s", p.token_text(member_token));
                return UNEXPECTED_TOKEN~;
            }
            advance(p)!;

            uint sh = p.pool.intern(p.token_text(member_token));
            Node member_node = ast::add_node(p.ast, NodeKind.IDENT_EXPR, member_token.pos, sh);

            uint[2] data = { (uint)left, (uint)member_node };
            uint ex = ast::push_extra_block(p.ast, &data);
            return ast::add_node(p.ast, NodeKind.ACCESS_EXPR, t.pos, ex);        
        }
        case TokenKind.BIT_NOT:
        {
            advance(p)!;
            if (ast::get_kind(p.ast, left) == NodeKind.TYPE_EXPR)
            {
                p.error("Expected a fault before '~'");
                return UNEXPECTED_TOKEN~;
            }
            return ast::add_node(p.ast, NodeKind.OPTIONAL_EXPR, t.pos, (uint)left);
        }
        case TokenKind.LBRACKET: 
        {
            advance(p)!;
			return parse_range(p, left, t.pos)!;
        }
        default:
            p.error("Unexpected infix token: %s", t.kind);
            return UNEXPECTED_TOKEN~;
    }
}

<*
	parse expressions recursively with Pratt parsing
	using Binding power.
	@param [&inout] p
	@param min_bp : "Starting binding power, always call with 0, it will call itself recursively with other values"
*>
fn Node? parse_expr(Parser* p, Precedence min_bp = LOWEST)
{
    Node left = parse_prefix_expr(p)!;

    while (true)
    {
        int lbp, rbp;
		get_binding_power(p.current().kind, &lbp, &rbp);

		// debug purposes
		log::debug("Current Token: %s, LBP: %d, MinBP: %d", p.current().kind, lbp, min_bp);

		// If the next operator doesn't bind strongly enough to the left
		if (lbp < (int)min_bp) break;

        left = parse_infix(p, left, (Precedence)rbp)!;
    }

	// Check for Postfix Attributes
    // only if min_bp is 0
	if (min_bp == 0 && p.is(TokenKind.AT_IDENT))
	{
		Node attr = parse_attributes(p)!;
        uint[2] data = { (uint)left, (uint)attr };
        uint ex = ast::push_extra_block(p.ast, &data);
        left = ast::add_node(p.ast, NodeKind.ATTRIBUTED_EXPR, p.current().pos, ex);
	}

    return left;
}

<*
	"Shortcut" for when a left node has already been parsed (like an identifier) 
	and want to continue building an expression from that specific point without starting over
*>
fn Node? parse_expr_resuming_with_left(Parser* p, Node left, uint min_bp)
{
    while (true)
    {
        int lbp, rbp;
        get_binding_power(p.current().kind, &lbp, &rbp);
        if (lbp < min_bp) break;

        left = parse_infix(p, left, (Precedence)rbp)!;
    }
    return left;
}

fn Node? parse_ternary(Parser* p, Node condition, Token t, Precedence rbp)
{
    Node then_expr = parse_expr(p, Precedence.LOWEST)!;
    expect(p, TokenKind.COLON)!;
    
    Node else_expr = parse_expr(p, rbp)!; 

    uint[3] data = { (uint)condition, (uint)then_expr, (uint)else_expr };
    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, NodeKind.TERNARY_EXPR, t.pos, ex);
}

<*
	TODO: needs more safety checks?
*>
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
			Node arg_node;

			if (p.current().kind == TokenKind.IDENT && p.peek().kind == TokenKind.COLON)
			{
				Token name_tok = p.current();
                advance(p, 2)!;
                
                uint name = p.pool.intern(p.token_text(name_tok));
                Node value = parse_expr(p)!;
                
                uint[2] data = { name, (uint)value };
                uint ex = ast::push_extra_block(p.ast, &data);
                arg_node = ast::add_node(p.ast, NodeKind.NAMED_ARG_EXPR, name_tok.pos, ex);
			}
			else
			{
            	arg_node = parse_expr(p)!;
			}

			args.push((uint)arg_node);
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

fn Node? parse_initializer_list(Parser* p)
{
    uint start_tok = p.pos;
    expect(p, TokenKind.LBRACE)!;

	// Handle empty initializer {}
    if (consume(p, TokenKind.RBRACE)!)
    {
        return ast::add_node(p.ast, NodeKind.INITIALIZER_LIST, start_tok, 0);
    }

    List{uint} exprs;
    exprs.tinit(8);
    exprs.push(0); // reserve count	
    defer exprs.free();

    while (true)
    {
        Node expr;
        
        // Check for Designated Initializer: .member = value
        if (consume(p, TokenKind.DOT)!)
        {
            Token member = p.current();
            expect(p, TokenKind.IDENT)!; 
            uint member_name = p.pool.intern(p.token_text(member));
            
            expect(p, TokenKind.EQ)!;
            Node val = parse_expr(p)!;
            
            uint[2] data = { member_name, (uint)val };
            uint ex = ast::push_extra_block(p.ast, &data);
            expr = ast::add_node(p.ast, NodeKind.DESIGNATED_INITIALIZER_LIST, member.pos, ex);
        }
        else if (p.is(TokenKind.LBRACE))
        {
            expr = parse_initializer_list(p)!;
        }
        else
        {
            // standard expression
            expr = parse_expr(p)!;
        }

        exprs.push((uint)expr);

        if (consume(p, TokenKind.RBRACE)!) break;
        expect(p, TokenKind.COMMA)!;
        if (consume(p, TokenKind.RBRACE)!) break;
    }

    exprs[0] = (uint)exprs.len() - 1;
    uint ex = ast::push_extra_block(p.ast, exprs.array_view());
    
    return ast::add_node(p.ast, NodeKind.INITIALIZER_LIST, start_tok, ex);
}

fn Node? parse_range(Parser* p, Node left, uint start_pos)
{
    Node start = 0;
    Node end = 0;
    bool is_slice = false;

    // leading colon/range: [:5] or [..5]
    if (p.is(TokenKind.COLON) || p.is(TokenKind.DOTDOT))
    {
        is_slice = true;
        advance(p)!;

        // Check for hat in the end slot: [:^1]
        if (consume(p, TokenKind.BIT_XOR)!)
        {
            Node inner = parse_expr(p, Precedence.CALL)!; 
            uint[2] data = { (uint)TokenKind.BIT_XOR, (uint)inner };
            uint ex = ast::push_extra_block(p.ast, &data);
            end = ast::add_node(p.ast, NodeKind.PREFIX_EXPR, p.current().pos, ex);
        }
        else
        {
            end = parse_expr(p, Precedence.LOWEST)!;
        }
    }
    else
    {
        // Check for hat: [^5]
        if (consume(p, TokenKind.BIT_XOR)!)
        {
            Node inner = parse_expr(p, Precedence.CALL)!; 
            uint[2] data = { (uint)TokenKind.BIT_XOR, (uint)inner };
            uint ex = ast::push_extra_block(p.ast, &data);
            start = ast::add_node(p.ast, NodeKind.PREFIX_EXPR, p.current().pos, ex);
        }
        else
        {
            start = parse_expr(p, Precedence.LOWEST)!;
        }
        
        //  [start:end] or [start..end]
        if (p.is(TokenKind.COLON) || p.is(TokenKind.DOTDOT))
        {
            is_slice = true;
            advance(p)!;

            // [0:5], [0:^1], or [0:]
            if (!p.is(TokenKind.RBRACKET))
            {
                if (consume(p, TokenKind.BIT_XOR)!)
                {
                    Node inner = parse_expr(p, Precedence.CALL)!; 
                    uint[2] data = { (uint)TokenKind.BIT_XOR, (uint)inner };
                    uint ex = ast::push_extra_block(p.ast, &data);
                    end = ast::add_node(p.ast, NodeKind.PREFIX_EXPR, p.current().pos, ex);
                }
                else
                {
                    end = parse_expr(p, Precedence.LOWEST)!;
                }
            }
        }
    }

    expect(p, TokenKind.RBRACKET)!;

    if (is_slice)
    {
        uint[2] slice_data = { (uint)start, (uint)end };
        uint slice_ex = ast::push_extra_block(p.ast, &slice_data);
        Node slice_node = ast::add_node(p.ast, NodeKind.SLICE_EXPR, start_pos, slice_ex);

        uint[2] access_data = { (uint)left, (uint)slice_node };
        uint access_ex = ast::push_extra_block(p.ast, &access_data);
        return ast::add_node(p.ast, NodeKind.INDEX_EXPR, start_pos, access_ex);
    }

    uint[2] data = { (uint)left, (uint)start };
    uint ex = ast::push_extra_block(p.ast, &data);
    return ast::add_node(p.ast, NodeKind.INDEX_EXPR, start_pos, ex);
}