module c3_parser::parser;

import std::io;
import lexer;
import line_map;
import c3_parser::ast;
import c3_parser::common;

// Colors for the terminal
const String ANSI_RED    = "\x1b[31;1m";
const String ANSI_YELLOW = "\x1b[33;1m";
const String ANSI_CYAN   = "\x1b[36;1m";
const String ANSI_RESET  = "\x1b[0m";
const String ANSI_BOLD   = "\x1b[1m";

macro void Parser.info(self, String fmt, ...)
{
	self.report(self.current(), "info", ANSI_CYAN, fmt, ...$vaarg);
}

macro void Parser.warn(self, String fmt, ...)
{
	self.report(self.current(), "warning", ANSI_YELLOW, fmt, ...$vaarg);
}

macro void Parser.error(self, String fmt, ...)
{
	log::error(fmt, ...$vaarg);
	self.report(self.current(), "error", ANSI_RED, fmt, ...$vaarg);
}

macro void Parser.error_at(self, Token t, String fmt, ...)
{
    self.report(t, "error", ANSI_RED, fmt, ...$vaarg);
}

fn void Parser.report(Parser* self, Token token, String level, String color, String fmt, args ...)
{
	Location loc = self.line_map.resolve(token.pos);

	io::printf("%s:%s:%s: %s%s:%s ", self.file_path, loc.line, loc.column, color, level, ANSI_RESET);
	io::printf(fmt, args);
	io::printn("");

	String line_text = self.line_map.get_line_from_src(self.src, loc.line);
	io::printf(" %4s | %s\n", loc.line, line_text);

	io::printf(" %4s | ", "");
	for (uint i = 1; i < loc.column; i++)
	{
		if (line_text[i - 1] == '\t')
		{
			io::print("\t");
		}
		else
		{
			io::print(" ");
		}
	}
	io::printf("%s^%s\n", color, ANSI_RESET);
}

fn bool is_keyword_ident(TokenKind type)
{
	return type >= ALIAS && type <= WHILE;
}

fn bool is_base_type(TokenKind kind)
{
	return kind >= VOID && kind <= UNTYPEDLIST;
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
    return k == IDENT || 
           k == HASH_IDENT || 
           k == CT_IDENT;
}

fn bool node_ends_with_block(Parser* p, Node n)
{
	NodeKind kind = p.ast.get_kind(n);

	log::debug("%s", kind);
	switch (kind)
	{
		case CALL_EXPR:
		case ATTR_CALL_EXPR:
			CallView view = { p.ast, n };
			return view.get_compound().is_valid();
		case COMPOUND_STMT:
			return true;
		default:
			return false;
	}
}

fn bool is_type(Parser* p)
{
	TokenKind kind = p.current().kind;

	if (is_type_primitive(kind)) return true;
	if (kind == TYPE_IDENT) return true;

	if (kind == IDENT && p.peek(1).kind == SCOPE)
    {
        return true;
    }

	return false;
}

fn bool is_type_primitive(TokenKind kind)
{
	switch (kind)
	{
		case BOOL:
		case CHAR:
		case DOUBLE:
		case FLOAT:
		case FLOAT16:
		case BFLOAT:
		case INT128:
		case ICHAR:
		case INT:
		case IPTR:
		case LONG:
		case SHORT:
		case UINT128:
		case UINT:
		case ULONG:
		case UPTR:
		case USHORT:
		case USZ:
		case SZ:
		case FLOAT128:
		case TYPEID:
		case FAULT:
		case ANY:
		case VOID:
		case CT_TYPE_IDENT:
		case CT_TYPEOF:
		case CT_TYPEFROM:
			return true;
		default:
			return false;
	}
}

fn void attach_contract(Parser* p, Node decl, Node contract)
{
	if (!decl.is_valid()) return;
	if (!contract.is_valid()) return;

    NodeKind kind = p.ast.get_kind(decl);
    
    uint offset = 0;
    switch (kind)
    {
		case MODULE_DECL:  offset = ModuleViewFields.CONTRACT;
        case FN_DECL:      offset = FnViewFields.CONTRACT;
        case STRUCT_DECL:  offset = StructViewFields.CONTRACT;
		case UNION_DECL:   offset = StructViewFields.CONTRACT;
        default: return;
    }
    
	uint base_extra_idx = p.ast.get_extra((uint)decl);
    p.ast.set_extra(base_extra_idx + offset, (uint)contract);
}

fn OverloadKind get_overload_from_token(TokenKind kind)
{
	switch (kind)
	{
		case PLUS: return OverloadKind.PLUS;
		case PLUS_ASSIGN: return OverloadKind.PLUS_ASSIGN;
		case MINUS: return OverloadKind.MINUS;
		case MINUS_ASSIGN: return OverloadKind.MINUS_ASSIGN;
		case ASTERISK: return OverloadKind.MULTIPLY;
		case MULT_ASSIGN: return OverloadKind.MULTIPLY_ASSIGN;
		case DIV: return OverloadKind.DIVIDE;
		case DIV_ASSIGN: return OverloadKind.DIVIDE_ASSIGN;
		case MOD: return OverloadKind.REMINDER;
		case MOD_ASSIGN: return OverloadKind.REMINDER_ASSIGN;
		case AMP: return OverloadKind.AND;
		case BIT_AND_ASSIGN: return OverloadKind.AND_ASSIGN;
		case BIT_OR: return OverloadKind.OR;
		case BIT_OR_ASSIGN: return OverloadKind.OR_ASSIGN;
		case BIT_XOR: return OverloadKind.XOR;
		case BIT_XOR_ASSIGN: return OverloadKind.XOR_ASSIGN;
		case LSHIFT: return OverloadKind.SHL;
		case LSHIFT_ASSIGN: return OverloadKind.SHL_ASSIGN;
		case RSHIFT: return OverloadKind.SHR;
		case RSHIFT_ASSIGN: return OverloadKind.SHR_ASSIGN;
		case BIT_NOT: return OverloadKind.NEGATE;
		case EQEQ: return OverloadKind.EQUAL;
		case NOT_EQUAL: return OverloadKind.NOT_EQUAL;
		default:
			unreachable();
	}
}

fn bool is_declaration_followup(Parser* p)
{
	uint i;

	while (p.peek(i).kind == IDENT && p.peek(i + 1).kind == SCOPE)
    {
        i += 2;
    }

	i++;

	if (p.is(CT_TYPEFROM) || p.is(CT_TYPEOF))
	{
		i++;
		uint depth = 1;
		do {
			if (p.peek(i).kind == LPAREN) depth++;
			if (p.peek(i).kind == RPAREN) depth--;

			i++;
		} while (depth != 0 && p.peek(i).kind != EOF);
	}

	while (true)
	{
		TokenKind k = p.peek(i).kind;

		// Skip over common type modifiers
		if (k == ASTERISK || k == QUESTION) 
		{
			i++;
		} 
		else if (k == LBRACKET) 
		{
			// Skip the entire [ ... ] block
			i++;
			while (p.peek(i).kind != RBRACKET && p.peek(i).kind != EOF) i++;
			i++; 
		} 
		else if (k == LVEC)
		{
			// Skip the entire <* ... > block
			i++;
			while (p.peek(i).kind != RVEC && p.peek(i).kind != EOF) i++;
			i++;
		}
		else 
		{
			break;
		}
	}

	// After skipping modifiers, do we see a variable name?
	TokenKind final_k = p.peek(i).kind;
	return final_k == IDENT || final_k == CONST_IDENT || final_k == CT_IDENT;
}

fn uint? parse_type_name(Parser* p, String msg)
{
	if (p.is(IDENT)) 
	{
		p.error("Name of %s must start with and uppercase letter", msg);
		return 0;
	}
	else if (p.is(CONST_IDENT))
	{
		p.error("Name of %s cannot be all uppercase", msg);
		return 0;
	}
	else
	{
		if (!p.is(TYPE_IDENT))
		{
			p.error("'%s' should be followed by the name of the %s.", msg, msg);
			return 0;
		}
	}

	uint name = p.pool.intern(p.current_text());
	advance(p)!;
	return name;
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
		case INTEGER: 
		case FLOAT:
		case REAL:
		case STRING:
		case CHAR_LITERAL:
		case LPAREN:
		case MINUS:
		case BANG:
		case BIT_NOT:
		case AMP:
		case ASTERISK:
			return true;
		default:
			return false;
	}
}

fn int base64_to_sextet(char c)
{
	if (c >= 'A' && c <= 'Z') return c - 'A';
	if (c >= 'a' && c <= 'z') return c - 'a' + 26;
	if (c >= '0' && c <= '9') return c - '0' + 52;
	if (c == '+')             return 62;
	if (c == '/')             return 63;
	if (c == '=')             return 0;
	return -1;
}
