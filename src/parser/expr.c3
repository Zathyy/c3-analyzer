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

fn Node*? parse_literal_expr(ParseContext* ctx)
{
	Token token = ctx.current();
	int start = token.pos;

	Node* node = ctx.ast.alloc_node(LITERAL_EXPR, start);
	LiteralExpr* literal = node.as(LITERAL_EXPR);
	String token_text = ctx.token_text(token);

	switch (token.kind)
	{
		case NULL:
			literal.kind = NULL;
			break;
		case TRUE:
			literal.kind = BOOL;
			literal.boolean = true;
			break;
		case FALSE:
			literal.kind = BOOL;
			literal.boolean = false;
			break;
		default:
			if (token.kind.is_int_literal())
			{
				literal.kind = INTEGER;
				long? value = token_text.to_long();
				if (catch err = value)
				{
					ctx.error("Failed to parse int literal: %s", err);
					return ctx.ast.error(start);
				}
				literal.integer = value;
				break;
			}
			else 
			{
				unreachable("Not implemented!");
			}
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

		expr.expr_string = parse_ident_expr(ctx)!;
	}

	return node;
}
