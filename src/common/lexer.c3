module lexer;

import std::io;
import parser::plog;

faultdef
	INVALID, UNEVEN_HEXADECIMAL, CONTRACT_NOT_CLOSED, INVALID_CONTRACT
;

enum TokenKind : ushort
{
	INVALID,
	// Invalid


	// Operators
	AMP,
	// &


	BIT_OR,
	// |


	BIT_XOR,
	// ^


	BIT_NOT,
	// ~


	BANG,
	// !


	PLUS,
	// +


	MINUS,
	// -


	ASTERISK,
	// *


	DIV,
	// /


	MOD,
	// %


	QUESTION,
	// ?


	QUESTQUEST,
	// ??


	ELVIS,
	// ?:


	BANGBANG,
	// !!


	BUILTIN,
	// $$


	RSHIFT,
	// >>


	LSHIFT,
	// <<


	PLUSPLUS,
	// ++


	MINUSMINUS,
	// --


	CT_CONCAT_OP,
	// +++


	CT_TERNARY,
	// ???


	// Assignment
	EQ,
	// =


	RSHIFT_ASSIGN,
	// >>=


	LSHIFT_ASSIGN,
	// <<=


	PLUS_ASSIGN,
	// +=


	MINUS_ASSIGN,
	// -=


	MULT_ASSIGN,
	// *=


	DIV_ASSIGN,
	// /=


	MOD_ASSIGN,
	// %=


	BIT_AND_ASSIGN,
	// &=


	BIT_XOR_ASSIGN,
	// ^=


	BIT_OR_ASSIGN,
	// |=


	CT_CONCAT_ASSIGN,
	// +++=


	// Comparison
	LESS,
	// <


	GREATER,
	// >


	AND,
	// &&


	OR,
	// ||


	LESS_EQ,
	// <=


	GREATER_EQ,
	// >=


	EQEQ,
	// ==


	NOT_EQUAL,
	// !=


	CT_AND_OP,
	// &&&


	CT_OR_OP,
	// |||


	// Punctuation
	EOS,
	// ;


	COLON,
	// :


	SCOPE,
	// ::


	COMMA,
	// ,


	DOT,
	// .


	DOTDOT,
	// ..


	ELLIPSIS,
	// ...


	// Structure
	LBRACE,
	// {


	RBRACE,
	// }


	LBRACKET,
	// [


	RBRACKET,
	// ]


	LPAREN,
	// (


	RPAREN,
	// )


	ARROW,
	// ->


	IMPLIES,
	// =>


	LVEC,
	// [<


	RVEC,
	// >]


	// Comments and Contracts
	CONTRACT,
	// <*


	LINE_COMMENT,
	// //


	BLOCK_COMMENT,
	// /*


	// Literals (Identifiers and Strings)

	STRING_LITERAL, // STRING

	CHAR_LITERAL,  // 'a' 'FO' 'BARS' '\u1232'
	BYTES_LITERAL, // Base64 or Hex

	INT_DECIMAL_LITERAL, // 123
	INT_HEX_LITERAL,     // 0x23
	INT_OCTAL_LITERAL,   // 0o327
	INT_BIN_LITERAL,     // 0b10010

	FLOAT_DECIMAL_LITERAL, // 43.23e23
	FLOAT_HEX_LITERAL,     // 0x23.2p-2a

	<* foo *>
	IDENT,
	<* '@' *>
	AT,

	TYPE_IDENT,       // Foo,
	CONST_IDENT,      // FOO
	AT_IDENT,         // @foo
	AT_TYPE_IDENT,    // @Foo
	AT_CONST_IDENT,   // @FOO
	HASH_IDENT,       // #foo,
	HASH_TYPE_IDENT,  // #Type
	HASH_CONST_IDENT, // #CONST_IDENT
	CT_IDENT,         // $foo
	CT_TYPE_IDENT,    // $Foo,
	CT_CONST_IDENT,   // $FOO,

	// Base Types
	VOID_TYPE,
	BOOL_TYPE,
	CHAR_TYPE,
	DOUBLE_TYPE,
	FLOAT_TYPE,
	FLOAT16_TYPE,
	BFLOAT_TYPE,
	INT128_TYPE,
	ICHAR_TYPE,
	INT_TYPE,
	IPTR_TYPE,
	SZ_TYPE,
	LONG_TYPE,
	SHORT_TYPE,
	UINT128_TYPE,
	UINT_TYPE,
	ULONG_TYPE,
	UPTR_TYPE,
	USHORT_TYPE,
	USZ_TYPE,
	FLOAT128_TYPE,
	ANY_TYPE,
	FAULT_TYPE,
	TYPEID_TYPE,
	UNTYPEDLIST_TYPE,

	// Keywords
	ALIAS,
	ASSERT,
	ASM,
	ATTRDEF,
	BITSTRUCT,
	BREAK,
	CASE,
	CATCH,
	CONSTDEF,
	CONST,
	CONTINUE,
	DEFAULT,
	DEFER,
	DO,
	ELSE,
	ENUM,
	EXTERN,
	FALSE,
	FAULTDEF,
	FOR,
	FOREACH,
	FOREACH_R,
	FN,
	TLOCAL,
	IF,
	INLINE,
	IMPORT,
	LENGTHOF,
	MACRO,
	MODULE,
	NEXTCASE,
	NULL,
	INTERFACE,
	RETURN,
	STATIC,
	STRUCT,
	SWITCH,
	TRUE,
	TRY,
	TYPEDEF,
	UNION,
	VAR,
	WHILE,

	CT_ASSERT,
	// $assert


	CT_CASE,
	// $case


	CT_DEFAULT,
	// $default


	CT_DEFINED,
	// $defined


	CT_ECHO,
	// $echo


	CT_ELSE,
	// $else


	CT_EMBED,
	// $embed


	CT_ENDFOR,
	// $endfor


	CT_ENDFOREACH,
	// $endforeach


	CT_ENDIF,
	// $endif


	CT_ENDSWITCH,
	// $endswitch


	CT_EVAL,
	// $eval


	CT_ERROR,
	// $error


	CT_EXEC,
	// $exec


	CT_EXPAND,
	// $expand


	CT_FEATURE,
	// $feature


	CT_FOR,
	// $for


	CT_FOREACH,
	// $foreach


	CT_IF,
	// $if


	CT_INCLUDE,
	// $include


	CT_REFLECT,
	// $reflect


	CT_STRINGIFY,
	// $stringify


	CT_SWITCH,
	// $switch


	CT_TYPEFROM,
	// $Typefrom


	CT_TYPEOF,
	// $Typeof


	CT_VAARG,
	// $vaarg,


	AT_INLINE,
	AT_PURE,
	AT_NOINLINE,

	EOL,
	EOF
}

fn bool TokenKind.is_int_literal(
	&self
) @inline => TokenKind.INT_DECIMAL_LITERAL.ordinal <= self.ordinal && self.ordinal <= TokenKind.INT_BIN_LITERAL.ordinal;

fn bool TokenKind.is_float_literal(
	&self
) @inline => *self == TokenKind.FLOAT_DECIMAL_LITERAL || *self == TokenKind.FLOAT_HEX_LITERAL;

struct Token
{
	TokenKind kind;
	int pos; // Offset in the source buffer
	int len; // Length of the lexeme
}

bool is_in_contract = false;

struct Lexer
{
	String buffer;
	int index;
}

fn bool Token.is_eof(&self) @inline => self.kind == EOF;

fn bool is_digit(char c) @inline => c >= '0' && c <= '9';
fn bool is_alpha(char c) @inline => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
fn bool is_ident(char c) @inline => is_alpha(c) || is_digit(c) || c == '_';
fn bool is_hex(char c) @inline => ascii::is_xdigit(c);
fn bool is_whitespace(char c)
{
	switch (c)
	{
		case ' ':
		case '\t':
		case '\n':
		case '\r':
			return true;
		default:
			return false;
	}
}

fn bool is_all_upper(String text)
{
	bool has_alpha = false;
	if (text == "_") return false;

	for (usz i = 0; i < text.len; i++)
	{
		char c = text[i];
		if (c >= 'a' && c <= 'z') return false;
		if ((c >= 'A' && c <= 'Z') || c == '_') has_alpha = true;
	}
	return has_alpha; // Ensure "123_" isn't counted as CONST_IDENT
}

fn char Lexer.peek(Lexer* self, sz ahead = 0) @inline
{
	if (self.index + ahead >= self.buffer.len) return 0;
	return self.buffer[self.index + ahead];
}

fn bool Lexer.eof(&self) @inline
{
	return self.index >= self.buffer.len;
}

fn char Lexer.peek_next(Lexer* self) @inline
{
	if (self.index + 1 >= (int)self.buffer.len) return '\0';
	return self.buffer[self.index + 1];
}

fn void? Lexer.skip_whitespace(Lexer* self)
{
	while (self.index < self.buffer.len)
	{
		char c = self.buffer[self.index];

		switch (c)
		{
			case ' ':
			case '\t':
			case '\r':
			case '\n':
				self.index++;
				break;
			case '/':
				if (self.peek_next() == '/')
				{
					self.skip_line_comment()!;
				}
				else if (self.peek_next() == '*')
				{
					self.skip_block_comment()!;
				}
				else
				{
					return;
				}
				break;
			default:
				return;
		}
	}
}

fn void? Lexer.skip_line_comment(Lexer* self)
{
	self.index += 2;
	while (self.index < self.buffer.len && self.buffer[self.index] != '\n')
	{
		self.advance()!;
	}
}

fn void? Lexer.skip_block_comment(Lexer* self)
{
	self.index += 2; // Skip the initial '/*'
	int depth = 1;

	while (self.index < self.buffer.len && depth > 0)
	{
		// Look for nested start: '/*'
		if (self.buffer[self.index] == '/' && self.peek_next() == '*')
		{
			depth++;
			self.index += 2;
			continue;
		}

		// Look for end: '*/'
		if (self.buffer[self.index] == '*' && self.peek_next() == '/')
		{
			depth--;
			self.index += 2;
			continue;
		}

		self.advance()!;
	}
}

fn Token? Lexer.lex_char(Lexer* self, int start)
{
	self.index++;

	while (self.index < self.buffer.len)
	{
		char c = self.buffer[self.index];

		if (c == '\'')
		{
			self.index++;
			return (Token) { CHAR_LITERAL, start, self.index - start };
		}

		if (c == '\\')
		{
			self.index += 2;
			continue;
		}

		self.index++;
	}

	return (Token) { INVALID, start, self.index - start };
}

fn Token? Lexer.lex_string(Lexer* self, int start)
{
	self.index++;

	while (self.index < self.buffer.len)
	{
		char c = self.buffer[self.index];

		if (c == '"')
		{
			self.index++;
			return (Token) { STRING_LITERAL, start, self.index - start };
		}

		if (c == '\\')
		{
			self.index += 2;
			continue;
		}

		self.index++;
	}

	return (Token) { INVALID, start, self.index - start };
}

fn Token? Lexer.lex_raw_string(Lexer* self, int start)
{
	self.index++; // Skip the opening `

	while (self.index < self.buffer.len)
	{
		if (self.peek() == '`') // Only stop at a backtick
		{
			self.index++;
			return (Token) { STRING_LITERAL, start, self.index - start };
		}
		self.index++;
	}
	return (Token) { INVALID, start, self.index - start };
}

fn TokenKind lookup_keyword(String text)
{
	switch (text)
	{
		// Top-Level Explicit Keywords
		case "alias": return ALIAS;
		case "attrdef": return ATTRDEF;
		case "bitstruct": return BITSTRUCT;
		case "const": return CONST;
		case "constdef": return CONSTDEF;
		case "enum": return ENUM;
		case "faultdef": return FAULTDEF;
		case "fn": return FN;
		case "import": return IMPORT;
		case "interface": return INTERFACE;
		case "macro": return MACRO;
		case "module": return MODULE;
		case "typedef": return TYPEDEF;
		case "struct": return STRUCT;
		case "union": return UNION;
		// Explicit Keywords
		case "any": return ANY_TYPE;
		case "asm": return ASM;
		case "assert": return ASSERT;
		case "break": return BREAK;
		case "case": return CASE;
		case "catch": return CATCH;
		case "continue": return CONTINUE;
		case "default": return DEFAULT;
		case "defer": return DEFER;
		case "do": return DO;
		case "else": return ELSE;
		case "false": return FALSE;
		case "for": return FOR;
		case "foreach": return FOREACH;
		case "foreach_r": return FOREACH_R;
		case "if": return IF;
		case "lengthof": return LENGTHOF;
		case "nextcase": return NEXTCASE;
		case "null": return NULL;
		case "return": return RETURN;
		case "static": return STATIC;
		case "switch": return SWITCH;
		case "true": return TRUE;
		case "try": return TRY;
		case "var": return VAR;
		case "while": return WHILE;
		case "extern": return EXTERN;
		case "inline": return INLINE;
		case "tlocal": return TLOCAL;
		// Base
		case "void": return VOID_TYPE;
		case "bool": return BOOL_TYPE;
		case "char": return CHAR_TYPE;
		case "ichar": return ICHAR_TYPE;
		case "short": return SHORT_TYPE;
		case "ushort": return USHORT_TYPE;
		case "int": return INT_TYPE;
		case "uint": return UINT_TYPE;
		case "long": return LONG_TYPE;
		case "ulong": return ULONG_TYPE;
		case "int128": return INT128_TYPE;
		case "uint128": return UINT128_TYPE;
		case "iptr": return IPTR_TYPE;
		case "uptr": return UPTR_TYPE;
		case "sz": return SZ_TYPE;
		case "usz": return USZ_TYPE;
		case "float": return FLOAT_TYPE;
		case "double": return DOUBLE_TYPE;
		case "float16": return FLOAT16_TYPE;
		case "bfloat": return BFLOAT_TYPE;
		case "float128": return FLOAT128_TYPE;
		case "fault": return FAULT_TYPE;
		case "typeid": return TYPEID_TYPE;
		default: return IDENT;
	}
}

fn Token? Lexer.lex_identifier(Lexer* self, int start_pos)
{
	char first = self.peek();

	if (first == '@' || first == '$' || first == '#')
	{
		self.advance()!;
	}

	while (!self.eof() && is_ident(self.peek()))
	{
		self.advance()!;
	}

	int length = self.index - start_pos;
	if (length == 0) return INVALID~;

	String text = self.buffer[start_pos:length];

	TokenKind kind = self.categorize_identifier(text);

	return self.emit(kind, start_pos, length);
}

fn Token? Lexer.lex_number(Lexer* self, int start_pos)
{
	TokenKind kind = INT_DECIMAL_LITERAL;

	// Hex: 0x
	if (self.peek() == '0' && (ascii::to_lower(self.peek_next()) == 'x'))
	{
		kind = INT_HEX_LITERAL;
		self.advance(2)!;
		// Allow hex digits OR underscores
		while (!self.eof() && (ascii::is_xdigit(self.peek()) || self.peek() == '_'))
		{
			self.advance()!;
		}

		if (!self.eof() && self.peek() == '.' && self.peek_next() != '.') // && ascii::is_xdigit(self.peek_next()))
		{
			kind = FLOAT_HEX_LITERAL;
			self.advance()!;
			while (!self.eof() && (ascii::is_xdigit(self.peek()) || self.peek() == '_'))
			{
				self.advance()!;
			}
		}

		if (!self.eof() && (self.peek() == 'p' || self.peek() == 'P'))
		{
			char next = self.peek_next();
			if (ascii::is_xdigit(next) || next == '-' || next == '+')
			{
				kind = FLOAT_HEX_LITERAL;
				self.advance()!;
				if (next == '-' || next == '+') self.advance()!;
				while (!self.eof() && (ascii::is_xdigit(self.peek()) || self.peek() == '_'))
				{
					self.advance()!;
				}
			}
		}
	} // Binary: 0b
	else if (self.peek() == '0' && (ascii::to_lower(self.peek_next()) == 'b'))
	{
		kind = INT_BIN_LITERAL;
		self.advance(2)!;
		while (!self.eof() && (ascii::is_bdigit(self.peek()) || self.peek() == '_'))
		{
			self.advance()!;
		}
	} // Octal: 0o
	else if (self.peek() == '0' && (ascii::to_lower(self.peek_next()) == 'o'))
	{
		kind = INT_OCTAL_LITERAL;
		self.advance(2)!;
		while (!self.eof() && (ascii::is_odigit(self.peek()) || self.peek() == '_'))
		{
			self.advance()!;
		}
	}
	else
	{
		kind = INT_DECIMAL_LITERAL;

		// Standard Decimals
		while (!self.eof() && (ascii::is_digit(self.peek()) || self.peek() == '_'))
		{
			self.advance()!;
		}

		// Real/Float check
		if (!self.eof() && self.peek() == '.' && self.peek_next() != '.') // && ascii::is_digit(self.peek_next()))
		{
			kind = FLOAT_DECIMAL_LITERAL;
			self.advance()!;
			while (!self.eof() && (ascii::is_digit(self.peek()) || self.peek() == '_'))
			{
				self.advance()!;
			}
		}

		if (!self.eof() && (self.peek() == 'e' || self.peek() == 'E'))
		{
			char next = self.peek_next();
			if (ascii::is_digit(next) || next == '-' || next == '+')
			{
				kind = FLOAT_DECIMAL_LITERAL;
				self.advance()!;
				if (next == '-' || next == '+') self.advance()!;
				while (!self.eof() && (ascii::is_digit(self.peek()) || self.peek() == '_'))
				{
					self.advance()!;
				}
			}
		}
	}

	// Handle Suffixes (e.g., 1u, 1.0f, 0xFFu64)
	char c = (char)ascii::to_lower(self.peek());
	if (c == 'u' || c == 'i' || c == 'f' || c == 'l')
	{
		self.advance()!;
		while (!self.eof() && ascii::is_alnum(self.peek()))
		{
			self.advance()!;
		}
	}

	return self.emit(kind, start_pos, self.index - start_pos);
}

fn Token? Lexer.lex_hex_array(Lexer* self, int start_pos)
{
	char start_quote = self.peek();
	self.advance()!;

	int digit_count = 0;

	while (!self.eof())
	{
		char c = self.peek();

		if (c == start_quote)
		{
			self.advance()!;
			break;
		}

		if (is_whitespace(c))
		{
			self.advance()!;
			continue;
		}

		if (is_hex(c))
		{
			self.advance()!;
			digit_count++;
			continue;
		}

		plog::error("[Lexer]: Unexpected character '%c' in hex string at index %d", c, self.index);
		return INVALID~;
	}

	if (digit_count % 2 != 0)
	{
		plog::error("[Lexer]: The hexadecimal string is not an even length");
		return UNEVEN_HEXADECIMAL~;
	}

	return self.emit(BYTES_LITERAL, start_pos, self.index - start_pos);
}

fn Token? Lexer.skip_contract(Lexer* self, int start_pos)
{
	while (!self.eof())
	{
		char c = self.peek();
		if (c == '*' && self.peek(1) == '>')
		{
			self.advance(2)!;
			return self.emit(CONTRACT, start_pos, self.index - start_pos);
		}
		self.advance()!;
	}

	return CONTRACT_NOT_CLOSED~;
}

fn void? Lexer.advance(Lexer* self, int len = 1) @inline
{
	if (self.eof()) return io::EOF~;
	self.index += len;
}

fn Token Lexer.emit(&self, TokenKind kind, int pos, int len) @inline
{
	return (Token) { .kind = kind, .pos = pos, .len = len };
}

fn Token? Lexer.next(&self)
{
	self.skip_whitespace()!;

	if (self.eof())
	{
		return io::EOF~;
	}

	int start = self.index;
	char c    = self.peek();

	switch (c)
	{
		case '=':
			self.advance()!;
			switch (self.peek())
			{
				case '=': self.advance()!; return self.emit(EQEQ, start, 2);
				case '>': self.advance()!; return self.emit(IMPLIES, start, 2);
			}
			return self.emit(EQ, start, 1);
		case '|':
			self.advance()!;
			switch (self.peek())
			{
				case '|':
					if (self.peek(1) == '|')
					{
						self.advance(2)!;
						return self.emit(CT_OR_OP, start, 3);
					}

					self.advance()!;
					return self.emit(OR, start, 2);
				case '=': self.advance()!; return self.emit(BIT_OR_ASSIGN, start, 2);
			}
			return self.emit(BIT_OR, start, 1);
		case '!':
			self.advance()!;
			switch (self.peek())
			{
				case '!': self.advance()!; return self.emit(BANGBANG, start, 2);
				case '=': self.advance()!; return self.emit(NOT_EQUAL, start, 2);
			}
			return self.emit(BANG, start, 1);
		case ':':
			self.advance()!;
			if (self.peek() == ':')
			{
				self.advance()!;
				return self.emit(SCOPE, start, 2);
			}
			return self.emit(COLON, start, 1);
		case '[':
			self.advance()!;
			if (self.peek() == '<')
			{
				self.advance()!;
				return self.emit(LVEC, start, 2);
			}
			return self.emit(LBRACKET, start, 1);
		case ']':
			self.advance()!;
			return self.emit(RBRACKET, start, 1);
		case '>':
			self.advance()!;
			switch (self.peek())
			{
				case '>':
					self.advance()!;
					if (self.peek() == '=')
					{
						self.advance()!;
						return self.emit(RSHIFT_ASSIGN, start, 3);
					}
					return self.emit(RSHIFT, start, 2);
				case '=': self.advance()!; return self.emit(GREATER_EQ, start, 2);
				case ']': self.advance()!; return self.emit(RVEC, start, 2);
			}
			return self.emit(GREATER, start, 1);
		case '<':
			self.advance()!;
			switch (self.peek())
			{
				case '<':
					self.advance()!;
					if (self.peek() == '=')
					{
						self.advance()!;
						return self.emit(LSHIFT_ASSIGN, start, 3);
					}
					return self.emit(LSHIFT, start, 2);
				case '=': self.advance()!; return self.emit(LESS_EQ, start, 2);
				case '*': self.advance()!; return self.skip_contract(start);
			}
			return self.emit(LESS, start, 1);
		case '&':
			self.advance()!;
			switch (self.peek())
			{
				case '&':

					{
						if (self.peek(1) == '&')
						{
							self.advance(2)!;
							return self.emit(CT_AND_OP, start, 3);
						}

						self.advance()!;
						return self.emit(AND, start, 2);
					}
				case '=': self.advance()!; return self.emit(BIT_AND_ASSIGN, start, 2);
			}
			return self.emit(AMP, start, 1);
		case '*':
			self.advance()!;
			switch (self.peek())
			{
				case '=': self.advance()!; return self.emit(MULT_ASSIGN, start, 2);
			}
			return self.emit(ASTERISK, start, 1);
		case '?':
			self.advance()!;
			switch (self.peek())
			{
				case '?':
					self.advance()!;
					if (self.peek() == '?')
					{
						self.advance()!;
						return self.emit(CT_TERNARY, start, 3);
					}
					return self.emit(QUESTQUEST, start, 2);
				case ':': self.advance()!; return self.emit(ELVIS, start, 2);
			}
			return self.emit(QUESTION, start, 1);
		case '.':
			self.advance()!;
			if (self.peek() == '.')
			{
				if (self.peek(1) == '.')
				{
					self.advance(2)!;
					return self.emit(ELLIPSIS, start, 3);
				}

				self.advance()!;
				return self.emit(DOTDOT, start, 2);
			}
			return self.emit(DOT, start, 1);
		case '%':
			self.advance()!;
			if (self.peek() == '=')
			{
				self.advance()!;
				return self.emit(MOD_ASSIGN, start, 2);
			}
			return self.emit(MOD, start, 1);
		case '^':
			self.advance()!;
			if (self.peek() == '=')
			{
				self.advance()!;
				return self.emit(BIT_XOR_ASSIGN, start, 2);
			}
			return self.emit(BIT_XOR, start, 1);
		case '+':
			self.advance()!;
			switch (self.peek())
			{
				case '+':

					{
						if (self.peek(1) == '+')
						{
							if (self.peek(2) == '=')
							{
								self.advance(3)!;
								return self.emit(CT_CONCAT_ASSIGN, start, 4);
							}
							self.advance(2)!;
							return self.emit(CT_CONCAT_OP, start, 3);
						}
						self.advance()!;
						return self.emit(PLUSPLUS, start, 2);
					}
				case '=':
					self.advance()!;
					return self.emit(PLUS_ASSIGN, start, 2);
			}
			return self.emit(PLUS, start, 1);
		case '-':
			self.advance()!;
			switch (self.peek())
			{
				case '-': self.advance()!; return self.emit(MINUSMINUS, start, 2);
				case '=': self.advance()!; return self.emit(MINUS_ASSIGN, start, 2);
				case '>': self.advance()!; return self.emit(ARROW, start, 2);
			}
			return self.emit(MINUS, start, 1);
		case '~': self.advance()!; return self.emit(BIT_NOT, start, 1);
		case '(': self.advance()!; return self.emit(LPAREN, start, 1);
		case ')': self.advance()!; return self.emit(RPAREN, start, 1);
		case '{': self.advance()!; return self.emit(LBRACE, start, 1);
		case '}': self.advance()!; return self.emit(RBRACE, start, 1);
		case ';': self.advance()!; return self.emit(EOS, start, 1);
		case ',': self.advance()!; return self.emit(COMMA, start, 1);
		case '/':
			self.advance()!;
			if (self.peek() == '=')
			{
				self.advance()!;
				return self.emit(DIV_ASSIGN, start, 2);
			}
			return self.emit(DIV, start, 1);
		case '\'':
			return self.lex_char(start);
		case '"':
			return self.lex_string(start);
		case '`':
			return self.lex_raw_string(start);
		case '$':
			if (self.peek(1) == '$')
			{
				self.advance(2)!;
				return self.emit(BUILTIN, start, 2);
			}
			nextcase;
		case 'b':
			if (self.peek(1) == '6' && self.peek(2) == '4' && (self.peek(3) == '`' || self.peek(3) == '"'))
			{
				char quote_char = self.peek(3);
				self.advance(4)!;
				while (!self.eof())
				{
					if (self.peek() == quote_char)
					{
						self.advance()!; // Advance past the closing quote
						return self.emit(BYTES_LITERAL, start, self.index - start);
					}
					self.advance()!;
				}
				return INVALID~;
			}
			nextcase;
		case 'x':
			if (self.peek(1) == '"' || self.peek(1) == '\'' || self.peek(1) == '`')
			{
				self.advance()!;
				return self.lex_hex_array(start)!;
			}
			nextcase;
		case '@':
		case '#':
			return self.lex_identifier(start);
		default:
			if (is_digit(c)) return self.lex_number(start)!;
			if (is_ident(c)) return self.lex_identifier(start)!;
			return INVALID~;
	}
}

fn TokenKind Lexer.categorize_identifier(Lexer* self, String text)
{
	if (text.len == 0) return INVALID;

	char prefix     = text[0];
	String base;
	bool has_prefix = false;

	if (prefix == '@' && text.len == 1)
	{
		return AT;
	}

	if (prefix == '@' || prefix == '$' || prefix == '#')
	{
		base = text[1:text.len - 1];
		has_prefix = true;

		if (prefix == '$')
		{
			switch (base)
			{
				case "assert": return CT_ASSERT;
				case "case": return CT_CASE;
				case "default": return CT_DEFAULT;
				case "defined": return CT_DEFINED;
				case "echo": return CT_ECHO;
				case "expand": return CT_EXPAND;
				case "else": return CT_ELSE;
				case "endfor": return CT_ENDFOR;
				case "endforeach": return CT_ENDFOREACH;
				case "endif": return CT_ENDIF;
				case "endswitch": return CT_ENDSWITCH;
				case "error": return CT_ERROR;
				case "eval": return CT_EVAL;
				case "exec": return CT_EXEC;
				case "feature": return CT_FEATURE;
				case "for": return CT_FOR;
				case "foreach": return CT_FOREACH;
				case "if": return CT_IF;
				case "include": return CT_INCLUDE;
				case "reflect": return CT_REFLECT;
				case "stringify": return CT_STRINGIFY;
				case "switch": return CT_SWITCH;
				case "Typefrom": return CT_TYPEFROM;
				case "Typeof": return CT_TYPEOF;
				case "vaarg": return CT_VAARG;
				default: break;
			}
		}
	}
	else
	{
		base = text;
		TokenKind kind = lookup_keyword(base);
		if (kind != IDENT) return kind;
	}
	
	

	while (base.len > 0 && base[0] == '_')
	{
		base = base[1..];
	}

	bool is_type  = false;
	bool is_const = false;

	if (base.len > 0)
	{
		char first_char = base[0];
		if (first_char >= 'A' && first_char <= 'Z')
		{
			if (is_all_upper(base))
			{
				is_const = true;
			}
			else
			{
				is_type = true;
			}
		}
	}

	if (prefix == '@')
	{
		if (is_const) return AT_CONST_IDENT;
		if (is_type) return AT_TYPE_IDENT;
		return AT_IDENT;
	}
	if (prefix == '$')
	{
		if (is_const) return CT_CONST_IDENT;
		if (is_type) return CT_TYPE_IDENT;
		return CT_IDENT;
	}
	if (prefix == '#')
	{
		if (is_const) return HASH_CONST_IDENT;
		if (is_type) return HASH_TYPE_IDENT;
		return HASH_IDENT;
	}

	if (is_const) return CONST_IDENT;
	if (is_type) return TYPE_IDENT;
	return IDENT;
}

struct ContractLexer
{
	Lexer lexer;
	String description;
}

<*
 @require contract.len >= 4 : "Contract must contain at least 4 chars"
*>
fn void ContractLexer.init(&self, String contract)
{
	// Strip the decorators <* and *>
	String inner = contract[2:^4];
	plog::debug("ContractLexer - string = %s", inner);

	usz i              = 0;
	bool line_start    = true;
	usz first_at_index = inner.len;

	// Scan for the first '@' that starts a line
	while (i < inner.len)
	{
		char c = inner[i];

		if (c == '@' && line_start)
		{
			first_at_index = i;
			break;
		}

		if (c == '\n')
		{
			line_start = true;
		}
		else if (!char.is_blank(c))
		{
			line_start = false;
		}

		i++;
	}

	self.description = inner[0:first_at_index].trim();

	self.lexer = { .buffer = inner[first_at_index..], .index = 0 };
	plog::debug("ContractLexer - buffer = %s", self.lexer.buffer);
}

fn Token? ContractLexer.next(&self) => self.lexer.next();

fn void test_lexer() @test
{
	String src  = "module foo; \nfn void bar() {}";
	Lexer lexer = (Lexer) { .buffer = src, .index = 0, };

	while (!lexer.eof())
	{
		Token token = lexer.next()!!;
		io::printfn("token: %s", lexer.buffer[token.pos:token.len]);
	}
}
