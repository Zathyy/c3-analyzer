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
		case CT_CONCAT_ASSIGN:
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
fn Node? parse_prefix_expr(ParseContext* ctx)
{
	Token t = ctx.current();

	if (is_type(ctx))
	{
		return parse_type(ctx, { .type_as_expression = true })!;
	}

	switch (t.kind)
	{
		case BUILTIN:
		{
			advance(ctx)!;
			Token next = ctx.current();

			// parse ident
			Node ident_node = parse_expr(ctx, Precedence.MULTIPLICATIVE)!;

			uint[2] data = { (uint)t.kind, (uint)ident_node };
			uint ex = ctx.ast.push_extra_block(&data);

			if (next.kind == CONST_IDENT)
			{
				return ctx.ast.add_node(COMPILER_CONST_EXPR, t.pos, ctx.current_pos(), ex);
			}

			return ctx.ast.add_node(BUILTIN_EXPR, t.pos, ctx.current_pos(), ex);
		}
		case NULL:
		{
			advance(ctx)!;
			return ctx.ast.add_node(NULL_LITERAL, t.pos, t.pos, 0);
		}
		case FN: // lambda
		{
			return parse_lambda(ctx)!;
		}
		case BYTES:
		{
			return parse_bytes_expr(ctx)!;
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
			if (ctx.peek().kind == SCOPE)
			{
				return parse_path_prefix(ctx)!;
			}

			advance(ctx)!;
			Token current = ctx.current();
			uint sh = ctx.pool.intern(ctx.token_text(t));
			return ctx.ast.add_node(IDENT_EXPR, t.pos, ctx.current_pos(), sh);

		// getting the actual literal value is up to the semantic analysis
		case STRING:
			String text = ctx.token_text(t);
			advance(ctx)!;
			while (ctx.is(STRING))
			{
				text = string::tformat("%s%s", text[..^2], ctx.token_text(ctx.current())[1..]);
				advance(ctx)!;
			}
			uint sh = ctx.pool.intern(text);
			return ctx.ast.add_node(STRING_LITERAL, t.pos, ctx.current_pos(), sh);
		
		case CHAR_LITERAL:
			String text = ctx.token_text(t);
			uint sh = ctx.pool.intern(text);
			advance(ctx)!;
			return ctx.ast.add_node(CHAR_LITERAL, t.pos, ctx.current_pos(), sh);

		case TRUE:
			advance(ctx)!;
			return ctx.ast.add_node(BOOL_LITERAL, t.pos, ctx.current_pos(), 1);

		case FALSE:
			advance(ctx)!;
			return ctx.ast.add_node(BOOL_LITERAL, t.pos, ctx.current_pos(), 0);

		case REAL:
			String text = ctx.token_text(t);
			uint sh = ctx.pool.intern(text);
			advance(ctx)!;
			return ctx.ast.add_node(FLOAT_LITERAL, t.pos, ctx.current_pos(), sh);

		case INTEGER:
			String text = ctx.token_text(t);
			uint sh = ctx.pool.intern(text);
			advance(ctx)!;
			return ctx.ast.add_node(INT_LITERAL, t.pos, ctx.current_pos(), sh);
		case BANG:
		case BANGBANG:
		case MINUS:
		case BIT_NOT:
		case AMP:
		case AND: // for the unary temp value pointer
		case ASTERISK:
			bool is_bang_bang = ctx.is(BANGBANG);
			advance(ctx)!;
			Node rhs = parse_expr(ctx, UNARY)!;

			uint[3] data = { (uint)t.kind, (uint)rhs, (uint)is_bang_bang };
			uint ex = ctx.ast.push_extra_block(&data);
			return ctx.ast.add_node(UNARY_EXPR, t.pos, ctx.current_pos(), ex);

		case LPAREN:
			Token start_token = t;
			advance(ctx)!; // consume '('

			Node inner = parse_expr(ctx, Precedence.LOWEST)!;
			
			expect(ctx, RPAREN)!;

			NodeKind kind = ctx.ast.get_kind(inner);
			
			// IMPORTANT!
			// Might be missing some kinds in 'can_start_expression'
			// which makes a Cast expr parsed as a grouped expr
			if (kind == TYPE_EXPR && can_start_expression(ctx.current().kind)) 
			{
				Node operand = parse_expr(ctx, Precedence.UNARY)!;
				uint[2] data = { (uint)inner, (uint)operand };
				uint ex = ctx.ast.push_extra_block(&data);
				return ctx.ast.add_node(CAST_EXPR, start_token.pos, ctx.current_pos(), ex);
			}

			// TODO: Add as grouped expr
			return inner;
		case CT_TYPEFROM:
		case CT_TYPEOF:
			{
				advance(ctx)!;

				expect(ctx, LPAREN)!;
				Node expr_inside = parse_expr(ctx)!;
				expect(ctx, RPAREN)!;

				return ctx.ast.add_node(TYPE_EXPR, t.pos, ctx.current_pos(), (uint)expr_inside);
			}
		case CT_VAARG:
		{
			advance(ctx)!;
			uint sh = ctx.pool.intern(ctx.token_text(t));
			return ctx.ast.add_node(IDENT_EXPR, t.pos, ctx.current_pos(), sh);
		}
		case CT_STRINGIFY:
		case CT_REFLECT:
		{
			advance(ctx)!;
			uint sh = ctx.pool.intern(ctx.token_text(t));
			return ctx.ast.add_node(IDENT_EXPR, t.pos, ctx.current_pos(), sh);
		}
		case CT_DEFINED:
		{
			return parse_ct_defined_expr(ctx)!;
		}
		case LBRACE:
			return parse_initializer_list(ctx)!;
		case ELLIPSIS:
		{
			advance(ctx)!;
			Node rhs = parse_expr(ctx, Precedence.UNARY)!;

			uint[2] data = { (uint)t.kind, (uint)rhs };
			uint ex = ctx.ast.push_extra_block(&data);
			return ctx.ast.add_node(SPLAT_EXPR, t.pos, ctx.current_pos(), ex);
		}
		case MINUSMINUS:
		case PLUSPLUS:
			{
				advance(ctx)!;
				Node right = parse_expr(ctx, Precedence.CALL)!;
				uint[2] data = { (uint)t.kind, (uint)right };

				uint ex = ctx.ast.push_extra_block(&data);
				return ctx.ast.add_node(PRE_UNARY_EXPR, t.pos, ctx.current_pos(), ex);
			}
		case CT_FEATURE:
		{
			advance(ctx)!;
			expect(ctx, LPAREN)!;
			Node expr = parse_expr(ctx)!;
			expect(ctx, RPAREN)!;
			return ctx.ast.add_node(CT_FEATURE_EXPR, t.pos, ctx.current_pos(), (uint)expr);
		}
		case LENGTHOF:
		{
			advance(ctx)!;
			expect(ctx, LPAREN)!;
			Node expr = parse_expr(ctx)!;
			expect(ctx, RPAREN)!;
			return ctx.ast.add_node(LENGTHOF_EXPR, t.pos, ctx.current_pos(), (uint)expr);
		}
		default:
			log::error(
				"parse_prefix_expr - Expected expression for token: ((%s) %s - %s)",
				ctx.token_text(ctx.current()),
				ctx.current().kind
			);
			ctx.error("Expected expression");
			return EXPECTED_EXPRESSION~;
	}
}

<*
	parse_infix (Led)
	Handles tokens that connect expressions (e.g. 1 + 2, obj.prop, arr[0])
	It takes a pre-parsed "left" node and attaches a "right" side to it.
*>
fn Node? parse_infix(ParseContext* ctx, Node left, Precedence rbp)
{
	Token t = ctx.current();

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
		case CT_CONCAT_ASSIGN:
		case CT_AND_OP: 
		case CT_OR_OP:
			{
				advance(ctx)!;
				Node right = parse_expr(ctx, rbp)!;

				uint[3] data = { (uint)left, (uint)right, (uint)t.kind };
				uint ex = ctx.ast.push_extra_block(&data);
				return ctx.ast.add_node(BINARY_EXPR, t.pos, ctx.current_pos(), ex);
			}
		case PLUSPLUS:
		case MINUSMINUS:
		case BANG:
		case BANGBANG:
			{
				advance(ctx)!;
				uint[2] data = { (uint)t.kind, (uint)left };

				uint ex = ctx.ast.push_extra_block(&data);
				return ctx.ast.add_node(POST_UNARY_EXPR, t.pos, ctx.current_pos(), ex);
			}
		case LPAREN:
			{
				advance(ctx)!;
				return parse_call(ctx, t, left)!;
			}
		case LBRACE:
		{
			NodeKind kind = ctx.ast.get_kind(left);

			if (kind == TYPE_EXPR) 
			{
				Node list = parse_initializer_list(ctx)!; 

				uint[*] data = {
					(uint)left,
					(uint)list,
				};
				uint ex = ctx.ast.push_extra_block(&data);
				return ctx.ast.add_node(COMPOUND_LITERAL_EXPR, t.pos, ctx.current_pos(), ex);
			}
			
			return parse_generic_expr(ctx)!;
		}
		case QUESTION:
		case CT_TERNARY:
			{
				return parse_ternary(ctx, left);
			}
		case DOT:
		case SCOPE:
			{
				return parse_access_expr(ctx, left);
			}
		case BIT_NOT:
			{
				advance(ctx)!;
				if (ctx.ast.get_kind(left) == TYPE_EXPR)
				{
					ctx.error("Expected a fault before '~'");
					return UNEXPECTED_TOKEN~;
				}
				return ctx.ast.add_node(OPTIONAL_EXPR, t.pos, ctx.current_pos(), (uint)left);
			}
		case LBRACKET:
			{
				advance(ctx)!;
				return parse_range(ctx, left, t.pos)!;
			}
		default:
			ctx.error("Unexpected infix token: %s", t.kind);
			return UNEXPECTED_TOKEN~;
	}
}

<*
	parse expressions recursively with Pratt parsing
	using Binding power.
	@param [&inout] ctx
	@param min_bp : "Starting binding power, always call with 0, it will call itself recursively with other values"
*>
fn Node? parse_expr(ParseContext* ctx, Precedence min_bp = LOWEST)
{
	Node left = parse_prefix_expr(ctx)!;

	while (true)
	{
		int lbp, rbp;
		get_binding_power(ctx.current().kind, &lbp, &rbp);

		// debug purposes
		log::debug("Current Token: %s, LBP: %d, MinBP: %d", ctx.current().kind, lbp, min_bp);

		// BREAK if:
        // 1. Token is not an infix operator (lbp is -1)
        // 2. Token precedence is lower than current min_bp
        if (lbp == Precedence.NONE || lbp < (int)min_bp) 
        {
            break;
        }

		left = parse_infix(ctx, left, (Precedence)rbp)!;
	}

	if (min_bp == 0 && ctx.is(AT_IDENT))
	{
		Node attr = parse_attributes(ctx)!;
		uint[2] data = { (uint)left, (uint)attr };
		uint ex = ctx.ast.push_extra_block(&data);
		left = ctx.ast.add_node(ATTRIBUTED_EXPR, ctx.current().pos, ctx.current_pos(), ex);
	}

	return left;
}

fn Node? parse_constant_expr(ParseContext* ctx)
{
	return parse_expr(ctx, ASSIGNMENT + 1);
}

<*
	"Shortcut" for when a left node has already been parsed (like an identifier) 
	and want to continue building an expression from that specific point without starting over
*>
fn Node? parse_expr_resuming_with_left(ParseContext* ctx, Node left, int min_bp)
{
	while (true)
	{
		int lbp, rbp;
		get_binding_power(ctx.current().kind, &lbp, &rbp);
		if ((int) lbp < min_bp) break;

		left = parse_infix(ctx, left, (Precedence)rbp)!;
	}
	return left;
}

fn Node? parse_ternary(ParseContext* ctx, Node condition)
{
	uint start_tok = ctx.current_pos();
	bool is_const = ctx.is(CT_TERNARY);
	advance(ctx)!;

	Node then_expr = parse_expr(ctx, Precedence.LOWEST)!;
	expect(ctx, COLON)!;

	Node else_expr = parse_expr(ctx, TERNARY)!;

	uint[4] data = { (uint)condition, (uint)then_expr, (uint)else_expr, (uint)is_const };
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(TERNARY_EXPR, start_tok, ctx.current_pos(), ex);
}

<*
 	TODO: needs more safety checks?
	TODO: needs better handling/control flow?
*>
fn Node? parse_call(ParseContext* ctx, Token t, Node callee)
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

				if (ctx.is(EOS))
				{
					arg_node = ctx.ast.add_node(NONE_EXPR, ctx.current_pos(), ctx.current_pos(), 0);
					advance(ctx)!;
					scratch.push((uint)arg_node);
					arg_node = (Node)parse_parameter_list(ctx, { .is_call = true })!;
				}
				else
				{
					arg_node = parse_type(ctx)!;
				}

				scratch.push((uint)arg_node);

				if (!ctx.is(COMMA) && !ctx.is(EOS)) 
				{
					break;
				}

				advance(ctx)!;
			}

			expect(ctx, RBRACE)!;
			// skip LPAREN, like parse_infix_expr would do on a non-generic call
			advance(ctx)!;
		}

		type_args_list_ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};


	uint args_list_ex;
	@with_scratch(; watermark)
	{
		while (ctx.current().kind != RPAREN && ctx.current().kind != EOS && !ctx.eof())
		{
			Node arg_node;
			// Named argument logic (name: expr)
			TokenKind kind = ctx.current().kind;
			if ((kind == IDENT || kind == HASH_IDENT || kind == CT_IDENT) && ctx.peek().kind == COLON)
			{
				Token name_tok = ctx.current();
				advance(ctx, 2)!;
				uint name_sh = ctx.pool.intern(ctx.token_text(name_tok));
				Node value = parse_expr(ctx)!;
				uint[2] data = { name_sh, (uint)value };
				uint arg_ex = ctx.ast.push_extra_block(&data);
				arg_node = ctx.ast.add_node(NAMED_ARG_EXPR, name_tok.pos, ctx.current_pos(), arg_ex);
			}
			else
			{
				arg_node = parse_expr(ctx)!;
			}

			scratch.push((uint)arg_node);
			if (!consume(ctx, COMMA)!) break;
		}

		if (consume(ctx, EOS)!)
		{
			macro_body_args = (Node)parse_parameter_list(ctx, { .is_call = true })!;
		}

		expect(ctx, RPAREN)!;
		args_list_ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};

	Node attr = parse_attributes(ctx)!;

	if (ctx.is(LBRACE))
	{
		trailing_block = parse_compound(ctx)!;
	}

	uint[*] final_data = views::@data{CallViewFields}
	(	
		CALLEE, callee,
		TYPE_ARG, type_args_list_ex,
		ARG, args_list_ex,
		COMPOUND, trailing_block,
	);

	uint ex = ctx.ast.push_extra_block(&final_data);
	return ctx.ast.add_node(CALL_EXPR, t.pos, ctx.current_pos(), ex);
}

fn Node? parse_designator_path(ParseContext* ctx)
{
	Node path;

	while (true) 
	{
		if (ctx.is(DOT)) 
		{
			Token dot_tok = ctx.peek();
			advance(ctx)!;

			Node field = parse_expr(ctx, HIGHEST)!;

			if (!path.is_valid()) 
			{
				path = field;
			} 
			else 
			{
				uint[2] data = { (uint)path, (uint)field };
				uint ex = ctx.ast.push_extra_block(&data);
				path = ctx.ast.add_node(DESIGNATOR_PERIOD_EXPR, dot_tok.pos, ctx.current_pos(), ex);
			}
			continue;
		}

		if (ctx.is(LBRACKET)) 
		{
			Token open_tok = ctx.peek();
			advance(ctx)!;

			Node start = parse_expr(ctx)!;
			Node end = {};
			bool is_range = false;

			if (ctx.is(DOTDOT) || ctx.is(COLON))
			{
				is_range = true;
				advance(ctx)!;
				end = parse_expr(ctx)!;
			}

			expect(ctx, RBRACKET)!;

			NodeKind kind = is_range ? DESIGNATOR_RANGE_EXPR : DESIGNATOR_INDEX_EXPR;
			uint[3] data = { (uint)path, (uint)start, (uint)end };
			uint ex = ctx.ast.push_extra_block(&data);
			path = ctx.ast.add_node(kind, open_tok.pos, ctx.current_pos(), ex);
			continue;
		}
		break;
	}
	return path;
}

fn Node? parse_initializer_list(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, LBRACE)!;

	// Handle empty initializer {}
	if (consume(ctx, RBRACE)!)
	{
		return ctx.ast.add_node(INITIALIZER_LIST, start_tok, ctx.current_pos(), 0);
	}

	uint ex = 0;
	@with_scratch(; watermark)
	{
		while (true)
		{
			Node expr;

			if (ctx.is(DOT) || ctx.is(LBRACKET))            
			{
				uint path_start = ctx.current_pos();
				Node path = parse_designator_path(ctx)!;

				if (consume(ctx, EQ)!)
				{
					Node val = parse_expr(ctx, Precedence.LOWEST)!;

					uint[2] data = { (uint)path, (uint)val };
					uint pair_ex = ctx.ast.push_extra_block(&data);
					expr = ctx.ast.add_node(DESIGNATED_INITIALIZER, path_start, ctx.current_pos(), pair_ex);
				}
				else
				{
					// .member (implies .member = member)
					expr = path;
				}
			}
			// Nested Initializer: { {1, 2}, {3, 4} }
			else if (ctx.is(LBRACE))
			{
				expr = parse_initializer_list(ctx)!;
			}
			else
			{
				expr = parse_expr(ctx)!;
			}

			scratch.push((uint)expr);

			if (consume(ctx, RBRACE)!) break;
			expect(ctx, COMMA)!;

			// Handle trailing comma
			if (ctx.is(RBRACE)) 
			{ 
				advance(ctx)!; 
				break; 
			} 
		}

		ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)scratch.len() - watermark));
	};

	return ctx.ast.add_node(INITIALIZER_LIST, start_tok, ctx.current_pos(), ex);
}

/**
 * maybe_range ::= range | ('^'? INTEGER)
 * range ::= dot_range | colon_range
 * dot_range ::= ('^'? INTEGER)? .. ('^'? INTEGER)?
 * colon_range ::= ('^'? INTEGER)? : ('^'? INTEGER)?
 */
fn Node? parse_range(ParseContext* ctx, Node left, uint start_pos)
{
	Node start;
	Node end;
	bool is_slice = false;

	if (ctx.is(COLON) || ctx.is(DOTDOT))
	{
		is_slice = true;
		advance(ctx)!;
	}
	else
	{
		if (consume(ctx, BIT_XOR)!)
		{
			Node inner = parse_expr(ctx, LOWEST)!;
			uint[2] data = { (uint)TokenKind.BIT_XOR, (uint)inner };
			uint ex = ctx.ast.push_extra_block(&data);
			start = ctx.ast.add_node(PREFIX_EXPR, ctx.current().pos, ctx.current_pos(), ex);
		}
		else
		{
			start = parse_expr(ctx, LOWEST)!;
		}

		if (ctx.is(COLON) || ctx.is(DOTDOT))
		{
			is_slice = true;
			advance(ctx)!;
		}
	}

	if (is_slice && !ctx.is(RBRACKET))
	{
		if (consume(ctx, BIT_XOR)!)
		{
			Node inner = parse_expr(ctx, LOWEST)!;
			uint[2] data = { (uint)TokenKind.BIT_XOR, (uint)inner };
			uint ex = ctx.ast.push_extra_block(&data);
			end = ctx.ast.add_node(PREFIX_EXPR, ctx.current().pos, ctx.current_pos(), ex);
		}
		else
		{
			end = parse_expr(ctx, LOWEST)!;
		}
	}

	expect(ctx, RBRACKET)!;

	if (is_slice)
	{
		uint[2] slice_data = { (uint)start, (uint)end };
		uint slice_ex = ctx.ast.push_extra_block(&slice_data);
		Node slice_node = ctx.ast.add_node(SLICE_EXPR, start_pos, ctx.current_pos(), slice_ex);

		uint[2] access_data = { (uint)left, (uint)slice_node };
		uint access_ex = ctx.ast.push_extra_block(&access_data);
		return ctx.ast.add_node(INDEX_EXPR, start_pos, ctx.current_pos(), access_ex);
	}

	uint[2] data = { (uint)left, (uint)start };
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(INDEX_EXPR, start_pos, ctx.current_pos(), ex);
}

fn Node? parse_ct_expr_list(ParseContext* ctx) => @with_scratch(; watermark)
{
	uint start_pos = ctx.current().pos;

	while (true)
	{
		Node item;

		if (ctx.is(VAR))
		{
			ParseFlags flags = { 
				.is_local = true,
				.is_var = true,
				.is_comptime = true 
			};
			item = parse_var_decl(ctx, flags)!;
		}
		else if (is_type(ctx))
		{
			ParseFlags flags = { 
				.is_local = true,
				.is_var = true,
				.is_comptime = true 
			};
			item = parse_var_decl(ctx, flags)!;
		}
		else
		{
			item = parse_expr(ctx)!;
		}

		scratch.push((uint)item);

		if (!consume(ctx, COMMA)!) break;

		TokenKind next = ctx.current().kind;
		if (next == EOS || next == COLON || next == RPAREN || next == RBRACKET)
		{
			break;
		}
	}

	uint count = (uint)scratch.len() - watermark;
	uint ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
	return ctx.ast.add_node(EXPR_LIST, start_pos, ctx.previous_pos(), ex);
}

fn Node? parse_contract_expr(ParseContext* ctx, bool is_ensure)
{
    uint start_pos = ctx.current().pos;
    Node expr = parse_expr(ctx)!;
    Node comment;

    if (consume(ctx, COLON)!)
    {
        comment = parse_expr(ctx)!; 
    }

    uint[3] entry_data = { (uint)expr, (uint)comment, is_ensure ? 1 : 0 };
    uint entry_ex = ctx.ast.push_extra_block(&entry_data);
    
    return ctx.ast.add_node(CONTRACT_ENTRY, start_pos, ctx.current_pos(), entry_ex);
}

fn Node? parse_expr_list(ParseContext* ctx) => @with_scratch(; watermark)
{
    uint start_pos = ctx.current().pos;

	while (!ctx.eof())	
	{
		scratch.push((uint)parse_decl_or_expr(ctx)!);
		if (ctx.is(EOS) || !consume(ctx, COMMA)!) break;
	}

    uint count = (uint)scratch.len() - watermark;
	uint ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
    return ctx.ast.add_node(EXPR_LIST, start_pos, ctx.previous_pos(), ex);
}

fn Node? parse_ct_defined_expr(ParseContext* ctx) => @with_scratch(; watermark)
{
    uint start_pos = ctx.current().pos;
	expect(ctx, CT_DEFINED)!;

	if (consume(ctx, LPAREN)!)
	{
		while (!ctx.is(RPAREN) && !ctx.eof())
		{
			scratch.push((uint)parse_decl_or_expr(ctx)!);

			if (!consume(ctx, COMMA)!)
			{
				if (!consume(ctx, RPAREN)!)
				{
					ctx.error("Expected closing ')'");
					ctx.push_invalid_node(ctx.current_pos());
					break;
				}
				break;
			}
		}
	}
	else
	{
		ctx.error("expected '('");
		ctx.push_invalid_node(ctx.current_pos());
	}

	uint count = (uint)scratch.len() - watermark;
    uint exprs_list_ex = ctx.ast.push_extra_list(scratch_view(watermark, count));

    uint[1] entry_data = { exprs_list_ex };
    uint entry_ex = ctx.ast.push_extra_block(&entry_data);

    return ctx.ast.add_node(CT_DEFINED_EXPR, start_pos, ctx.current_pos(), entry_ex);	
}

fn Node? parse_decl_or_expr(ParseContext* ctx)
{
	if (ctx.is(VAR))
	{
		return parse_var_decl(ctx, { .is_expr = true, .is_local = true, .skip_eos = true, .is_var = true })!;
	}

	// Need to check that its not a type expr
	if (is_type(ctx) && is_declaration_followup(ctx))
	{
		return parse_var_decl(ctx, { .is_expr = true, .is_local = true, .skip_eos = true })!;
	}

	return parse_expr(ctx)!;
}

fn Node? parse_lambda(ParseContext* ctx)
{
	uint start_tok = ctx.current_pos();
	expect(ctx, FN)!;

	Node return_type;
	if (!ctx.is(LPAREN))
	{
		return_type = parse_type(ctx)!;
	}

	Node params = parse_parameter_list(ctx)!;
	Node attr = parse_attributes(ctx)!;

	Node body;
	if (ctx.is(IMPLIES))
	{
		advance(ctx)!;
		log::debug("parse_fn_decl - parse_short_body");
		body = parse_expr(ctx)!;
	}
	else if (ctx.is(LBRACE))
	{
		body = parse_compound(ctx)!;
	}
	else
	{
		ctx.error("Expected the beginning of a block or a short statement.");
		body = ctx.push_invalid_node(ctx.current_pos());
	}

	uint[*] data = views::@data{LambdaViewFields}
	(
		RETURN_TYPE, return_type,
		ATTRIBUTES, attr,
		BODY, body,
	);

	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(LAMBDA_EXPR, start_tok, ctx.current_pos(), ex);
}

fn Node? parse_generic_expr(ParseContext* ctx) => @with_scratch(; watermark)
{
	uint start_pos = ctx.current_pos();
	expect(ctx, LBRACE)!;

	do
	{
		scratch.push((uint)parse_expr(ctx)!);
		if (!consume(ctx, COMMA)!)
		{
			expect(ctx, RBRACE)!;
			break;
		}
	}
	while (!consume(ctx, RBRACE)!);

	uint count = (uint)scratch.len() - watermark;
	uint ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
	return ctx.ast.add_node(GENERIC_IDENT_EXPR, start_pos, ctx.current_pos(), ex);
}

fn Node? parse_access_expr(ParseContext* ctx, Node left)
{
	uint start_tok = ctx.current_pos();
	advance(ctx)!;
	Token member_token = ctx.current();

	if (member_token.kind == LBRACKET)
	{
		advance(ctx)!;
		Node deref_node = ctx.ast.add_node(MAYBE_DEREF_EXPR, member_token.pos, ctx.current_pos(), (uint)left);
		return parse_range(ctx, deref_node, start_tok);
	}

	Node member_node;

	if (member_token.kind == CT_EVAL)
	{
		advance(ctx)!;
		if (ctx.current().kind != LPAREN)
		{
			ctx.error("Expected '(' after '$eval' got: %s", ctx.token_text(ctx.current()));
			return UNEXPECTED_TOKEN~;
		}
		advance(ctx)!;

		member_node = parse_expr(ctx)!;
		if (ctx.current().kind != RPAREN)
		{
			ctx.error("Expected ')' after '$eval(...' got: %s", ctx.token_text(ctx.current()));
			return UNEXPECTED_TOKEN~;
		}
		advance(ctx)!;
	} 
	else
	{
		if ((!is_type(ctx)) 
				 && member_token.kind != IDENT
				 && member_token.kind != CONST_IDENT
				 && member_token.kind != CT_IDENT
				 && member_token.kind != TYPE_IDENT
				 && member_token.kind != AT_IDENT)
		{
			ctx.error("Expected identifier or '$eval(...)' after '.' got: %s", ctx.token_text(member_token));
			return UNEXPECTED_TOKEN~;
		}
		advance(ctx)!;

		uint sh = ctx.pool.intern(ctx.token_text(member_token));
		member_node = ctx.ast.add_node(IDENT_EXPR, member_token.pos, ctx.current_pos(), sh);
	}

	uint[2] data = { (uint)left, (uint)member_node };
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(ACCESS_EXPR, start_tok, ctx.current_pos(), ex);
}

fn Node? parse_bytes_expr(ParseContext* ctx)
{
    uint start_pos = ctx.current_pos();
    
    @with_scratch(; watermark)
    {
        while (ctx.is(BYTES))
        {
            Token tok = ctx.current();
            String lexeme = ctx.token_text(tok);
            
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
            
            advance(ctx)!;
        }

        uint total_len = (uint)scratch.len() - watermark;
        if (total_len == 0)
        {
            log::error("Byte array must contain at least one byte.");
            return UNEXPECTED_TOKEN~;
        }

        uint ex = ctx.ast.push_extra_list(scratch_view(watermark, (uint)total_len));
        return ctx.ast.add_node(BYTES_LITERAL, start_pos, ctx.current_pos(), ex);
    };
}
