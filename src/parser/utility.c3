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
    self.report(self.current(), "info", ANSI_CYAN, fmt, $vasplat);
}

macro void Parser.warn(self, String fmt, ...)
{
    self.report(self.current(), "warning", ANSI_YELLOW, fmt, $vasplat);
}

macro void Parser.error(self, String fmt, ...)
{
	log::error(fmt, $vasplat);
    self.report(self.current(), "error", ANSI_RED, fmt, $vasplat);
}

fn void Parser.report(Parser* self, Token token, String level, String color, String fmt, args...)
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
	return type >= TokenKind.ALIAS
		&& type <= TokenKind.WHILE;
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


fn bool is_type(TokenKind kind)
{
	switch (kind)
	{
		case TokenKind.BOOL:
		case TokenKind.CHAR:
		case TokenKind.DOUBLE:
		case TokenKind.FLOAT:
		case TokenKind.FLOAT16:
		case TokenKind.BFLOAT16:
		case TokenKind.INT128:
		case TokenKind.ICHAR:
		case TokenKind.INT:
		case TokenKind.IPTR:
		case TokenKind.LONG:
		case TokenKind.SHORT:
		case TokenKind.UINT128:
		case TokenKind.UINT:
		case TokenKind.ULONG:
		case TokenKind.UPTR:
		case TokenKind.USHORT:
		case TokenKind.USZ:
		case TokenKind.ISZ:
		case TokenKind.FLOAT128:
		case TokenKind.TYPEID:
		case TokenKind.FAULT:
		case TokenKind.ANY:
		case TokenKind.VOID:
		case TokenKind.TYPE_IDENT:
		case TokenKind.CT_TYPE_IDENT:
		case TokenKind.CT_TYPEOF:
		case TokenKind.CT_EVALTYPE:
		case TokenKind.CT_VATYPE:
		case TokenKind.CT_TYPEFROM:
			return true;
		default: 
			return false;
	}
}
