module lexer;

import std::io;

faultdef
	INVALID, 
	UNEVEN_HEXADECIMAL,
	CONTRACT_NOT_CLOSED,
	INVALID_CONTRACT
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
	STRING,
	// STRING
	CHAR_LITERAL,
	// 'a' 'FO' 'BARS' '\u1232'
	BYTES, // Base64 or Hex
	INTEGER, // 123 0x23 0b10010 0o327
	REAL, // 0x23.2p-2a 43.23e23
	IDENT, // foo
	TYPE_IDENT,
	// Foo,
	CONST_IDENT,
	// FOO
	AT_IDENT,
	// @foo
	AT_TYPE_IDENT,
	// @Foo
	AT_CONST_IDENT,
	// @FOO
	HASH_IDENT,
	// #foo,
	HASH_TYPE_IDENT,
	// #Type
	HASH_CONST_IDENT,
	// #CONST_IDENT
	CT_IDENT,
	// $foo
	CT_TYPE_IDENT,
	// $Foo,
	CT_CONST_IDENT,
	// $FOO,

	// Base Types
	VOID,
	BOOL,
	CHAR,
	DOUBLE,
	FLOAT,
	FLOAT16,
	BFLOAT,
	INT128,
	ICHAR,
	INT,
	IPTR,
	SZ,
	LONG,
	SHORT,
	UINT128,
	UINT,
	ULONG,
	UPTR,
	USHORT,
	USZ,
	FLOAT128,
	ANY,
	FAULT,
	TYPEID,
	UNTYPEDLIST,

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

struct Token
{
	TokenKind kind;
	uint pos; // Offset in the source buffer
	uint len; // Length of the lexeme
}

bool is_in_contract = false;

struct Lexer
{
	String buffer;
	usz index;
}

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

fn char Lexer.peek(Lexer* self, usz ahead = 0) @inline
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
	if (self.index + 1 >= self.buffer.len) return '\0';
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
    uint depth = 1;

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

fn Token? Lexer.lex_char(Lexer* self, uint start)
{
	self.index++;

	while (self.index < self.buffer.len)
	{
		char c = self.buffer[self.index];

		if (c == '\'')
		{
			self.index++; 
			return (Token) { CHAR_LITERAL, start, (uint)self.index - start };
		}

		if (c == '\\')
		{
			self.index += 2;
			continue;
		}

		self.index++; 
	}

	return (Token) { INVALID, start, (uint)self.index - start };
}

fn Token? Lexer.lex_string(Lexer* self, uint start)
{
	self.index++;

	while (self.index < self.buffer.len)
	{
		char c = self.buffer[self.index];

		if (c == '"')
		{
			self.index++; 
			return (Token) { STRING, start, (uint)self.index - start };
		}

		if (c == '\\') 
		{
			self.index += 2;
			continue;
		}

		self.index++; 
	}

	return (Token) { INVALID, start, (uint)self.index - start };
}

fn Token? Lexer.lex_raw_string(Lexer* self, uint start)
{
    self.index++; // Skip the opening `

    while (self.index < self.buffer.len)
    {
        if (self.peek() == '`') // Only stop at a backtick
        {
            self.index++;
            return (Token) { STRING, start, (uint)self.index - start };
        }
        self.index++;
    }
    return (Token) { INVALID, start, (uint)self.index - start };
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
		case "any": return ANY;
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
		case "void": return VOID;
		case "bool": return BOOL;
		case "char": return CHAR;
		case "ichar": return ICHAR;
		case "short": return SHORT;
		case "ushort": return USHORT;
		case "int": return INT;
		case "uint": return UINT;
		case "long": return LONG;
		case "ulong": return ULONG;
		case "int128": return INT128;
		case "uint128": return UINT128;
		case "iptr": return IPTR;
		case "uptr": return UPTR;
		case "sz": return SZ;
		case "usz": return USZ;
		case "float": return FLOAT;
		case "double": return DOUBLE;
		case "float16": return FLOAT16;
		case "bfloat": return BFLOAT;
		case "float128": return FLOAT128;
		case "fault": return FAULT;
		case "typeid": return TYPEID;
		default: return IDENT;
	}
}

fn Token? Lexer.lex_identifier(Lexer* self, uint start_pos)
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

	uint length = (uint)self.index - start_pos;
	if (length == 0) return INVALID~;

	String text = self.buffer[start_pos:length];

	TokenKind kind = self.categorize_identifier(text);

	return self.emit(kind, start_pos, length);
}

fn Token? Lexer.lex_number(Lexer* self, uint start_pos)
{
	bool is_float = false;

	// Hex: 0x
	if (self.peek() == '0' && (ascii::to_lower(self.peek_next()) == 'x'))
	{
		self.advance(2)!;
		// Allow hex digits OR underscores
		while (!self.eof() && (ascii::is_xdigit(self.peek()) || self.peek() == '_'))
		{
			self.advance()!;
		}

		if (!self.eof() && self.peek() == '.' && self.peek_next() != '.') //&& ascii::is_xdigit(self.peek_next()))
		{
			is_float = true;
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
				is_float = true;
				self.advance()!;
				if (next == '-' || next == '+') self.advance()!;
				while (!self.eof() && (ascii::is_xdigit(self.peek()) || self.peek() == '_'))
				{
					self.advance()!;
				}
			}
		}
	} 
	// Binary: 0b
	else if (self.peek() == '0' && (ascii::to_lower(self.peek_next()) == 'b'))
	{
		self.advance(2)!;
		while (!self.eof() && (ascii::is_bdigit(self.peek()) || self.peek() == '_'))
		{
			self.advance()!;
		}
	} 
	// Octal: 0o
	else if (self.peek() == '0' && (ascii::to_lower(self.peek_next()) == 'o'))
	{
		self.advance(2)!;
		while (!self.eof() && (ascii::is_odigit(self.peek()) || self.peek() == '_'))
		{
			self.advance()!;
		}
	}
	else
	{
		// Standard Decimals
		while (!self.eof() && (ascii::is_digit(self.peek()) || self.peek() == '_'))
		{
			self.advance()!;
		}

		// Real/Float check
		if (!self.eof() && self.peek() == '.' && self.peek_next() != '.')// && ascii::is_digit(self.peek_next()))
		{
			is_float = true;
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
				is_float = true;
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

	TokenKind kind = is_float ? REAL : INTEGER;
	return self.emit(kind, start_pos, (uint)self.index - start_pos);
}

fn Token? Lexer.lex_hex_array(Lexer* self, uint start_pos)
{
    char start_quote = self.peek(); 
    self.advance()!;

    uint digit_count = 0;

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

		log::error("[Lexer]: Unexpected character '%c' in hex string at index %d", c, self.index);
        return INVALID~;
    }

    if (digit_count % 2 != 0)
    {
		log::error("[Lexer]: The hexadecimal string is not an even length");
        return UNEVEN_HEXADECIMAL~; 
    }

    return self.emit(BYTES, start_pos, (uint)self.index - start_pos);
}

fn Token? Lexer.skip_contract(Lexer* self, uint start_pos)
{
	while (!self.eof())
	{
		char c = self.peek();
		if (c == '*' && self.peek(1) == '>')
		{
			self.advance(2)!;
			return self.emit(CONTRACT, start_pos, (uint)self.index - start_pos);
		}
		self.advance()!;
	}

	return CONTRACT_NOT_CLOSED~;
}

fn void? Lexer.advance(Lexer* self, uint len = 1) @inline
{
	if (self.eof()) return io::EOF~;
	self.index += len;
}

fn Token Lexer.emit(&self, TokenKind kind, uint pos, uint len) @inline
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

	uint start = (uint)self.index;
	char c = self.peek();

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
			if (self.peek(1) == '6' && self.peek(2) == '4' && self.peek(3) == '`')
			{
				self.advance(3)!;
				return self.lex_raw_string(start)!;
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

	char prefix = text[0];
	String base;
	bool has_prefix = false;

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

	while (base[0] == '_') base = base[1..];

	bool is_type = false;
	bool is_const = false;

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
	log::debug("ContractLexer - string = %s", inner);

	usz i = 0;
	bool line_start = true;
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
	log::debug("ContractLexer - buffer = %s", self.lexer.buffer);
}

fn Token? ContractLexer.next(&self) => self.lexer.next();

fn void test_lexer() @test
{
	String src = "module foo; \nfn void bar() {}";
	Lexer lexer = (Lexer) { .buffer = src, .index = 0, };

	while (!lexer.eof())
	{
		Token token = lexer.next()!!;
		io::printfn("token: %s", lexer.buffer[token.pos:token.len]);
	}
}
