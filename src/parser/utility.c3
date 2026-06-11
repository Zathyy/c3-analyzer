module parser::parser;

import parser::plog;

import std::io;
import std::collections::list;
import lexer;
import line_map;
import parser::ast;

// Colors for the terminal
const String ANSI_RED    = "\x1b[31;1m";
const String ANSI_YELLOW = "\x1b[33;1m";
const String ANSI_CYAN   = "\x1b[36;1m";
const String ANSI_RESET  = "\x1b[0m";
const String ANSI_BOLD   = "\x1b[1m";

macro void ParseContext.info(&self, String fmt, ...)
{
	self.report(self.peek(), INFO, ANSI_CYAN, fmt, ...$vaarg);
}

macro void ParseContext.warn(&self, String fmt, ...)
{
	self.report(self.peek(), WARN, ANSI_YELLOW, fmt, ...$vaarg);
}

macro void ParseContext.error(&self, String fmt, ...)
{
	self.report(self.peek(), ERROR, ANSI_RED, fmt, ...$vaarg);
}

macro void ParseContext.error_at(&self, Token t, String fmt, ...)
{
	self.report(t, ERROR, ANSI_RED, fmt, ...$vaarg);
}

fn void ParseContext.report(ParseContext* self, Token token, LogPriority level, String color, String fmt, args...)
{
	Location loc = self.line_map.resolve(token.pos);
	$if $feature(PARSER_LIB):
		self.errors.push({ level, loc, token, string::format(self.allocator, fmt, ...args) });
	$else
		io::printf("%s:%s:%s: %s%s:%s ", self.file_path, loc.line, loc.column, color, level.description, ANSI_RESET);
		io::printf(fmt, ...args);
		io::printn("");

		String line_text = self.line_map.get_line_from_src(self.src, loc.line);
		io::printf(" %4s | %s\n", loc.line, line_text);

		io::printf(" %4s | ", "");
		for (sz i = 1; i < loc.column; i++)
		{
			if (i - 1 < line_text.len && line_text[i - 1] == '\t')
			{
				io::print("\t");
			}
			else
			{
				io::print(" ");
			}
		}
		io::printf("%s^%s\n", color, ANSI_RESET);
	$endif
}

fn bool is_keyword_ident(TokenKind type)
{
	return type >= ALIAS && type <= WHILE;
}

fn bool is_base_type(TokenKind kind)
{
	return kind >= VOID_TYPE && kind <= UNTYPEDLIST_TYPE;
}

fn bool is_some_ident(TokenKind type)
{
	switch (type)
	{
		case TYPE_IDENT:
		case IDENT:
		case CONST_IDENT:
			return true;
		default:
			return false;
	}
}

fn bool is_non_type_ident(TokenKind k)
{
	return k == IDENT || k == HASH_IDENT || k == CT_IDENT;
}

fn bool is_type(ParseContext* ctx)
{
	TokenKind kind = ctx.peek().kind;

	if (is_type_primitive(kind)) return true;
	if (kind == TYPE_IDENT) return true;

	// if (kind == IDENT && ctx.peek(1).kind == SCOPE)
	// {
	// 	return true;
	// }

	return false;
}

fn bool is_alias_name_kind(TokenKind kind)
{
	switch (kind)
	{
		case TYPE_IDENT:
		case IDENT:
		case CONST_IDENT:
		case AT_IDENT:
			return true;
		default:
			return false;
	}
}

fn bool is_alias_source_name_kind(TokenKind kind)
{
	switch (kind)
	{
		case IDENT:
		case CONST_IDENT:
		case AT_IDENT:
			return true;
		default:
			return false;
	}
}

<*
 Return whether kind may appear as a path's final segment with options.
 @param kind : "Candidate token kind for the segment."
 @param options : "Final-segment allowances used by the caller."
*>
fn bool is_path_final_kind(TokenKind kind, PathExprOptions options)
{
	if (kind == IDENT) return true;
	if (options.allow_const_final && kind == CONST_IDENT) return true;
	if (options.allow_attr_final && kind == AT_IDENT) return true;
	return false;
}

<*
 Append an arena-owned node slice into a temporary node list.
 @param [&inout] list : "Destination list."
 @param nodes : "Nodes to append."
*>
fn void append_node_array(List{Node*}* list, NodeArray nodes)
{
	foreach (node : nodes)
	{
		list.push(node);
	}
}

<*
 Parse attributes at the current token and append them into an existing list.
 @param [&inout] ctx : "Parser context to consume attributes from."
 @param [&inout] parent_node : "Node receiving visibility and has-attributes side effects."
 @param [&inout] list : "Destination list for parsed ATTRIBUTE_DECL nodes."
*>
fn void? parse_attributes_into(ParseContext* ctx, Node* parent_node, List{Node*}* list)
{
	if (ctx.is(AT_IDENT))
	{
		append_node_array(list, parse_attributes(ctx, parent_node)!);
	}
}

<*
 Parse an optional parenthesized list of interface type expressions.

 interface_type_list ::= '(' type_expr (',' type_expr)* ')' | empty
 @param [&inout] ctx : "Parser context positioned at '(' when present."
*>
fn NodeArray? parse_interface_type_list(ParseContext* ctx, ParseFlags flags = { }) => @pool()
{
	List{Node*} interfaces;
	interfaces.init(tmem, 4);

	if (!consume(ctx, LPAREN)!)
	{
		return alloc::clone_slice(ctx.arena, interfaces.array_view());
	}

	while (!ctx.eof() && !ctx.is(RPAREN))
	{
		Node* interface_type = parse_type_expr(ctx, null, flags)!;
		interfaces.push(interface_type);

		if (!consume(ctx, COMMA)!) break;
		if (ctx.is(RPAREN))
		{
			interfaces.push(unexpected(ctx, "Expected interface name after ',' in interface type list")!);
			break;
		}
	}

	@expect_else(ctx, RPAREN ; err)
	{
		interfaces.push(err);
	}!;

	return alloc::clone_slice(ctx.arena, interfaces.array_view());
}

fn bool is_error_or_missing_node(Node* node)
{
	return node.kind == ERROR || node.kind == MISSING;
}

fn void? skip_balanced_group(ParseContext* ctx, TokenKind open, TokenKind close)
{
	expect(ctx, open)!;

	int depth = 1;
	while (!ctx.eof() && depth > 0)
	{
		if (ctx.is(open))
		{
			depth++;
		}
		else if (ctx.is(close))
		{
			depth--;
		}

		advance(ctx)!;
	}
}

fn bool is_type_primitive(TokenKind kind)
{
	switch (kind)
	{
		case BOOL_TYPE:
		case CHAR_TYPE:
		case DOUBLE_TYPE:
		case FLOAT_TYPE:
		case FLOAT16_TYPE:
		case BFLOAT_TYPE:
		case INT128_TYPE:
		case ICHAR_TYPE:
		case INT_TYPE:
		case IPTR_TYPE:
		case LONG_TYPE:
		case SHORT_TYPE:
		case UINT128_TYPE:
		case UINT_TYPE:
		case ULONG_TYPE:
		case UPTR_TYPE:
		case USHORT_TYPE:
		case USZ_TYPE:
		case SZ_TYPE:
		case FLOAT128_TYPE:
		case TYPEID_TYPE:
		case FAULT_TYPE:
		case ANY_TYPE:
		case VOID_TYPE:
		case CT_TYPE_IDENT:
		case CT_TYPEOF:
		case CT_TYPEFROM:
			return true;
		default:
			return false;
	}
}

fn OverloadKind get_overload_from_token(TokenKind kind)
{
	switch (kind)
	{
		case PLUS: return OV_PLUS;
		case PLUS_ASSIGN: return OV_PLUS_ASSIGN;
		case MINUS: return OV_MINUS;
		case MINUS_ASSIGN: return OV_MINUS_ASSIGN;
		case ASTERISK: return OV_MULTIPLY;
		case MULT_ASSIGN: return OV_MULTIPLY_ASSIGN;
		case DIV: return OV_DIVIDE;
		case DIV_ASSIGN: return OV_DIVIDE_ASSIGN;
		case MOD: return OV_REMINDER;
		case MOD_ASSIGN: return OV_REMINDER_ASSIGN;
		case AMP: return OV_AND;
		case BIT_AND_ASSIGN: return OV_AND_ASSIGN;
		case BIT_OR: return OV_OR;
		case BIT_OR_ASSIGN: return OV_OR_ASSIGN;
		case BIT_XOR: return OV_XOR;
		case BIT_XOR_ASSIGN: return OV_XOR_ASSIGN;
		case LSHIFT: return OV_SHL;
		case LSHIFT_ASSIGN: return OV_SHL_ASSIGN;
		case RSHIFT: return OV_SHR;
		case RSHIFT_ASSIGN: return OV_SHR_ASSIGN;
		case BIT_NOT: return OV_NEGATE;
		case EQEQ: return OV_EQUAL;
		case NOT_EQUAL: return OV_NOT_EQUAL;
		default:
			unreachable();
	}
}

fn bool is_declaration_followup(ParseContext* ctx)
{
	int i;

	while (ctx.peek(i).kind == IDENT && ctx.peek(i + 1).kind == SCOPE)
	{
		i += 2;
	}

	i++;

	if (ctx.is(CT_TYPEFROM) || ctx.is(CT_TYPEOF))
	{
		i++;
		int depth = 1;
		do
		{
			if (ctx.peek(i).kind == LPAREN) depth++;
			if (ctx.peek(i).kind == RPAREN) depth--;

			i++;
		} while (depth != 0 && ctx.peek(i).kind != EOF);
	}

	while (true)
	{
		TokenKind k = ctx.peek(i).kind;

		// Skip over common type modifiers
		if (k == ASTERISK || k == QUESTION)
		{
			i++;
		}
		else if (k == LBRACKET)
		{
			// Skip the entire [ ... ] block
			i++;
			while (ctx.peek(i).kind != RBRACKET && ctx.peek(i).kind != EOF) i++;
			i++;
		}
		else if (k == LVEC)
		{
			// Skip the entire <* ... > block
			i++;
			while (ctx.peek(i).kind != RVEC && ctx.peek(i).kind != EOF) i++;
			i++;
		}
		else if (k == LBRACE)
		{
			i++;
			while (ctx.peek(i).kind != RBRACE && ctx.peek(i).kind != EOF) i++;
			i++;
		}
		else
		{
			break;
		}
	}

	// After skipping modifiers, do we see a variable name?
	TokenKind final_k = ctx.peek(i).kind;
	return final_k == IDENT || final_k == CONST_IDENT || final_k == CT_IDENT;
}

fn bool can_start_expression(TokenKind kind)
{
	if (is_keyword_ident(kind) || is_base_type(kind))
	{
		return true;
	}

	switch (kind)
	{
		case IDENT:
		case AT_IDENT:
		case TYPE_IDENT:
		case CT_TYPE_IDENT:
		case CT_IDENT:
		case CONST_IDENT:
		case HASH_IDENT:
		case HASH_TYPE_IDENT:
		case BUILTIN:
		case FLOAT_DECIMAL_LITERAL:
		case FLOAT_HEX_LITERAL:
		case INT_DECIMAL_LITERAL:
		case INT_HEX_LITERAL:
		case INT_OCTAL_LITERAL:
		case INT_BIN_LITERAL:
		case STRING_LITERAL:
		case CHAR_LITERAL:
		case LPAREN:
		case MINUS:
		case BANG:
		case BIT_NOT:
		case AMP:
		case ASTERISK:
		case LBRACE:
			return true;
		default:
			return false;
	}
}

fn bool token_type_ends_case(TokenKind kind)
{
	return kind == CASE || kind == DEFAULT || kind == CT_DEFAULT || kind == RBRACE || kind == CT_CASE
		|| kind == CT_ENDSWITCH;
}

fn bool check_if_typed_parameter(ParseContext* ctx)
{
	TokenKind first  = ctx.peek(0).kind;
	TokenKind second = ctx.peek(1).kind;

	if (is_type_primitive(first) || first == TYPE_IDENT)
	{
		return true;
	}
	return false;
}

fn Node* alloc_any_type_expr(ParseContext* ctx)
{
	int pos = ctx.peek(0).pos;

	Node* type_node = ctx.ast.alloc_node(TYPE_EXPR, pos, pos);
	TypeExpr* data  = type_node.as(TYPE_EXPR);

	data.kind = TypeKind.TYPE_IDENTIFIER;
	data.unresolved.name = ctx.ast.string_pool.internalize("any");
	data.unresolved.path = ctx.ast.alloc_node(MISSING, pos);

	return type_node;
}
