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

fn bool is_type(TokenKind kind)
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
		case TYPE_IDENT:
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
	if (!decl.is_valid()) return;

    NodeKind kind = ast::get_kind(p.ast, decl);

	if (kind == MODULE_DECL) return;
    
    uint offset = 0;
    switch (kind)
    {
		case MODULE_DECL:  offset = 3;
        case FN_DECL:      offset = 4;
        case VAR_DECL:     offset = 3;
        case STRUCT_DECL:  offset = 3;
        default: return;
    }
    
	uint base_extra_idx = ast::get_extra(p.ast, (uint)decl);
    p.ast.set_extra(base_extra_idx + offset, (uint)contract);
}