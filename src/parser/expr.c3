<*
 Pratt parsing using Binding power
	
	Resources for Binding power pratt parsing:
	- https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html
*>
module c3_parser::parser;

import c3_parser::ast;
import lexer;
import std::core::ascii;

import c3_parser::common;

import std::io;
import std::collections::list;

<*
	Should be aligned to C3C
	According to: https://c3-lang.org/language-rules/precedence/
*>
constdef Precedence : inline int
{
	NONE           = -1,
	LOWEST         = 0,
	ASSIGNMENT     = 10, // =, *=, /=, %=, +=, etc
	TERNARY        = 20, // ?:
	OR             = 30, // || |||
	AND            = 40, // && &&&
	RELATIONAL     = 50, // < > <= >= == !=
	ADDITIVE       = 60, // + - +++
	ORELSE         = 70, // ?: ??
	BIT            = 80, // ^ | &
	SHIFT          = 90, // << >>
	MULTIPLICATIVE = 100, // * / %
	UNARY          = 110, // ! - + ~ * & prefix ++/--
	CALL           = 120, // . () [] postfix ++ -- !! ! ~
  HIGHEST        = 130,
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
		case EQ:
		case MULT_ASSIGN:
		case PLUS_ASSIGN:
		case MINUS_ASSIGN:
		case BIT_OR_ASSIGN:
		case BIT_XOR_ASSIGN:
		case DIV_ASSIGN:
		case MOD_ASSIGN:
		case BIT_AND_ASSIGN:
		case LSHIFT_ASSIGN:
		case RSHIFT_ASSIGN:
			*lbp = Precedence.ASSIGNMENT;
			*rbp = Precedence.ASSIGNMENT - 1;
			break;

		case CT_TERNARY:
		case QUESTION:
			*lbp = Precedence.TERNARY;
			*rbp = Precedence.TERNARY - 1;
			break;

		case OR:
		case CT_OR_OP:
			*lbp = Precedence.OR;
			*rbp = Precedence.OR + 1;
			break;

		case AND:
		case CT_AND_OP:
			*lbp = Precedence.AND;
			*rbp = Precedence.AND + 1;
			break;

		// RELATIONAL
		case EQEQ:
		case NOT_EQUAL:
		case GREATER:
		case GREATER_EQ:
		case LESS:
		case LESS_EQ:
			*lbp = Precedence.RELATIONAL;
			*rbp = Precedence.RELATIONAL + 1;
			break;

		// ADDITIVE
		case PLUS:
		case MINUS:
		case CT_CONCAT_OP:
			*lbp = Precedence.ADDITIVE;
			*rbp = Precedence.ADDITIVE + 1;
			break;

		case QUESTQUEST:
		case ELVIS:
			*lbp = Precedence.ORELSE;
			*rbp = Precedence.ORELSE + 1;
			break;

		// Bit
		case BIT_OR:
		case BIT_XOR:
		case AMP:
			*lbp = Precedence.BIT;
			*rbp = Precedence.BIT + 1;
			break;

		// Shift
		case RSHIFT:
		case LSHIFT:
			*lbp = Precedence.SHIFT;
			*rbp = Precedence.SHIFT + 1;
			break;

		// MULTIPLICATIVE
		case DIV:
		case MOD:
		case ASTERISK:
			*lbp = Precedence.MULTIPLICATIVE;
			*rbp = Precedence.MULTIPLICATIVE + 1;
			break;

		// Postfix / Access / Call
		case DOT:
		case SCOPE:
		case LPAREN:
		case LBRACE:
		case LBRACKET:
			*lbp = Precedence.CALL;
			*rbp = Precedence.CALL; //TODO: CALL or None?
			break;
		case BANGBANG:
		case PLUSPLUS:
		case MINUSMINUS:
		case BANG:
		case BIT_NOT:
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

	if (is_type(p))
	{
		return parse_type(p, { .type_as_expression = true })!;
	}

	switch (t.kind)
	{
		case BUILTIN:
		{
			advance(p)!;
			Token next = p.current();

			// parse ident
			Node ident_node = parse_expr(p, Precedence.MULTIPLICATIVE)!;

			uint[2] data = { (uint)t.kind, (uint)ident_node };
			uint ex = p.ast.push_extra_block(&data);

			if (next.kind == CONST_IDENT)
			{
				return p.ast.add_node(COMPILER_CONST_EXPR, t.pos, p.current_pos(), ex);
			}

			return p.ast.add_node(BUILTIN_EXPR, t.pos, p.current_pos(), ex);
		}
		case NULL:
		{
			advance(p)!;
			return p.ast.add_node(NULL_LITERAL, t.pos, t.pos, 0);
		}
		case FN: // lambda
		{
			return parse_lambda(p)!;
		}
		case BYTES:
		{
			return parse_bytes_expr(p)!;
		}
		case AT_IDENT:
		case AT_CONST_IDENT:
		case AT_TYPE_IDENT:
		case IDENT:
		case CONST_IDENT:
		case TYPE_IDENT:
		case CT_IDENT:
		case CT_CONST_IDENT:
		case CT_TYPE_IDENT:
		case HASH_IDENT:
		case HASH_CONST_IDENT:
		case HASH_TYPE_IDENT:
			// Handle namespaced paths like MyModule::my_var
			// and the new type properties ::
			if (p.peek().kind == SCOPE)
			{
				return parse_path_prefix(p)!;
			}

			advance(p)!;
			Token current = p.current();
			uint sh = p.pool.intern(p.token_text(t));
			return p.ast.add_node(IDENT_EXPR, t.pos, p.current_pos(), sh);

		// getting the actual literal value is up to the semantic analysis
		case STRING:
			String text = p.token_text(t);
			advance(p)!;
			while (p.is(STRING))
			{
				text = string::tformat("%s%s", text[..^2], p.token_text(p.current())[1..]);
				advance(p)!;
			}
			uint sh = p.pool.intern(text);
			return p.ast.add_node(STRING_LITERAL, t.pos, p.current_pos(), sh);
		
		case CHAR_LITERAL:
			String text = p.token_text(t);
			uint sh = p.pool.intern(text);
			advance(p)!;
			return p.ast.add_node(CHAR_LITERAL, t.pos, p.current_pos(), sh);

		case TRUE:
			advance(p)!;
			return p.ast.add_node(BOOL_LITERAL, t.pos, p.current_pos(), 1);

		case FALSE:
			advance(p)!;
			return p.ast.add_node(BOOL_LITERAL, t.pos, p.current_pos(), 0);

		case REAL:
			String text = p.token_text(t);
			uint sh = p.pool.intern(text);
			advance(p)!;
			return p.ast.add_node(FLOAT_LITERAL, t.pos, p.current_pos(), sh);

		case INTEGER:
			String text = p.token_text(t);
			uint sh = p.pool.intern(text);
			advance(p)!;
			return p.ast.add_node(INT_LITERAL, t.pos, p.current_pos(), sh);
		case BANG:
		case BANGBANG:
		case MINUS:
		case BIT_NOT:
		case AMP:
		case AND: // for the unary temp value pointer
		case ASTERISK:
			bool is_bang_bang = p.is(BANGBANG);
			advance(p)!;
			Node rhs = parse_expr(p, UNARY)!;

			uint[3] data = { (uint)t.kind, (uint)rhs, (uint)is_bang_bang };
			uint ex = p.ast.push_extra_block(&data);
			return p.ast.add_node(UNARY_EXPR, t.pos, p.current_pos(), ex);

		case LPAREN:
			Token start_token = t;
			advance(p)!; // consume '('

			Node inner = parse_expr(p, Precedence.LOWEST)!;
			
			expect(p, RPAREN)!;

			NodeKind kind = p.ast.get_kind(inner);
			
			// IMPORTANT!
			// Might be missing some kinds in 'can_start_expression'
			// which makes a Cast expr parsed as a grouped expr
			if (kind == TYPE_EXPR && can_start_expression(p.current().kind)) 
			{
				Node operand = parse_expr(p, Precedence.UNARY)!;
				uint[2] data = { (uint)inner, (uint)operand };
				uint ex = p.ast.push_extra_block(&data);
				return p.ast.add_node(CAST_EXPR, start_token.pos, p.current_pos(), ex);
			}

			// TODO: Add as grouped expr
			return inner;
		case CT_TYPEFROM:
		case CT_TYPEOF:
			{
				advance(p)!;

				expect(p, LPAREN)!;
				Node expr_inside = parse_expr(p)!;
				expect(p, RPAREN)!;

				return p.ast.add_node(TYPE_EXPR, t.pos, p.current_pos(), (uint)expr_inside);
			}
		case CT_VAARG:
		{
			advance(p)!;
			uint sh = p.pool.intern(p.token_text(t));
			return p.ast.add_node(IDENT_EXPR, t.pos, p.current_pos(), sh);
		}
		case CT_STRINGIFY:
		case CT_REFLECT:
		{
			advance(p)!;
			uint sh = p.pool.intern(p.token_text(t));
			return p.ast.add_node(IDENT_EXPR, t.pos, p.current_pos(), sh);
		}
		case CT_DEFINED:
		{
			return parse_ct_defined_expr(p)!;
		}
		case LBRACE:
			return parse_initializer_list(p)!;
		case ELLIPSIS:
		{
			advance(p)!;
			Node rhs = parse_expr(p, Precedence.UNARY)!;

			uint[2] data = { (uint)t.kind, (uint)rhs };
			uint ex = p.ast.push_extra_block(&data);
			return p.ast.add_node(SPLAT_EXPR, t.pos, p.current_pos(), ex);
		}
		case MINUSMINUS:
		case PLUSPLUS:
			{
				advance(p)!;
				Node right = parse_expr(p, Precedence.CALL)!;
				uint[2] data = { (uint)t.kind, (uint)right };

				uint ex = p.ast.push_extra_block(&data);
				return p.ast.add_node(PRE_UNARY_EXPR, t.pos, p.current_pos(), ex);
			}
		case CT_FEATURE:
		{
			advance(p)!;
			expect(p, LPAREN)!;
			Node expr = parse_expr(p)!;
			expect(p, RPAREN)!;
			return p.ast.add_node(CT_FEATURE_EXPR, t.pos, p.current_pos(), (uint)expr);
		}
		case LENGTHOF:
		{
			advance(p)!;
			expect(p, LPAREN)!;
			Node expr = parse_expr(p)!;
			expect(p, RPAREN)!;
			return p.ast.add_node(LENGTHOF_EXPR, t.pos, p.current_pos(), (uint)expr);
		}
		default:
			log::error(
				"parse_prefix_expr - Expected expression for token: ((%s) %s - %s)",
				p.token_text(p.current()),
				p.current().kind
			);
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
		case PLUS:
		case PLUS_ASSIGN:
		case MINUS:
		case MINUS_ASSIGN:
		case ASTERISK:
		case MULT_ASSIGN:
		case DIV:
		case DIV_ASSIGN:
		case MOD:
		case MOD_ASSIGN:
		case EQ:
		case GREATER:
		case GREATER_EQ:
		case LESS:
		case LESS_EQ:
		case AND:
		case OR:
		case BIT_OR:
		case BIT_XOR:
		case BIT_XOR_ASSIGN:
		case BIT_OR_ASSIGN:
		case AMP:
		case BIT_AND_ASSIGN:
		case EQEQ:
		case NOT_EQUAL:
		case RSHIFT:
		case LSHIFT:
		case RSHIFT_ASSIGN:
		case LSHIFT_ASSIGN:
		case QUESTQUEST:
		case ELVIS:
		case CT_CONCAT_OP:
		case CT_AND_OP: 
		case CT_OR_OP:
			{
				advance(p)!;
				Node right = parse_expr(p, rbp)!;

				uint[3] data = { (uint)left, (uint)right, (uint)t.kind };
				uint ex = p.ast.push_extra_block(&data);
				return p.ast.add_node(BINARY_EXPR, t.pos, p.current_pos(), ex);
			}
		case PLUSPLUS:
		case MINUSMINUS:
		case BANG:
		case BANGBANG:
			{
				advance(p)!;
				uint[2] data = { (uint)t.kind, (uint)left };

				uint ex = p.ast.push_extra_block(&data);
				return p.ast.add_node(POST_UNARY_EXPR, t.pos, p.current_pos(), ex);
			}
		case LPAREN:
			{
				advance(p)!;
				return parse_call(p, t, left)!;
			}
		case LBRACE:
		{
			NodeKind kind = p.ast.get_kind(left);

			if (kind == TYPE_EXPR) 
			{
				Node list = parse_initializer_list(p)!; 

				uint[*] data = {
					(uint)left,
					(uint)list,
				};
				uint ex = p.ast.push_extra_block(&data);
				return p.ast.add_node(COMPOUND_LITERAL_EXPR, t.pos, p.current_pos(), ex);
			}
			
			return parse_generic_expr(p)!;
		}
		case QUESTION:
		case CT_TERNARY:
			{
				return parse_ternary(p, left);
			}
		case DOT:
		case SCOPE:
			{
				advance(p)!;
				Token member_token = p.current();

				if (member_token.kind == LBRACKET)
				{
					advance(p)!;
					Node deref_node = p.ast.add_node(MAYBE_DEREF_EXPR, member_token.pos, p.current_pos(), (uint)left);
					return parse_range(p, deref_node, t.pos);
				}

				if ((!is_type(p)) 
					&& member_token.kind != IDENT
					&& member_token.kind != CONST_IDENT
					&& member_token.kind != CT_IDENT
					&& member_token.kind != TYPE_IDENT
					&& member_token.kind != AT_IDENT)
				{
					p.error("Expected identifier after '.' got: %s", p.token_text(member_token));
					return UNEXPECTED_TOKEN~;
				}
				advance(p)!;

				uint sh = p.pool.intern(p.token_text(member_token));
				Node member_node = p.ast.add_node(IDENT_EXPR, member_token.pos, p.current_pos(), sh);

				uint[2] data = { (uint)left, (uint)member_node };
				uint ex = p.ast.push_extra_block(&data);
				return p.ast.add_node(ACCESS_EXPR, t.pos, p.current_pos(), ex);
			}
		case BIT_NOT:
			{
				advance(p)!;
				if (p.ast.get_kind(left) == TYPE_EXPR)
				{
					p.error("Expected a fault before '~'");
					return UNEXPECTED_TOKEN~;
				}
				return p.ast.add_node(OPTIONAL_EXPR, t.pos, p.current_pos(), (uint)left);
			}
		case LBRACKET:
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

		// BREAK if:
        // 1. Token is not an infix operator (lbp is -1)
        // 2. Token precedence is lower than current min_bp
        if (lbp == Precedence.NONE || lbp < (int)min_bp) 
        {
            break;
        }

		left = parse_infix(p, left, (Precedence)rbp)!;
	}

	if (min_bp == 0 && p.is(AT_IDENT))
	{
		Node attr = parse_attributes(p)!;
		uint[2] data = { (uint)left, (uint)attr };
		uint ex = p.ast.push_extra_block(&data);
		left = p.ast.add_node(ATTRIBUTED_EXPR, p.current().pos, p.current_pos(), ex);
	}

	return left;
}

fn Node? parse_constant_expr(Parser* p)
{
	return parse_expr(p, ASSIGNMENT + 1);
}

<*
	"Shortcut" for when a left node has already been parsed (like an identifier) 
	and want to continue building an expression from that specific point without starting over
*>
fn Node? parse_expr_resuming_with_left(Parser* p, Node left, int min_bp)
{
	while (true)
	{
		int lbp, rbp;
		get_binding_power(p.current().kind, &lbp, &rbp);
		if ((int) lbp < min_bp) break;

		left = parse_infix(p, left, (Precedence)rbp)!;
	}
	return left;
}

fn Node? parse_ternary(Parser* p, Node condition)
{
	uint start_tok = p.current_pos();
	bool is_const = p.is(CT_TERNARY);
	advance(p)!;

	Node then_expr = parse_expr(p, Precedence.LOWEST)!;
	expect(p, COLON)!;

	Node else_expr = parse_expr(p, TERNARY)!;

	uint[4] data = { (uint)condition, (uint)then_expr, (uint)else_expr, (uint)is_const };
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(TERNARY_EXPR, start_tok, p.current_pos(), ex);
}

<*
 	TODO: needs more safety checks?
	TODO: needs better handling/control flow?
*>
fn Node? parse_call(Parser* p, Token t, Node callee)
{
	Node trailing_block;
	uint type_args_list_ex;
	Node macro_body_args;

	@with_scratch(; watermark)
	{
		if (t.kind == LBRACE)
		{
			while (true)
			{
				Node arg_node;

				if (p.is(EOS))
				{
					arg_node = p.ast.add_node(NONE_EXPR, p.current_pos(), p.current_pos(), 0);
					advance(p)!;
					scratch.push((uint)arg_node);
					arg_node = (Node)parse_parameter_list(p, { .is_call = true })!;
				}
				else
				{
					arg_node = parse_type(p)!;
				}

				scratch.push((uint)arg_node);

				if (!p.is(COMMA) && !p.is(EOS)) 
				{
					break;
				}

				advance(p)!;
			}

			expect(p, RBRACE)!;
			// skip LPAREN, like parse_infix_expr would do on a non-generic call
			advance(p)!;
		}

		type_args_list_ex = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};


	uint args_list_ex;
	@with_scratch(; watermark)
	{
		while (p.current().kind != RPAREN && p.current().kind != EOS && !p.eof())
		{
			Node arg_node;
			// Named argument logic (name: expr)
			TokenKind kind = p.current().kind;
			if ((kind == IDENT || kind == HASH_IDENT || kind == CT_IDENT) && p.peek().kind == COLON)
			{
				Token name_tok = p.current();
				advance(p, 2)!;
				uint name_sh = p.pool.intern(p.token_text(name_tok));
				Node value = parse_expr(p)!;
				uint[2] data = { name_sh, (uint)value };
				uint arg_ex = p.ast.push_extra_block(&data);
				arg_node = p.ast.add_node(NAMED_ARG_EXPR, name_tok.pos, p.current_pos(), arg_ex);
			}
			else
			{
				arg_node = parse_expr(p)!;
			}

			scratch.push((uint)arg_node);
			if (!consume(p, COMMA)!) break;
		}

		if (consume(p, EOS)!)
		{
			macro_body_args = (Node)parse_parameter_list(p, { .is_call = true })!;
		}

		expect(p, RPAREN)!;
		args_list_ex = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};

	Node attr = parse_attributes(p)!;

	if (p.is(LBRACE))
	{
		trailing_block = parse_compound(p)!;
	}

	uint[*] final_data = views::@data{CallViewFields}
	(	
		CALLEE, callee,
		TYPE_ARG, type_args_list_ex,
		ARG, args_list_ex,
		COMPOUND, trailing_block,
	);

	uint ex = p.ast.push_extra_block(&final_data);
	return p.ast.add_node(CALL_EXPR, t.pos, p.current_pos(), ex);
}

fn Node? parse_designator_path(Parser* p)
{
	Node path;

	while (true) 
	{
		if (p.is(DOT)) 
		{
			Token dot_tok = p.peek();
			advance(p)!;

			Node field = parse_expr(p, HIGHEST)!;

			if (!path.is_valid()) 
			{
				path = field;
			} 
			else 
			{
				uint[2] data = { (uint)path, (uint)field };
				uint ex = p.ast.push_extra_block(&data);
				path = p.ast.add_node(DESIGNATOR_PERIOD_EXPR, dot_tok.pos, p.current_pos(), ex);
			}
			continue;
		}

		if (p.is(LBRACKET)) 
		{
			Token open_tok = p.peek();
			advance(p)!;

			Node start = parse_expr(p)!;
			Node end = {};
			bool is_range = false;

			if (p.is(DOTDOT) || p.is(COLON))
			{
				is_range = true;
				advance(p)!;
				end = parse_expr(p)!;
			}

			expect(p, RBRACKET)!;

			NodeKind kind = is_range ? DESIGNATOR_RANGE_EXPR : DESIGNATOR_INDEX_EXPR;
			uint[3] data = { (uint)path, (uint)start, (uint)end };
			uint ex = p.ast.push_extra_block(&data);
			path = p.ast.add_node(kind, open_tok.pos, p.current_pos(), ex);
			continue;
		}
		break;
	}
	return path;
}

fn Node? parse_initializer_list(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, LBRACE)!;

	// Handle empty initializer {}
	if (consume(p, RBRACE)!)
	{
		return p.ast.add_node(INITIALIZER_LIST, start_tok, p.current_pos(), 0);
	}

	uint ex = 0;
	@with_scratch(; watermark)
	{
		while (true)
		{
			Node expr;

			if (p.is(DOT) || p.is(LBRACKET))            
			{
				uint path_start = p.current_pos();
				Node path = parse_designator_path(p)!;

				if (consume(p, EQ)!)
				{
					Node val = parse_expr(p, Precedence.LOWEST)!;

					uint[2] data = { (uint)path, (uint)val };
					uint pair_ex = p.ast.push_extra_block(&data);
					expr = p.ast.add_node(DESIGNATED_INITIALIZER, path_start, p.current_pos(), pair_ex);
				}
				else
				{
					// .member (implies .member = member)
					expr = path;
				}
			}
			// Nested Initializer: { {1, 2}, {3, 4} }
			else if (p.is(LBRACE))
			{
				expr = parse_initializer_list(p)!;
			}
			else
			{
				expr = parse_expr(p)!;
			}

			scratch.push((uint)expr);

			if (consume(p, RBRACE)!) break;
			expect(p, COMMA)!;

			// Handle trailing comma
			if (p.is(RBRACE)) 
			{ 
				advance(p)!; 
				break; 
			} 
		}

		ex = p.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};

	return p.ast.add_node(INITIALIZER_LIST, start_tok, p.current_pos(), ex);
}

/**
 * maybe_range ::= range | ('^'? INTEGER)
 * range ::= dot_range | colon_range
 * dot_range ::= ('^'? INTEGER)? .. ('^'? INTEGER)?
 * colon_range ::= ('^'? INTEGER)? : ('^'? INTEGER)?
 */
fn Node? parse_range(Parser* p, Node left, uint start_pos)
{
	Node start;
	Node end;
	bool is_slice = false;

	if (p.is(COLON) || p.is(DOTDOT))
	{
		is_slice = true;
		advance(p)!;
	}
	else
	{
		if (consume(p, BIT_XOR)!)
		{
			Node inner = parse_expr(p, LOWEST)!;
			uint[2] data = { (uint)TokenKind.BIT_XOR, (uint)inner };
			uint ex = p.ast.push_extra_block(&data);
			start = p.ast.add_node(PREFIX_EXPR, p.current().pos, p.current_pos(), ex);
		}
		else
		{
			start = parse_expr(p, LOWEST)!;
		}

		if (p.is(COLON) || p.is(DOTDOT))
		{
			is_slice = true;
			advance(p)!;
		}
	}

	if (is_slice && !p.is(RBRACKET))
	{
		if (consume(p, BIT_XOR)!)
		{
			Node inner = parse_expr(p, LOWEST)!;
			uint[2] data = { (uint)TokenKind.BIT_XOR, (uint)inner };
			uint ex = p.ast.push_extra_block(&data);
			end = p.ast.add_node(PREFIX_EXPR, p.current().pos, p.current_pos(), ex);
		}
		else
		{
			end = parse_expr(p, LOWEST)!;
		}
	}

	expect(p, RBRACKET)!;

	if (is_slice)
	{
		uint[2] slice_data = { (uint)start, (uint)end };
		uint slice_ex = p.ast.push_extra_block(&slice_data);
		Node slice_node = p.ast.add_node(SLICE_EXPR, start_pos, p.current_pos(), slice_ex);

		uint[2] access_data = { (uint)left, (uint)slice_node };
		uint access_ex = p.ast.push_extra_block(&access_data);
		return p.ast.add_node(INDEX_EXPR, start_pos, p.current_pos(), access_ex);
	}

	uint[2] data = { (uint)left, (uint)start };
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(INDEX_EXPR, start_pos, p.current_pos(), ex);
}

fn Node? parse_ct_expr_list(Parser* p) => @with_scratch(; watermark)
{
	uint start_pos = p.current().pos;

	while (true)
	{
		Node item;

		if (p.is(VAR))
		{
			ParseFlags flags = { 
				.is_local = true,
				.is_var = true,
				.is_comptime = true 
			};
			item = parse_var_decl(p, flags)!;
		}
		else if (is_type(p))
		{
			ParseFlags flags = { 
				.is_local = true,
				.is_var = true,
				.is_comptime = true 
			};
			item = parse_var_decl(p, flags)!;
		}
		else
		{
			item = parse_expr(p)!;
		}

		scratch.push((uint)item);

		if (!consume(p, COMMA)!) break;

		TokenKind next = p.current().kind;
		if (next == EOS || next == COLON || next == RPAREN || next == RBRACKET)
		{
			break;
		}
	}

	uint count = (uint)scratch.len() - watermark;
	uint ex = p.ast.push_extra_list(scratch_view(watermark, count));
	return p.ast.add_node(EXPR_LIST, start_pos, p.previous_pos(), ex);
}

fn Node? parse_contract_expr(Parser* p, bool is_ensure)
{
    uint start_pos = p.current().pos;
    Node expr = parse_expr(p)!;
    Node comment;

    if (consume(p, COLON)!)
    {
        comment = parse_expr(p)!; 
    }

    uint[3] entry_data = { (uint)expr, (uint)comment, is_ensure ? 1 : 0 };
    uint entry_ex = p.ast.push_extra_block(&entry_data);
    
    return p.ast.add_node(CONTRACT_ENTRY, start_pos, p.current_pos(), entry_ex);
}

fn Node? parse_expr_list(Parser* p) => @with_scratch(; watermark)
{
    uint start_pos = p.current().pos;

	while (!p.eof())	
	{
		scratch.push((uint)parse_decl_or_expr(p)!);
		if (p.is(EOS) || !consume(p, COMMA)!) break;
	}

    uint count = (uint)scratch.len() - watermark;
	uint ex = p.ast.push_extra_list(scratch_view(watermark, count));
    return p.ast.add_node(EXPR_LIST, start_pos, p.previous_pos(), ex);
}

fn Node? parse_ct_defined_expr(Parser* p) => @with_scratch(; watermark)
{
    uint start_pos = p.current().pos;
	expect(p, CT_DEFINED)!;

	if (consume(p, LPAREN)!)
	{
		while (!p.is(RPAREN) && !p.eof())
		{
			scratch.push((uint)parse_decl_or_expr(p)!);

			if (!consume(p, COMMA)!)
			{
				if (!consume(p, RPAREN)!)
				{
					p.error("Expected closing ')'");
					p.push_invalid_node(p.current_pos());
					break;
				}
				break;
			}
		}
	}
	else
	{
		p.error("expected '('");
		p.push_invalid_node(p.current_pos());
	}

	uint count = (uint)scratch.len() - watermark;
    uint exprs_list_ex = p.ast.push_extra_list(scratch_view(watermark, count));

    uint[1] entry_data = { exprs_list_ex };
    uint entry_ex = p.ast.push_extra_block(&entry_data);

    return p.ast.add_node(CT_DEFINED_EXPR, start_pos, p.current_pos(), entry_ex);	
}

fn Node? parse_decl_or_expr(Parser* p)
{
	if (p.is(VAR))
	{
		return parse_var_decl(p, { .is_expr = true, .is_local = true, .skip_eos = true, .is_var = true })!;
	}

	// Need to check that its not a type expr
	if (is_type(p) && is_declaration_followup(p))
	{
		return parse_var_decl(p, { .is_expr = true, .is_local = true, .skip_eos = true })!;
	}

	return parse_expr(p)!;
}

fn Node? parse_lambda(Parser* p)
{
	uint start_tok = p.current_pos();
	expect(p, FN)!;

	Node return_type;
	if (!p.is(LPAREN))
	{
		return_type = parse_type(p)!;
	}

	Node params = parse_parameter_list(p)!;
	Node attr = parse_attributes(p)!;

	Node body;
	if (p.is(IMPLIES))
	{
		advance(p)!;
		log::debug("parse_fn_decl - parse_short_body");
		body = parse_expr(p)!;
	}
	else if (p.is(LBRACE))
	{
		body = parse_compound(p)!;
	}
	else
	{
		p.error("Expected the beginning of a block or a short statement.");
		body = p.push_invalid_node(p.current_pos());
	}

	uint[*] data = views::@data{LambdaViewFields}
	(
		RETURN_TYPE, return_type,
		ATTRIBUTES, attr,
		BODY, body,
	);

	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(LAMBDA_EXPR, start_tok, p.current_pos(), ex);
}

fn Node? parse_generic_expr(Parser* p) => @with_scratch(; watermark)
{
	uint start_pos = p.current_pos();
	expect(p, LBRACE)!;

	do
	{
		scratch.push((uint)parse_expr(p)!);
		if (!consume(p, COMMA)!)
		{
			expect(p, RBRACE)!;
			break;
		}
	}
	while (!consume(p, RBRACE)!);

	uint count = (uint)scratch.len() - watermark;
	uint ex = p.ast.push_extra_list(scratch_view(watermark, count));
	return p.ast.add_node(GENERIC_IDENT_EXPR, start_pos, p.current_pos(), ex);
}

fn Node? parse_bytes_expr(Parser* p)
{
    uint start_pos = p.current_pos();
    
    @with_scratch(; watermark)
    {
        while (p.is(BYTES))
        {
            Token tok = p.current();
            String lexeme = p.token_text(tok);
            
            // Determine if it's hex or b64 based on the prefix
            bool is_hex = lexeme[0] == 'x';
			// remove x' '
            String inner = lexeme[2:^3];

            if (is_hex)
			{
				for (Size i = 0; i < inner.len; i++)
				{
					if (lexer::is_whitespace(inner[i])) continue;
					char high = char.from_hex(inner[i]);

					i++;
					while (i < inner.len && lexer::is_whitespace(inner[i]))
					{ 
						i++;
					}
					
					char low = char.from_hex(inner[i]);

					scratch.push((char)((high << 4) | low));
				}
			}
            else
            {
                int buffer = 0;
				int bits_collected = 0;

				for (Size i = 0; i < inner.len; i++)
				{
					char c = inner[i];
					
					if (lexer::is_whitespace(c)) continue;
					if (c == '=') break;

					int sextet = base64_to_sextet(c);
					if (sextet < 0) continue;

					buffer = (buffer << 6) | sextet;
					bits_collected += 6;

					if (bits_collected >= 8)
					{
						bits_collected -= 8;
						char byte = (char)((buffer >> bits_collected) & 0xFF);
						scratch.push(byte);
					}
				}
            }
            
            advance(p)!;
        }

        uint total_len = (uint)scratch.len() - watermark;
        if (total_len == 0)
        {
            log::error("Byte array must contain at least one byte.");
            return UNEXPECTED_TOKEN~;
        }

        uint ex = p.ast.push_extra_list(scratch_view(watermark, (uint)total_len));
        return p.ast.add_node(BYTES_LITERAL, start_pos, p.current_pos(), ex);
    };
}