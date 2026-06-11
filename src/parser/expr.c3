<*
 Pratt parsing using Binding power
	
	Resources for Binding power pratt parsing:
	- https://matklad.github.io/2020/04/13/simple-but-powerful-pratt-parsing.html
*>
module parser::parser;

import parser::ast;
import lexer;
import std::core::ascii;

import std::io;
import std::collections::list;
import std::encoding;
import parser::plog;

<*
 Parse an alias-only C3 function pointer type.

 Function pointer syntax is formed from a function declaration with the name
 omitted, and C3 exposes it through alias declarations.
 @param [&inout] ctx : "Parser context positioned at 'fn'."
*>
fn Node*? parse_fn_type_expr(ParseContext* ctx) => @pool()
{
	int start = ctx.current().pos;
	expect(ctx, FN)!;
	Node* node        = ctx.ast.alloc_node(TYPE_EXPR, start);
	TypeExpr* fn_type = node.as(TYPE_EXPR);
	defer node.end_token = ctx.current().pos;

	fn_type.kind = TYPE_FUNCTION;
	fn_type.func.ret_type = parse_type_expr(ctx)!;
	if (is_error_or_missing_node(fn_type.func.ret_type))
	{
		node.kind = MISSING;
	}

	fn_type.func.params = parse_parameter_list(ctx)!;
	foreach (param : fn_type.func.params)
	{
		if (is_error_or_missing_node(param))
		{
			node.kind = MISSING;
		}
	}

	return node;
}

<*
 Parse a type target for a TYPE_IDENT alias.

 C3 function pointer types are alias-only, so this helper accepts `fn` syntax
 for aliases without making `fn` a general type-expression start.
 @param [&inout] ctx : "Parser context positioned at the alias target."
*>
fn Node*? parse_alias_type_target(ParseContext* ctx) => @pool()
{
	if (ctx.is(FN))
	{
		return parse_fn_type_expr(ctx)!;
	}

	return parse_type_expr(ctx)!;
}

<*
 Parse a C3 type expression.

 Handles primitive and named type identifiers plus postfix pointer, array,
 slice, vector, and generic type forms.
 @param [&inout] ctx : "Parser context positioned at the first type token."
 @param parse_flags : "Type-expression options used by declaration and expression parsing."
*>
fn Node*? parse_type_expr(ParseContext* ctx, Node* path_expr = null, ParseFlags parse_flags = { })
{
	int start = ctx.current().pos;

	plog::debug("parse_type_expr");

	Node* current_type = ctx.ast.alloc_node(TYPE_EXPR, start, ctx.current().pos);
	TypeExpr* data     = current_type.as(TYPE_EXPR);

	// Check for built-in primitive keywords (int, void, double, etc.)
	if IS_PRIM: (is_type_primitive(ctx.current().kind))
	{
		Token t = ctx.current();
		advance(ctx)!;

		data.kind = TYPE_IDENTIFIER;
		data.unresolved.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		data.unresolved.path = null;
	}
	else
	{
		Node* path = path_expr;
		if (!path)
		{
			path = parse_path_expr(ctx, { .as_prefix = true })!;
		}
		Token t = @expect_else_skip(ctx, TYPE_IDENT, { EOS, ASTERISK, LBRACE, QUESTION, LVEC } ; err)
		{
			break IS_PRIM;
		}!;
		data.kind = TYPE_IDENTIFIER;
		data.unresolved.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
		data.unresolved.path = path;
	}

	current_type.end_token = ctx.current().pos;

	while (true)
	{
		Token t = ctx.current();

		if (t.kind == QUESTION)
		{
			advance(ctx)!;
			plog::debug("set type to optional");
			current_type.as(TYPE_EXPR).optional = true;
			continue;
		}

		if (t.kind == ASTERISK)
		{
			advance(ctx)!;

			Node* ptr_node     = ctx.ast.alloc_node(TYPE_EXPR, start, t.pos);
			TypeExpr* ptr_data = ptr_node.as(TYPE_EXPR);

			ptr_data.kind = TYPE_POINTER;
			ptr_data.modify.base = current_type; // The previous node becomes the base

			// Swap current_type out so the next iteration wraps THIS layer
			current_type = ptr_node;
			continue;
		}

		if (t.kind == LVEC)
		{
			advance(ctx)!;

			Node* vec_node     = ctx.ast.alloc_node(TYPE_EXPR, start, ctx.current().pos);
			TypeExpr* vec_data = vec_node.as(TYPE_EXPR);

			vec_data.kind = TYPE_VECTOR;
			vec_data.array.base = current_type;

			if (!consume(ctx, ASTERISK)!)
			{
				vec_data.array.len_expr = parse_expr(ctx, ADDITIVE)!;
			}

			expect(ctx, RVEC)!;

			vec_node.end_token = ctx.current().pos;
			current_type = vec_node;
			continue;
		}

		if (t.kind == LBRACKET)
		{
			advance(ctx)!;

			Node* arr_node     = ctx.ast.alloc_node(TYPE_EXPR, start, ctx.current().pos);
			TypeExpr* arr_data = arr_node.as(TYPE_EXPR);

			if (ctx.is(RBRACKET))
			{
				advance(ctx)!;
				arr_data.kind = TYPE_SLICE;
				arr_data.modify.base = current_type;
			}
			else if (ctx.is(ASTERISK) && ctx.peek(1)!.kind == RBRACKET)
			{
				advance(ctx)!; // Consume '*'
				advance(ctx)!; // Consume ']'

				arr_data.kind = TYPE_ARRAY;
				arr_data.array.base = current_type;
				arr_data.array.len_expr = null; // null represents inferred array size [*]
			}
			else
			{
				arr_data.kind = TYPE_ARRAY;
				arr_data.array.base = current_type;
				arr_data.array.len_expr = parse_expr(ctx)!;
				expect(ctx, RBRACKET)!;
			}

			arr_node.end_token = ctx.current().pos;
			current_type = arr_node;
			continue;
		}

		// Handle Generics: '{' ... '}'
		if (t.kind == LBRACE)
		{
			if (parse_flags.no_generics) break;
			if (parse_flags.type_as_expression) break;

			Node* gen_node     = ctx.ast.alloc_node(TYPE_EXPR, start, ctx.current().pos);
			TypeExpr* gen_data = gen_node.as(TYPE_EXPR);

			gen_data.kind = TYPE_GENERIC;
			gen_data.generic.base = current_type;
			gen_data.generic.params = parse_generics_list(ctx)!;

			gen_node.end_token = ctx.current().pos;
			current_type = gen_node;
			continue;
		}

		break;
	}

	return current_type;
}

fn Node*? parse_ident_expr(ParseContext* ctx)
{
	int start = ctx.current().pos;
	Node* path_prefix;

	if (ctx.peek(1)!.kind == SCOPE)
	{
		path_prefix = parse_path_expr(ctx, { .as_prefix = true })!;
	}
	Token t = ctx.current();
	switch (t.kind)
	{
		case TYPE_IDENT:
			return parse_type_expr(ctx, path_prefix)!;
		case IDENT:
		case CONST_IDENT:
		case AT_IDENT:
		case CT_IDENT:
		case HASH_IDENT:

			{
				Node* node       = ctx.ast.alloc_node(IDENT_EXPR, start, ctx.current().pos);
				IdentExpr* ident = node.as(IDENT_EXPR);
				ident.ident = ctx.ast.string_pool.internalize(ctx.token_text(t));
				ident.path_expr = path_prefix;

				advance(ctx)!;
				return node;
			}
		default:
			advance(ctx)!;
			return unexpected_at(ctx, t, "Expected type or identifier after path - got: %s", t.kind.description);
	}
}

fn Node*? parse_literal_expr(ParseContext* ctx) => @pool()
{
	Token token = ctx.current();
	int start   = token.pos;

	Node* node = ctx.ast.alloc_node(LITERAL_EXPR, start);
	defer node.end_token = ctx.current().pos;
	LiteralExpr* literal = node.as(LITERAL_EXPR);
	String token_text    = ctx.token_text(token);

	plog::debug("literal_expr: %s", token.kind);

	switch (token.kind)
	{
		case NULL:
			literal.kind = NULL_LITERAL;
			advance(ctx)!;
			break;
		case TRUE:
			literal.kind = BOOL_LITERAL;
			literal.boolean = true;
			advance(ctx)!;
			break;
		case FALSE:
			literal.kind = BOOL_LITERAL;
			literal.boolean = false;
			advance(ctx)!;
			break;
		case INT_DECIMAL_LITERAL:
		case INT_HEX_LITERAL:
		case INT_OCTAL_LITERAL:
		case INT_BIN_LITERAL:
			literal.kind = INT_LITERAL;
			String clean_string = token_text.treplace("_", "");
			int base = 10;
			usz start_idx = 0;
			if (token.kind == INT_HEX_LITERAL)
			{
				base = 16;
				start_idx = 2;
			}
			else if (token.kind == INT_BIN_LITERAL)
			{
				base = 2;
				start_idx = 2;
			}
			else if (token.kind == INT_OCTAL_LITERAL)
			{
				base = 8;
				start_idx = 2;
			}
			else
			{
				base = 10;
				start_idx = 0;
			}

			String body = clean_string[start_idx..];
			usz end_idx = body.len;
			while (end_idx > 0)
			{
				char last_char = body[end_idx - 1];
				if (ascii::is_alpha(last_char))
				{
					if (base == 16 && ascii::is_xdigit(last_char)) break;
					if (base == 10 && ascii::is_digit(last_char)) break;
					if (base == 8 && ascii::is_odigit(last_char)) break;
					if (base == 2 && ascii::is_bdigit(last_char)) break;

					end_idx--;
				}
				else
				{
					break;
				}
			}
			String pure_digits = body[0:end_idx];
			long? value = pure_digits.to_long(base);
			if (catch err = value)
			{
				ctx.error("Failed to parse int literal (%s): %s", pure_digits, err);
				advance(ctx)!;
				return ctx.ast.error(start);
			}
			literal.integer = value;
			advance(ctx)!;
			break;
		case FLOAT_DECIMAL_LITERAL:
		case FLOAT_HEX_LITERAL:

			{
				literal.kind = REAL_LITERAL;
				String clean_string = token_text.treplace("_", "");
				sz len              = clean_string.len;
				if (len > 0)
				{
					if (clean_string.ends_with("f32") || clean_string.ends_with("f64"))
					{
						clean_string = clean_string[0:len - 3];
					}
					if (clean_string.ends_with("f") || clean_string.ends_with("d"))
					{
						if (token.kind == FLOAT_HEX_LITERAL)
						{
							if (clean_string.contains("p") || clean_string.contains("P"))
							{
								clean_string = clean_string[0:len - 1];
							}
						}
						else
						{
							clean_string = clean_string[0:len - 1];
						}
					}
				}
				double? real = clean_string.to_double();
				if (catch err = real)
				{
					ctx.error("Failed to decode float literal (%s): %s", token_text, err);
					advance(ctx)!;
					return ctx.ast.error(start);
				}
				literal.real = real;
				advance(ctx)!;
				break;
			}
		case STRING_LITERAL:
			literal.kind = STRING_LITERAL;
			String text = token_text[1:^2]; // remove trailing "
			literal.string = ctx.ast.string_pool.internalize(text);
			advance(ctx)!;
			break;
		case BYTES_LITERAL:
			literal.kind = BYTES_LITERAL;
			if (token_text.starts_with("b64"))
			{
				String clean = token_text[4:^5];
				char[]? b64  = base64::decode(tmem, clean);
				if (catch err = b64)
				{
					ctx.error("Failed to decode Base64(%s): %s", clean, err);
					advance(ctx)!;
					return ctx.ast.error(start);
				}
				literal.bytes = alloc::clone_slice(ctx.arena, b64);
				advance(ctx)!;
			}
			else if (token_text.starts_with("x"))
			{
				String clean = token_text.treplace(" ", "");
				String final = clean[2:^3];
				plog::debug("%s", final);
				if (final.len % 2 != 0)
				{
					ctx.error(
						"Hex literal payload must have an even number of digits (got %s chars in '%s')",
						final.len,
						final
					);
					advance(ctx)!;
					return ctx.ast.error(start);
				}
				char[]? hex = hex::decode(tmem, final);
				if (catch err = hex)
				{
					ctx.error("Failed to decode hex(%s): %s", final, err);
					advance(ctx)!;
					return ctx.ast.error(start);
				}
				literal.bytes = alloc::clone_slice(ctx.arena, hex);
				advance(ctx)!;
			}
			break;
		case CHAR_LITERAL:
			literal.kind = INT_LITERAL;

			// Slice off the enclosing single quotes: 'c' -> c
			String clean_char = token_text[1:^2];

			if (clean_char.len == 0)
			{
				ctx.error("Empty character literal encountered");
				advance(ctx)!;
				return ctx.ast.error(start);
			}

			// Handle escapes vs plain characters
			if (clean_char[0] == '\\')
			{
				if (clean_char.len < 2)
				{
					ctx.error("Malformed escape sequence in character literal");
					advance(ctx)!;
					return ctx.ast.error(start);
				}

				switch (clean_char[1])
				{
					case 'n': literal.integer = (long)'\n'; break;
					case 'r': literal.integer = (long)'\r'; break;
					case 't': literal.integer = (long)'\t'; break;
					case '\\': literal.integer = (long)'\\'; break;
					case '\'': literal.integer = (long)'\''; break;
					case '"': literal.integer = (long)'"'; break;
					case '0': literal.integer = (long)'\0'; break;
					default:
						ctx.error("Unsupported escape sequence '\\%c'", clean_char[1]);
						advance(ctx)!;
						return ctx.ast.error(start);
				}
			}
			else
			{
				// Just grab the direct byte values
				literal.integer = (long)clean_char[0];
			}
			advance(ctx)!;
			break;
		default:
			unreachable("Not implemented! (%s)", token.kind.description);
	}

	return node;
}

<*
 Parse a full path e.g. foo::bar::baz;
 @param [&inout] ctx : "Parser context to consume tokens from."
*>
fn Node*? parse_path_expr(ParseContext* ctx, PathExprOptions options = { }) => @pool()
{
	int start_pos = ctx.current().pos;
	plog::debug("parse_path_expr");

	if (is_type(ctx))
	{
		if (options.as_prefix)
		{
			return null;
		}
	}

	if (!ctx.is(IDENT))
	{
		if (ctx.peek(1)!.kind != SCOPE)
		{
			if (options.as_prefix)
			{
				return null;
			}
		}

		ctx.error("Expected a path identifier here");
		return ctx.ast.error(start_pos);
	}

	Node* node     = ctx.ast.alloc_node(PATH_EXPR, start_pos, ctx.current().pos);
	PathExpr* path = node.as(PATH_EXPR);
	defer node.end_token = ctx.current().pos;

	List{StringID} temp_segments;
	temp_segments.init(tmem, 8);

	while (true)
	{
		if (options.as_prefix && ctx.peek(1)!.kind != SCOPE)
		{
			break;
		}

		Token t = ctx.current();
		temp_segments.push(ctx.ast.string_pool.internalize(ctx.token_text(t)));
		advance(ctx)!;

		if (!consume(ctx, SCOPE)!) break;
		if (!is_some_ident(ctx.current().kind))
		{
			if (!options.as_prefix)
			{
				temp_segments.push(ast::EMPTY_STR);
				advance(ctx)!;
			}
			break;
		}
	}

	path.segments = alloc::clone_slice(ctx.arena, temp_segments.array_view());
	return node;
}

fn Node*? parse_binary_expr(ParseContext* ctx, Node* left, Precedence prec)
{
	int start      = ctx.current().pos;
	TokenKind kind = ctx.current().kind;
	advance(ctx)!;
	Node* right = parse_expr(ctx, prec)!;

	Node* node      = ctx.ast.alloc_node(BINARY_EXPR, start, ctx.current().pos);
	BinaryExpr* bin = node.as(BINARY_EXPR);
	bin.left = left;
	bin.right = right;
	bin.op = parser::binaryop_from_token(kind);
	return node;
}

<*
 unary_expr ::= unary_op expr
*>
fn Node*? parse_unary_expr(ParseContext* ctx)
{
	int start_pos = ctx.current().pos;
	if (ctx.is(MINUS))
	{
		if (ctx.peek(1)!.kind.is_int_literal())
		{
			advance(ctx)!;
			return parse_expr(ctx)!;
		}
	}
	bool is_bang_bang = ctx.is(BANGBANG);
	Node* node        = ctx.ast.alloc_node(UNARY_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	UnaryExpr* unary = node.as(UNARY_EXPR);
	UnaryOpKind? op  = parser::unaryop_from_token(ctx.current().kind);
	if (catch op)
	{
		ctx.error("Not a unary operator (%s)", ctx.current().kind);
		return ctx.ast.error(ctx.current().pos);
	}
	advance(ctx)!;
	unary.expr = parse_expr(ctx, UNARY)!;
	if (is_bang_bang)
	{
		Node* outer          = ctx.ast.alloc_node(UNARY_EXPR, ctx.current().pos);
		UnaryExpr* out_unary = outer.as(UNARY_EXPR);
		out_unary.expr = node;
		out_unary.operator = UNARYOP_NOT;
		return outer;
	}
	return node;
}

fn Node*? parse_post_unary_expr(ParseContext* ctx, Node* left, Precedence bp)
{
	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(POST_UNARY_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	PostUnaryExpr* unary = node.as(POST_UNARY_EXPR);
	UnaryOpKind? op      = parser::unaryop_from_token(ctx.current().kind);
	if (catch op)
	{
		ctx.error("Not a unary operator (%s)", ctx.current().kind);
		return ctx.ast.error(ctx.current().pos);
	}
	unary.operator = op;
	unary.expr = left;
	advance(ctx)!;
	return node;
}

<*
 expr_list ::= decl_or_expr*

*>
fn Node*? parse_expr_list(ParseContext* ctx) => @pool()
{
	int start_pos  = ctx.current().pos;
	Node* node     = ctx.ast.alloc_node(EXPR_LIST, start_pos);
	ExprList* list = node.as(EXPR_LIST);
	defer node.end_token = ctx.current().pos;
	List{Node*} exprs;
	exprs.tinit();
	while (!ctx.eof())
	{
		exprs.push(parse_decl_or_expr(ctx)!);
		if (ctx.eof() || !consume(ctx, COMMA)!) break;
	}

	list.exprs = alloc::clone_slice(ctx.arena, exprs.array_view());
	return node;
}

<*
 contract_expr ::= expr_list (':'? STRING)?
*>
fn Node*? parse_contract_expr(ParseContext* ctx)
{
	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(CONTRACT_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	ContractExpr* expr = node.as(CONTRACT_EXPR);

	expr.exprs = parse_expr_list(ctx)!;

	if (!ctx.eof() && consume(ctx, COLON)!)
	{
		if (!ctx.is(STRING_LITERAL))
		{
			ctx.error("Expected a string after ':'");
			ctx.ast.error(ctx.current().pos);
			node.kind = ERROR;
			ctx.skip_until({ EOS, EOF })!;
			return node;
		}

		expr.expr_string = parse_expr(ctx)!;
	}

	return node;
}

fn Node*? parse_call_expr(ParseContext* ctx, Node* callee)
{
	int start_pos = ctx.current().pos;
	expect(ctx, LPAREN)!;
	Node* node = ctx.ast.alloc_node(CALL_EXPR, callee.start_token);
	defer node.end_token = ctx.current().pos;
	CallExpr* call = node.as(CALL_EXPR);
	call.callee = callee;

	plog::debug("call_expr");

	if (!ctx.is(RPAREN) && !ctx.eof())
	{
		plog::debug("call_expr - args");
		call.args = parse_arg_list(ctx)!;
	}

	NodeArray body_args;
	if (consume(ctx, EOS)!)
	{
		body_args = parse_parameter_list(ctx, { .is_call = true })!;
	}

	expect(ctx, RPAREN)!;

	if (ctx.is(AT_IDENT))
	{
		Token t = ctx.current();
		call.attributes = parse_attributes(ctx, node)!;

		foreach (attr : call.attributes)
		{
			AttributeDecl* attr_decl = attr.as(ATTRIBUTE_DECL);
			switch (attr_decl.kind)
			{
				case AttributeKind.INLINE:
				case AttributeKind.PURE:
				case AttributeKind.NOINLINE:
					// Set flags?
					break;
				default:
					unexpected_at(ctx, t, "Only '@pure', '@inline' and '@noinline' are valid attributes for calls")!;
			}
		}
	}
	Node* body;
	if (ctx.is(LBRACE))
	{
		body = parse_compound_stmt(ctx)!;
	}

	if (body || body_args)
	{
		Node* body_node          = ctx.ast.alloc_node(MACRO_BODY_EXPR, start_pos);
		MacroBodyExpr* body_expr = body_node.as(MACRO_BODY_EXPR);
		body_expr.args = body_args;
		body_expr.body = body;
		body_node.end_token = ctx.current().pos;
		call.macro_body_expr = body_node;
	}

	return node;
}

<*
 catch_unwrap ::= 'catch' (IDENT | type_expr? IDENT '=' catch_chain) | catch_chain
	catch_chain ::= parse_try_chain_expr (',' parse_try_chain_expr)*

*>
fn Node*? parse_catch_expr(ParseContext* ctx) => @pool()
{
	@expect_else(ctx, CATCH ; err)
	{
		return err;
	}!;

	Node* node = ctx.ast.alloc_node(CATCH_EXPR, ctx.current().pos);
	defer node.end_token = ctx.current().pos;
	CatchExpr* catch_expr = node.as(CATCH_EXPR);

	Node* sub_expr = parse_try_chain_expr(ctx)!;
	if (sub_expr.kind == ERROR)
	{
		ctx.skip_until({ EOS, RPAREN, EOF })!;
		return sub_expr;
	}
	List{Node*} exprs;
	exprs.tinit();
	if (consume(ctx, COMMA)!)
	{
		exprs.push(sub_expr);
		do
		{
			sub_expr = parse_try_chain_expr(ctx)!;
			if (sub_expr.kind == ERROR)
			{
				ctx.skip_until({ EOS, RPAREN, EOF })!;
				return sub_expr;
			}
			exprs.push(sub_expr);
		} while (consume(ctx, COMMA)!);
		catch_expr.exprs = alloc::clone_slice(ctx.arena, exprs.array_view());
		return node;
	}

	if (sub_expr.kind == TYPE_EXPR)
	{
		catch_expr.type = sub_expr;
		Node* variable = parse_try_chain_expr(ctx)!;
		if (variable.kind == ERROR)
		{
			ctx.skip_until({ EOS, RPAREN, EOF })!;
			return variable;
		}
		catch_expr.variable = variable;
	}
	else
	{
		catch_expr.type = null;
		catch_expr.variable = sub_expr;
	}

	if (!consume(ctx, EQ)!)
	{
		if (catch_expr.type)
		{
			ctx.error("Expected '=' here");
			return ctx.ast.error(ctx.current().pos);
		}

		exprs.push(catch_expr.variable);
		catch_expr.variable = null;
		return node;
	}

	do
	{
		sub_expr = parse_try_chain_expr(ctx)!;
		if (sub_expr.kind == ERROR)
		{
			return sub_expr;
		}
		exprs.push(sub_expr);
	} while (consume(ctx, COMMA)!);

	catch_expr.exprs = alloc::clone_slice(ctx.arena, exprs.array_view());

	return node;
}

<*
 cond_list ::= ((expr | decl-expr) COMMA)* (expr | decl-expr | try_unwrap_chain | catch_unwrap )
*>
fn Node*? parse_cond_expr(ParseContext* ctx) => @pool()
{
	Node* node = ctx.ast.alloc_node(COND_EXPR, ctx.current().pos);
	defer node.end_token = ctx.current().pos;
	CondExpr* cond = node.as(COND_EXPR);

	List{Node*} exprs;
	exprs.tinit();

	while (!ctx.eof())
	{
		if (ctx.is(TRY))
		{
			exprs.push(parse_try_unwrap_chain_expr(ctx)!);
			if (ctx.is(COMMA))
			{
				ctx.error("'try' must be placed last");
				return ctx.ast.error(ctx.current().pos);
			}
			break;
		}
		if (ctx.is(CATCH))
		{
			exprs.push(parse_catch_expr(ctx)!);
			if (ctx.is(COMMA))
			{
				ctx.error("'catch' must be placed last");
				return ctx.ast.error(ctx.current().pos);
			}
			break;
		}

		exprs.push(parse_decl_or_expr(ctx)!);
		if (!consume(ctx, COMMA)!) break;
	}

	cond.exprs = alloc::clone_slice(ctx.arena, exprs.array_view());
	return node;
}

fn Node*? parse_try_expr(ParseContext* ctx)
{
	@expect_else(ctx, TRY ; err)
	{
		return err;
	}!;

	Node* node = ctx.ast.alloc_node(TRY_EXPR, ctx.current().pos);
	defer node.end_token = ctx.current().pos;
	TryExpr* try_expr = node.as(TRY_EXPR);

	Node* lhs = parse_try_chain_expr(ctx)!;

	if (lhs.kind == TYPE_EXPR)
	{
		try_expr.type = lhs;
		try_expr.variable = parse_try_chain_expr(ctx)!;
	}
	else
	{
		try_expr.variable = lhs;
	}

	if (lhs.kind == TYPE_EXPR && try_expr.variable.kind != IDENT_EXPR)
	{
		ctx.error("A new variable was expected");
		return ctx.ast.error(lhs.start_token);
	}
	if (consume(ctx, EQ)!)
	{
		try_expr.init = parse_try_chain_expr(ctx)!;
	}
	return node;
}

<*
 try_unwrap_chain ::= try ('&&' (try_unwrap | try_chain_expr))*

*>
fn Node*? parse_try_unwrap_chain_expr(ParseContext* ctx)
{
	Node* first_try      = parse_try_expr(ctx)!;
	Node* current        = first_try;
	TryExpr* current_try = current.as(TRY_EXPR);

	while (consume(ctx, AND)!)
	{
		Node* next_expr = null;

		if (ctx.is(TRY))
		{
			next_expr = parse_try_expr(ctx)!;
		}
		else
		{
			next_expr = parse_try_chain_expr(ctx)!;
		}

		if (current.kind == NodeKind.TRY_EXPR)
		{
			current.as(TRY_EXPR).next = next_expr;
		}
		else
		{
			current_try.next = next_expr;
		}

		current = next_expr;
	}

	return first_try;
}

<*
 ternary_optional_expr ::= expr? | ternary_expr
 optional_expr ::= <left> '?' '!'?
 ternary_expr ::= <left> '?' expr ':' ternary_prec_expr
*>
fn Node*? parse_ternary_expr(ParseContext* ctx, Node* left)
{
	Node* node = ctx.ast.alloc_node(TERNARY_EXPR, ctx.current().pos);
	defer node.end_token = ctx.current().pos;
	TernaryExpr* tern = node.as(TERNARY_EXPR);

	tern.is_const = ctx.is(CT_TERNARY);
	advance(ctx)!;
	tern.cond = left;

	tern.then_expr = parse_expr(ctx)!;

	@expect_else(ctx, COLON ; err)
	{
		return err;
	}!;

	tern.else_expr = parse_expr(ctx, TERNARY)!;

	return node;
}

<*
 builtin_expr ::= '$$' IDENT
 compiler_const_expr ::= '$$' CONST_IDENT
*>
fn Node*? parse_builtin_expr(ParseContext* ctx)
{
	expect(ctx, BUILTIN)!;

	StringID name;
	BuiltinFunction builtin;

	plog::debug("builtin");

	do COND:
	{
		Token t = @expect_some_else(ctx, { IDENT, CONST_IDENT, TYPE_IDENT } ; err)
		{
			name = ast::EMPTY_STR;
			break COND;
		}!;

		name = ctx.ast.string_pool.internalize(ctx.token_text(t));

		if (t.kind == CONST_IDENT)
		{
			Node* node             = ctx.ast.alloc_node(COMPILER_CONST_EXPR, ctx.current().pos);
			CompilerConstExpr* cce = node.as(COMPILER_CONST_EXPR);

			cce.name = name;

			return node;
		}
	};

	Node* node         = ctx.ast.alloc_node(BUILTIN_EXPR, ctx.current().pos);
	BuiltinExpr* built = node.as(BUILTIN_EXPR);

	built.name = name;

	return node;
}

<*
 splat_expr ::= '...' expr
*>
fn Node*? parse_splat_expr(ParseContext* ctx)
{
	Node* node = ctx.ast.alloc_node(SPLAT_EXPR, ctx.current().pos);
	defer node.end_token = ctx.current().pos;
	SplatExpr* spl = node.as(SPLAT_EXPR);

	expect(ctx, ELLIPSIS)!;

	spl.inner = parse_expr(ctx)!;

	return node;
}

fn Node*? parse_vasplat_expr(ParseContext* ctx)
{
	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(VASPLAT_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	VasplatExpr* eval_named = node.as(VASPLAT_EXPR);

	expect(ctx, ELLIPSIS)!;
	expect(ctx, CT_VAARG)!;

	if (consume(ctx, LBRACKET)!)
	{
		ctx.warn("Not implemented!");
		plog::warn("This is not implemented!");
		advance(ctx)!;
	}

	return node;
}

fn Node*? parse_ct_eval_expr(ParseContext* ctx)
{
	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(CT_EVAL_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	CtEvalExpr* eval = node.as(CT_EVAL_EXPR);

	expect(ctx, CT_EVAL)!;
	expect(ctx, LPAREN)!;
	eval.inner_expr = parse_expr(ctx)!;
	expect(ctx, RPAREN)!;

	return node;
}

<*
 lambda_expr ::= "fn" return_type? fn_parameter_list attributes? lambda_body
 lambda_body ::= "{" statement* "}"
				| "=>" expression
*>
fn Node*? parse_lambda_expr(ParseContext* ctx)
{
	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(LAMBDA_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	LambdaExpr* lambda = node.as(LAMBDA_EXPR);

	node.visibility = LOCAL;

	expect(ctx, FN)!;
	if (!ctx.is(LPAREN))
	{
		lambda.return_type = parse_type_expr(ctx, null, { .no_generics = true })!;
	}
	lambda.params = parse_parameter_list(ctx)!;
	if (ctx.is(AT_IDENT))
	{
		lambda.attributes = parse_attributes(ctx, node)!;
	}

	if (consume(ctx, IMPLIES)!)
	{
		lambda.body = parse_expr(ctx)!;

		// Clean statement ending validation
		// if (!node_ends_with_block(ctx, lambda.body))
		// {
		// 	expect(ctx, EOS)!;
		// }
	}
	else if (ctx.is(LBRACE))
	{
		lambda.body = parse_compound_stmt(ctx)!;
	}
	else
	{
		unexpected(ctx, "Expected the beginning of a block or a shortbody")!;
	}

	return node;
}

fn Node*? parse_generic_expr(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(GENERIC_IDENT_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	GenericIdentExpr* generic = node.as(GENERIC_IDENT_EXPR);
	expect(ctx, LBRACE)!;
	List{Node*} exprs;
	exprs.tinit();
	do
	{
		exprs.push(parse_expr(ctx)!);
		if (!consume(ctx, COMMA)!)
		{
			expect(ctx, RBRACE)!;
			break;
		}
	} while (!consume(ctx, RBRACE)!);
	generic.exprs = alloc::clone_slice(ctx.arena, exprs.array_view());
	return node;
}

fn Node*? parse_group_expr(ParseContext* ctx)
{
	int start_pos = ctx.current().pos;

	expect(ctx, LPAREN)!;
	Node* inner = parse_expr(ctx)!;
	expect(ctx, RPAREN)!;

	// can_start_expression might miss some cases
	if (inner.kind == TYPE_EXPR && can_start_expression(ctx.current().kind))
	{
		Node* operand = parse_expr(ctx, UNARY)!;

		Node* node = ctx.ast.alloc_node(CAST_EXPR, start_pos);
		defer node.end_token = ctx.current().pos;
		CastExpr* cast = node.as(CAST_EXPR);
		cast.inner = inner;
		cast.operand = operand;
		return node;
	}

	Node* node = ctx.ast.alloc_node(GROUP_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	GroupExpr* group = node.as(GROUP_EXPR);

	group.inner = inner;

	return node;
}

<*
 designator_expr ::= ('[' expr ']' | '.' IDENT)*

*>
fn Node*? parse_designator_expr(ParseContext* ctx)
{
	Node* path;

	while (true)
	{
		if (ctx.is(DOT))
		{
			int start_pos = ctx.current().pos;
			advance(ctx)!; // consume '.'

			Node* field = parse_expr(ctx, HIGHEST)!;

			Node* node = ctx.ast.alloc_node(DESIGNATOR_EXPR, start_pos);
			node.end_token = ctx.current().pos;

			DesignatorExpr* des = node.as(DESIGNATOR_EXPR);
			des.kind = DesignatorKind.PERIOD;
			des.path = path; // will be null if this is the very first component
			des.field = field;

			path = node;
			continue;
		}

		if (ctx.is(LBRACKET))
		{
			int start_pos = ctx.current().pos;
			advance(ctx)!; // consume '['
			Node* designator_node = parse_range_expr(ctx, path, start_pos)!;
			path = designator_node;
			continue;
		}

		break;
	}

	return path;
}

<*
 initializer_list_expr ::= '{' ('...' expr | expr (',' expr)*)? '}'
*>
fn Node*? parse_initializer_list_expr(ParseContext* ctx) => @pool()
{
	expect(ctx, LBRACE)!;

	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(INITIALIZER_LIST_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	InitializerListExpr* init = node.as(INITIALIZER_LIST_EXPR);

	// Handle empty initializer {}
	if (consume(ctx, RBRACE)!)
	{
		return node;
	}

	List{Node*} exprs;
	exprs.tinit();

	while (!ctx.eof())
	{
		Node* expr;

		if (ctx.is(ELLIPSIS))
		{
			expr = parse_vasplat_expr(ctx)!;
		}
		if (ctx.is(DOT) || ctx.is(LBRACKET))
		{
			Token path_token = ctx.current();
			Node* des_expr   = parse_designator_expr(ctx)!;

			if (consume(ctx, EQ)!)
			{
				Node* val           = parse_expr(ctx)!;
				Node* des_init_node = ctx.ast.alloc_node(DESIGNATED_INITIALIZER_EXPR, path_token.pos);
				des_init_node.end_token = ctx.current().pos;

				DesignatedInitializerExpr* des_init = des_init_node.as(DESIGNATED_INITIALIZER_EXPR);
				des_init.path = des_expr;
				des_init.value = val;

				expr = des_init_node;
			}
			else
			{
				// Implicit assignment shortcut: .member
				expr = des_expr;
			}
		}
		else if (ctx.is(LBRACE))
		{
			// Nested initializers like { {1, 2}, {3, 4} }
			expr = parse_initializer_list_expr(ctx)!;
		}
		else
		{
			expr = parse_expr(ctx)!;
		}

		exprs.push(expr);

		if (consume(ctx, RBRACE)!) break;
		expect(ctx, COMMA)!;
		if (ctx.is(RBRACE))
		{
			advance(ctx)!;
			break;
		}
	}

	init.exprs = alloc::clone_slice(ctx.arena, exprs.array_view());

	return node;
}

fn Node*? parse_access_expr(ParseContext* ctx, Node* left)
{
	int start_pos          = ctx.current().pos;
	TokenKind op_kind      = ctx.current().kind;
	AccessKind access_kind = (op_kind == TokenKind.SCOPE) ? AccessKind.STATIC : AccessKind.INSTANCE;
	advance(ctx)!;
	Token member_token = ctx.current();

	if (member_token.kind == LBRACKET)
	{
		advance(ctx)!;
		Node* deref_node      = ctx.ast.alloc_node(MAYBE_DEREF_EXPR, member_token.pos, ctx.current().pos);
		MaybeDeferExpr* deref = deref_node.as(MAYBE_DEREF_EXPR);
		deref.left = left;
		// TODO: parse range
		return deref_node;
	}

	Node* node = ctx.ast.alloc_node(ACCESS_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	AccessExpr* access = node.as(ACCESS_EXPR);

	access.kind = access_kind;
	access.left = left;

	if EVAL: (member_token.kind == CT_EVAL)
	{
		advance(ctx)!;
		@expect_else_skip(ctx, LPAREN, { RPAREN, EOS } ; err)
		{
			break EVAL;
		}!;

		access.member = parse_expr(ctx)!;

		expect(ctx, RPAREN)!;
	}
	else
	{
		// HIGHEST bp to avoid consuming downstream infix operators.
		access.member = parse_expr(ctx, HIGHEST)!;
	}

	return node;
}

<*
 maybe_range ::= range | ('^'? INTEGER)
 range ::= dot_range | colon_range
 dot_range ::= ('^'? INTEGER)? .. ('^'? INTEGER)?
 colon_range ::= ('^'? INTEGER)? : ('^'? INTEGER)?
*>
fn Node*? parse_range_expr(ParseContext* ctx, Node* left, int start_pos)
{
	Node* start;
	Node* end;
	bool is_slice       = false;
	bool start_from_end = false;
	bool end_from_end   = false;
	TokenKind op_kind   = TokenKind.EOS;

	// Check if the start of the range is omitted (e.g., `[:5]` or `[..5]`)
	if (ctx.is(COLON) || ctx.is(DOTDOT))
	{
		is_slice = true;
		op_kind = ctx.current().kind;
		advance(ctx)!;
	}
	else
	{
		// Parse the optional leading index modifier caret '^' (BIT_XOR)
		if (consume(ctx, BIT_XOR)!)
		{
			start_from_end = true;
		}

		start = parse_expr(ctx, LOWEST)!;

		// Check if an operator separates this from a secondary range bound
		if (ctx.is(COLON) || ctx.is(DOTDOT))
		{
			is_slice = true;
			op_kind = ctx.current().kind;
			advance(ctx)!;
		}
	}

	// If it is a full range slice, parse the trailing bound component
	if (is_slice && !ctx.is(RBRACKET))
	{
		if (consume(ctx, BIT_XOR)!)
		{
			end_from_end = true;
		}

		end = parse_expr(ctx, LOWEST)!;
	}

	expect(ctx, RBRACKET)!;

	Node* designator_node = ctx.ast.alloc_node(DESIGNATOR_EXPR, start_pos);
	designator_node.end_token = ctx.current().pos;
	DesignatorExpr* des = designator_node.as(DESIGNATOR_EXPR);
	des.path = left;

	Node* range_node = ctx.ast.alloc_node(RANGE_EXPR, start_pos);
	range_node.end_token = ctx.current().pos;
	RangeExpr* range_payload = range_node.as(RANGE_EXPR);

	range_payload.start = start;
	range_payload.end = end;
	range_payload.start_from_end = start_from_end;
	range_payload.end_from_end = end_from_end;

	if (is_slice)
	{
		des.kind = DesignatorKind.RANGE;

		if (op_kind == COLON)
		{
			// Syntax: [start : len]
			range_payload.kind = RangeKind.CONST_LEN;
		}
		else
		{
			// Syntax: [start .. end]
			if (start && end)
			{
				range_payload.kind = RangeKind.CONST_RANGE;
			}
			else if (end)
			{
				range_payload.kind = RangeKind.CONST_END;
			}
			else
			{
				range_payload.kind = RangeKind.DYNAMIC;
			}
		}
	}
	else
	{
		// Syntax: [index] (Single lookup access format)
		des.kind = DesignatorKind.INDEX;
		range_payload.kind = RangeKind.SINGLE_ELEMENT;
	}

	des.range = range_node;
	return designator_node;
}

<*
 @param [&in] left
*>
fn Node*? parse_raise_suffix_expr(ParseContext* ctx, Node* left, Token left_token)
{
	if (left.kind == TYPE_EXPR)
	{
		advance(ctx)!;
		return unexpected_at(ctx, left_token, "Expected a fault before '~'")!;
	}
	expect(ctx, BIT_NOT)!;
	int start_pos     = ctx.current().pos;
	Node* node        = ctx.ast.alloc_node(OPTIONAL_EXPR, start_pos);
	OptionalExpr* opt = node.as(OPTIONAL_EXPR);
	opt.inner_expr = left;
	node.end_token = ctx.current().pos;
	return node;
}

fn Node*? parse_ct_defined_expr(ParseContext* ctx) => @pool()
{
	expect(ctx, CT_DEFINED)!;
	expect(ctx, LPAREN)!;

	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(CT_DEFINED_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	CtDefinedExpr* def = node.as(CT_DEFINED_EXPR);
	List{Node*} exprs;
	exprs.tinit();
	while (!ctx.eof() && !consume(ctx, RPAREN)!)
	{
		exprs.push(parse_decl_or_expr(ctx)!);
		if (!consume(ctx, COMMA)!)
		{
			expect(ctx, RPAREN)!;
			break;
		}
	}

	def.expr_list = alloc::clone_slice(ctx.arena, exprs.array_view());

	return node;
}

fn Node*? parse_ct_feature(ParseContext* ctx)
{
	expect(ctx, CT_FEATURE)!;

	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(CT_FEATURE_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	CtFeatureExpr* feat = node.as(CT_FEATURE_EXPR);

	expect(ctx, LPAREN)!;
	feat.inner_expr = parse_expr(ctx)!;
	expect(ctx, RPAREN)!;

	return node;
}

<*
 lengthof ::= LENGTHOF '(' expr ')'
*>
fn Node*? parse_lengthof_expr(ParseContext* ctx)
{
	expect(ctx, LENGTHOF)!;

	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(LENGTHOF_EXPR, start_pos);
	defer node.end_token = ctx.current().pos;
	LengthofExpr* len = node.as(LENGTHOF_EXPR);

	expect(ctx, LPAREN)!;
	len.inner_expr = parse_expr(ctx)!;
	expect(ctx, RPAREN)!;

	return node;
}

<*
 ct_expand_stmt :: CT_EXPAND '(' expr ')'
*>
fn Node*? parse_ct_expand_stmt(ParseContext* ctx)
{
	expect(ctx, CT_EXPAND)!;

	int start_pos = ctx.current().pos;
	Node* node    = ctx.ast.alloc_node(CT_EXPAND_STMT, start_pos);
	defer node.end_token = ctx.current().pos;
	CtExpandStmt* exp = node.as(CT_EXPAND_STMT);

	expect(ctx, LPAREN)!;
	exp.expr = parse_expr(ctx)!;
	expect(ctx, RPAREN)!;
	expect(ctx, EOS)!;
	return node;
}
