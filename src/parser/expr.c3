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


fn Node*? parse_type_expr(ParseContext* ctx, ParseFlags parse_flags = {})
{
	int start = ctx.peek(0).pos;

    Node* current_type = ctx.ast.alloc_node(TYPE_EXPR, start, ctx.peek().pos);
    TypeExpr* data = current_type.as(TYPE_EXPR);

    // Check for built-in primitive keywords (int, void, double, etc.)
    if (is_type_primitive(ctx.peek(0).kind))
    {
        Token t = ctx.peek(0);
        advance(ctx)!;
        
        data.kind = TYPE_IDENTIFIER;
        data.unresolved.name = ctx.ast.string_pool.internalize(ctx.token_text(t));
        data.unresolved.path = null;
    }
    else
    {
        Node* path = parse_path_expr(ctx, true)!;
        if (path.kind == ERROR) return path;

		if (!ctx.is(TYPE_IDENT))
		{
			ctx.error("Expected TypeIdent, got %s", ctx.current_text());
			return ctx.ast.error(ctx.current().pos);
		}

		advance(ctx)!;
	
        data.kind = TYPE_IDENTIFIER;
        data.unresolved.name = ctx.ast.string_pool.internalize(ctx.token_text(ctx.current()));
        data.unresolved.path = path;
    }

    current_type.end_token = ctx.peek(0).pos;

    while (true)
    {
        Token t = ctx.peek(0);

        if (t.kind == ASTERISK)
        {
            advance(ctx)!;

            Node* ptr_node = ctx.ast.alloc_node(TYPE_EXPR, start, t.pos);
            TypeExpr* ptr_data = ptr_node.as(TYPE_EXPR);
            
            ptr_data.kind = TYPE_POINTER;
            ptr_data.modify.base = current_type; // The previous node becomes the base
            
            // Swap current_type out so the next iteration wraps THIS layer
            current_type = ptr_node;
            continue;
        }

        if (t.kind == LBRACKET)
        {
            advance(ctx)!;

            Node* arr_node = ctx.ast.alloc_node(TYPE_EXPR, start, ctx.peek().pos);
            TypeExpr* arr_data = arr_node.as(TYPE_EXPR);

            if (ctx.is(RBRACKET))
            {
                advance(ctx)!;
                arr_data.kind = TYPE_SLICE;
                arr_data.modify.base = current_type;
            }
            else if (ctx.is(ASTERISK) && ctx.peek(1).kind == RBRACKET)
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
                
                if (!consume(ctx, RBRACKET)!)
                {
                    ctx.error("Expected a closing ']'");
                    return ctx.ast.error(start);
                }
			}

            arr_node.end_token = ctx.peek(0).pos;
            current_type = arr_node;
            continue;
        }

        // Handle Generics: '{' ... '}'
        if (t.kind == LBRACE)
        {
            if (parse_flags.no_generics) break;

            Node* gen_node = ctx.ast.alloc_node(TYPE_EXPR, start, ctx.peek().pos);
            TypeExpr* gen_data = gen_node.as(TYPE_EXPR);
            
            gen_data.kind = TYPE_GENERIC;
            gen_data.generic.base = current_type;
            gen_data.generic.params = parse_generics_list(ctx)!;

            gen_node.end_token = ctx.peek(0).pos;
            current_type = gen_node;
            continue;
        }

        break;
    }

    return current_type;
}

fn Node*? parse_ident_expr(ParseContext* ctx)
{
	int start = ctx.peek(0).pos;
	if (ctx.peek(1).kind == SCOPE)
	{
		return parse_path_expr(ctx, true)!;
	}
	Node* node = ctx.ast.alloc_node(IDENT_EXPR, start, ctx.peek().pos);
	IdentExpr* ident = node.as(IDENT_EXPR);
	ident.ident = ctx.ast.string_pool.internalize(ctx.token_text(ctx.peek(0)));
	advance(ctx)!;
	return node;
}

fn Node*? parse_literal_expr(ParseContext* ctx) => @pool()
{
	Token token = ctx.current();
	int start = token.pos;

	Node* node = ctx.ast.alloc_node(LITERAL_EXPR, start);
	defer node.end_token = ctx.current().pos;
	LiteralExpr* literal = node.as(LITERAL_EXPR);
	String token_text = ctx.token_text(token);

	log::debug("literal_expr: %s", token.kind);

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
            if (token.kind == INT_HEX_LITERAL)        { base = 16; start_idx = 2; }
            else if (token.kind == INT_BIN_LITERAL)   { base = 2;  start_idx = 2; }
            else if (token.kind == INT_OCTAL_LITERAL) { base = 8;  start_idx = 2; }
            else                                      { base = 10; start_idx = 0; }

			String body = clean_string[start_idx..];
			usz end_idx = body.len;
            while (end_idx > 0)
            {
                char last_char = body[end_idx - 1];
                if (ascii::is_alpha(last_char))
                {
                    if (base == 16 && ascii::is_xdigit(last_char)) break;
                    if (base == 10 && ascii::is_digit(last_char))  break; 
                    if (base == 8  && ascii::is_odigit(last_char)) break;
                    if (base == 2  && ascii::is_bdigit(last_char)) break;

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
            sz len = clean_string.len;
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
				char[]? b64 = base64::decode(tmem, clean);
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
				log::debug("%s", final);
				if (final.len % 2 != 0)
                {
                    ctx.error("Hex literal payload must have an even number of digits (got %s chars in '%s')", 
                              final.len, final);
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
		default:
			unreachable("Not implemented!");
	}

	return node;
}

<*
	Parse a full path e.g. foo::bar::baz;
	@param [&inout] ctx
*>
fn Node*? parse_path_expr(ParseContext* ctx, bool as_prefix = false) => @pool()
{
	int start_pos = ctx.peek(0).pos;

	if (!ctx.is(IDENT))
	{
		if (ctx.peek(1).kind != SCOPE)
		{
			if (as_prefix)
			{
				return ctx.ast.alloc_node(MISSING, start_pos);
			}
		}

		ctx.error("Expected a path identifier here");
		return ctx.ast.error(start_pos);
	}

	Node* node = ctx.ast.alloc_node(PATH_EXPR, start_pos, ctx.peek().pos);
	PathExpr* path = node.as(PATH_EXPR);
	defer node.end_token = ctx.peek(0).pos;

	List{StringID} temp_segments;
	temp_segments.init(tmem, 8);

	while (true)
	{
		Token t = ctx.peek(0);
		temp_segments.push(ctx.ast.string_pool.internalize(ctx.token_text(t)));
		advance(ctx)!;

		if (!consume(ctx, SCOPE)!) break;

		if (!ctx.is(IDENT))
		{
			if (!as_prefix)
			{
				temp_segments.push(-1);
				node.kind = MISSING;
			}
			break;
		}
	}

	path.segments = alloc::clone_slice(ctx.arena, temp_segments.array_view());
	return node;
}

fn Node*? parse_binary_expr(ParseContext* ctx, Node* left, Precedence prec) 
{
	int start = ctx.peek(0).pos;
	TokenKind kind = ctx.peek(0).kind;
	advance(ctx)!;
	Node* right = parse_expr(ctx, prec)!;

	Node* node = ctx.ast.alloc_node(BINARY_EXPR, start, ctx.peek(0).pos);
	BinaryExpr* bin = node.as(BINARY_EXPR);
	bin.left = left;
	bin.right = right;
	bin.op = parser::binaryop_from_token(kind);
	return node;
}

<*
	expr_list ::= decl_or_expr*
*>
fn Node*? parse_expr_list(ParseContext* ctx) => @pool()
{
	int start_pos = ctx.current().pos;
	Node* node = ctx.ast.alloc_node(EXPR_LIST, start_pos);
	ExprList* list = node.as(EXPR_LIST);
	defer node.end_token = ctx.current().pos;
	List{Node*} exprs; exprs.tinit();
	while (!ctx.eof())
	{	
		exprs.push(parse_decl_or_expr(ctx)!);
		if (!consume(ctx, COMMA)!) break;
	}

	list.exprs = alloc::clone_slice(ctx.arena, exprs.array_view());
	return node;
}

<*
	contract_expr ::= expr_list (':'? STRING)?
*>
fn Node*? parse_contract_expr(ParseContext* ctx)
{
	int start_pos = ctx.peek(0).pos;
	Node* node = ctx.ast.alloc_node(CONTRACT_EXPR, start_pos);
	defer node.end_token = ctx.peek(0).pos;
	ContractExpr* expr = node.as(CONTRACT_EXPR);

	expr.exprs = parse_expr_list(ctx)!;

	if (consume(ctx, COLON)!)
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
