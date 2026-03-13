module c3::lexer;

import std::io, std::ascii;

faultdef INVALID_CHAR;

enum TokenType : ushort (String name)
{
    INVALID      { "Invalid" },

    // Operators
    AMP          { "&" }, 
    BIT_OR       { "|" }, 
    BIT_XOR      { "^" }, 
    BIT_NOT      { "~" }, 
    BANG         { "!" }, 
    PLUS         { "+" }, 
    MINUS        { "-" }, 
    STAR         { "*" },
    DIV          { "/" }, 
    MOD          { "%" },
    QUESTION     { "?" }, 
    QUESTQUEST   { "??" }, 
    ELVIS        { "?:" }, 
    BANGBANG     { "!!" }, 
    BUILTIN      { "$$" }, 
    SHR_OP       { ">>" }, 
    SHL_OP       { "<<" },
    PLUSPLUS     { "++" }, 
    MINUSMINUS   { "--" }, 
    CT_CONCAT_OP { "+++" }, 
    CT_TERNARY   { "???" },

    // Assignment
    EQ               { "=" }, 
    SHR_ASSIGN       { ">>=" }, 
    SHL_ASSIGN       { "<<=" }, 
    PLUS_ASSIGN      { "+=" }, 
    MINUS_ASSIGN     { "-=" }, 
    MULT_ASSIGN      { "*=" },
    DIV_ASSIGN       { "/=" }, 
    MOD_ASSIGN       { "%=" }, 
    BIT_AND_ASSIGN   { "&=" },
    BIT_XOR_ASSIGN   { "^=" }, 
    BIT_OR_ASSIGN    { "|=" },
    CT_CONCAT_ASSIGN { "+++=" },

    // Comparison
    LESS        { "<" }, 
    GREATER     { ">" }, 
    AND         { "&&" }, 
    OR          { "||" }, 
    LESS_EQ     { "<=" }, 
    GREATER_EQ  { ">=" }, 
    EQEQ        { "==" }, 
    NOT_EQUAL   { "!=" }, 
    CT_AND_OP   { "&&&" },
    CT_OR_OP    { "|||" },

    // Punctuation
    EOS       { ";" }, 
    COLON     { ":" }, 
    SCOPE     { "::" }, 
    COMMA     { "," }, 
    DOT       { "." }, 
    DOTDOT    { ".." }, 
    ELLIPSIS  { "..." },

    // Structure
    LBRACE    { "{" }, 
    RBRACE    { "}" }, 
    LBRACKET  { "[" },
    RBRACKET  { "]" }, 
    LPAREN    { "(" }, 
    RPAREN    { ")" }, 
    ARROW     { "->" }, 
    IMPLIES   { "=>" },
    LVEC      { "[<" }, 
    RVEC      { ">]" },

    // Comments and Contracts
    CONTRACT      { "<*" }, 
    LINE_COMMENT  { "//" }, 
    BLOCK_COMMENT { "/*" },

    // Literals (Identifiers and Strings)
    STRING           { "STRING" }, 
    CHAR_LITERAL     { "CHAR" }, 
    BYTES            { "BYTES" }, 
    INTEGER          { "INTEGER" }, 
    REAL             { "REAL" }, 
    IDENT            { "IDENT" }, 
    TYPE_IDENT       { "TYPE_IDENT" },
    CONST_IDENT      { "CONST_IDENT" }, 
    AT_IDENT         { "MACRO_IDENT" }, 
    AT_TYPE_IDENT    { "MACRO_TYPE_IDENT" }, 
    AT_CONST_IDENT   { "MACRO_CONST_IDENT" }, 
    HASH_IDENT       { "HASH_IDENT" },
    HASH_TYPE_IDENT  { "TYPE_IDENT" }, 
    HASH_CONST_IDENT { "CONST_IDENT" }, 
    CT_IDENT         { "CT_IDENT" }, 
    CT_TYPE_IDENT    { "CT_TYPE_IDENT" },
    CT_CONST_IDENT   { "CT_TYPE_IDENT" },

    // Base Types
    VOID     { "void" }, 
    BOOL     { "bool" }, 
    CHAR     { "char" }, 
    ICHAR    { "ichar" }, 
    SHORT    { "short" }, 
    USHORT   { "ushort" }, 
    INT      { "int" }, 
    UINT     { "uint" }, 
    LONG     { "long" }, 
    ULONG    { "ulong" }, 
    INT128   { "int128" },
    UINT128  { "uint128" }, 
    FLOAT    { "float" }, 
    DOUBLE   { "double" }, 
    FLOAT16  { "float16" }, 
    BFLOAT16 { "bfloat16" }, 
    FLOAT128 { "float128" }, 
    IPTR     { "iptr" }, 
    UPTR     { "uptr" }, 
    ISZ      { "isz" },
    USZ      { "usz" }, 
    FAULT    { "fault" }, 
    ANY      { "any" }, 
    TYPEID   { "typeid" },

    // Keywords
    ALIAS      { "alias" }, 
    ASM        { "asm" }, 
    ASSERT     { "assert" }, 
    ATTRDEF    { "attrdef" }, 
    BITSTRUCT  { "bitstruct" }, 
    CONST      { "const" }, 
    CONSTDEF   { "constdef" }, 
    ENUM       { "enum" },
    FAULTDEF   { "faultdef" }, 
    FUNC       { "fn" }, 
    IMPORT     { "import" }, 
    INTERFACE  { "interface" }, 
    MACRO      { "macro" }, 
    MODULE     { "module" }, 
    STRUCT     { "struct" }, 
    UNION      { "union" },
    TYPEDEF    { "typedef" }, 
    BREAK      { "break" }, 
    CASE       { "case" }, 
    CATCH      { "catch" }, 
    CONTINUE   { "continue" }, 
    DEFAULT    { "default" }, 
    DEFER      { "defer" }, 
    DO         { "do" }, 
    ELSE       { "else" },
    EXTERN     { "extern" }, 
    FALSE      { "false" }, 
    FOR        { "for" }, 
    FOREACH    { "foreach" }, 
    FOREACH_R  { "foreach_r" }, 
    IF         { "if" }, 
    INLINE     { "inline" }, 
    LENGTHOF   { "lengthof" }, 
    NEXTCASE   { "nextcase" },
    NULL       { "null" }, 
    RETURN     { "return" }, 
    STATIC     { "static" }, 
    SWITCH     { "switch" }, 
    TLOCAL     { "tlocal" }, 
    TRUE       { "true" }, 
    TRY        { "try" }, 
    VAR        { "var" }, 
    WHILE      { "while" },

    CT_ALIGNOF     { "$alignof" }, 
    CT_ASSERT      { "$assert" }, 
    CT_ASSIGNABLE  { "$assignable" }, 
    CT_CASE        { "$case" }, 
    CT_DEFAULT     { "$default" }, 
    CT_DEFINED     { "$defined" },
    CT_ECHO        { "$echo" }, 
    CT_ELSE        { "$else" }, 
    CT_ENDFOR      { "$endfor" }, 
    CT_ENDFOREACH  { "$endforeach" }, 
    CT_ENDIF       { "$endif" }, 
    CT_ENDSWITCH   { "$endswitch" },
    CT_ERROR       { "$error" }, 
    CT_EVAL        { "$eval" }, 
    CT_EVALTYPE    { "$evaltype" }, 
    CT_EXEC        { "$exec" }, 
    CT_EXTNAMEOF   { "$extnameof" }, 
    CT_FEATURE     { "$feature" },
    CT_FOR         { "$for" }, 
    CT_FOREACH     { "$foreach" }, 
    CT_IF          { "$if" }, 
    CT_IS_CONST    { "$is_const" }, 
    CT_INCLUDE     { "$include" }, 
    CT_KINDOF      { "$kindof" },
    CT_NAMEOF      { "$nameof" }, 
    CT_OFFSETOF    { "$offsetof" }, 
    CT_QNAMEOF     { "$qnameof" }, 
    CT_SIZEOF      { "$sizeof" }, 
    CT_STRINGIFY   { "$stringify" }, 
    CT_SWITCH      { "$switch" },
    CT_TYPEFROM    { "$typefrom" }, 
    CT_TYPEOF      { "$typeof" }, 
    CT_VAARG       { "$vaarg" }, 
    CT_VACONST     { "$vaconst" }, 
    CT_VACOUNT     { "$vacount" }, 
    CT_VAEXPR      { "$vaexpr" },
    CT_VAREF       { "$varef" }, 
    CT_VATYPE      { "$vatype" }, 
    CT_VASPLAT     { "$vasplat" }, 

	AT_INLINE    { "@inline" },
	AT_PURE      { "@pure"   },
	AT_NOINLINE  { "@noinline" },

    EOL { "EOL" }, 
    EOF { "EOF" },
}

struct Token (Printable)
{
	String    text;
	usz       offset;
	usz       len;
	usz       ln, col;
	usz       nl_before;
	TokenType type;
}

fn usz? Token.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	n += f.printf("<%s>", self.type.name)!;
	if (self.text.len)
	{
		@pool() {
			n += f.printf(" %s", self.text.tescape(true))!;
		};
	}
	return n;
}

struct Lexer
{
	String input;
	usz  pos;
	usz  ln, col;
	usz  token_start;
	usz  nl_before;
	bool emit_eol;
}

fn Lexer* Lexer.init(&self, String input, bool emit_eol = false)
{
	*self = { .input = input, .emit_eol = emit_eol, .pos = 0, .token_start = 0,
		.nl_before = 0, .ln = 1, .col = 1 };
	return self;
}

fn void Lexer.report_error(&self, String msg)
{
	io::eprintfn("LEXER ERROR at Ln: %d, Col: %d -- %s", self.ln, self.col, msg);
}

fn bool is_lf(char c) @inline => c == '\n';
fn bool is_ws(char c) @inline => @ok(" \t\r\n".index_of_char(c));
fn bool is_digit(char c) @inline => ascii::is_digit(c);
fn bool is_ident(char c) @inline => ascii::is_alnum(c) || c == '_';

fn char? Lexer.advance(&self)
{
	char c;

	if (self.at_end()) return io::EOF~;

	c = self.input[self.pos];
	self.pos++;

	self.col++;
	if (is_lf(c))
	{
		self.ln++;
		self.nl_before++;
		self.col = 1;
	}
	return c;
}

fn bool Lexer.at_end(&self) => self.pos >= self.input.len;

fn char Lexer.peek(&self, usz ahead = 0)
{
	if (self.pos + ahead >= self.input.len) return 0;
	return self.input[self.pos + ahead];
}

fn bool Lexer.must(&self, String s)
{
	usz n = s.len;
	if (self.pos+n-1 < self.input.len && self.input[self.pos:n] == s)
	{
		while (n--) (void)self.advance();
		return true;
	}
	return false;
}

fn String Lexer.lexeme(&self)
{
	usz len = self.pos - self.token_start;
	return self.input[self.token_start:len];
}

<*
 Emit token from lexer.
*>
fn Token Lexer.emit_token(&self, TokenType type)
{
	String lexeme = self.lexeme();
	Token tok = {
		.type      = type,
		.offset    = self.token_start,
		.len       = lexeme.len,
		.ln        = self.ln,
		.col       = self.col,
		.text      = lexeme,
		.nl_before = self.nl_before
	};
	self.nl_before = 0;
	return tok;
}

<*
 Lex the next token.
*>
fn Token? Lexer.next(&self)
{
	char c;
	TokenType type;

	self.scan_whitespace()!;

	self.token_start = self.pos;
	if (self.at_end()) return io::EOF~;

	switch (c = self.peek())
	{
		case ';': self.advance()!; return self.emit_token(EOS);
		case ',': self.advance()!; return self.emit_token(COMMA);
		case '~': self.advance()!; return self.emit_token(BIT_NOT);
		case '^':
			switch
			{
				case self.must("^="): type = BIT_XOR_ASSIGN;
				case self.must("^"):  type = BIT_XOR;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '*':
			switch
			{
				case self.must("*="): type = MULT_ASSIGN;
				case self.must("*"):  type = STAR;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '%':
			switch
			{
				case self.must("%="): type = MOD_ASSIGN;
				case self.must("%"):  type = MOD;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '.':
			switch
			{
				case self.must("..."): type = ELLIPSIS;
				case self.must(".."):  type = DOTDOT;
				case self.must("."):   type = DOT;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '+':
			switch
			{
				case self.must("+++="): type = CT_CONCAT_ASSIGN;
				case self.must("+++"):  type = CT_CONCAT_OP;
				case self.must("++"):   type = PLUSPLUS;
				case self.must("+="):   type = PLUS_ASSIGN;
				case self.must("+"):    type = PLUS;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '-':
			switch
			{
				case self.must("--"): type = MINUSMINUS;
				case self.must("-="): type = MINUS_ASSIGN;
				case self.must("->"): type = ARROW;
				case self.must("-"):  type = MINUS;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case ':':
			switch
			{
				case self.must("::"):  type = SCOPE;
				case self.must(":"):   type = COLON;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '!':
			switch
			{
				case self.must("!!"):  type = BANGBANG;
				case self.must("!="):  type = NOT_EQUAL;
				case self.must("!"):   type = BANG;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '?':
			switch
			{
				case self.must("???"): type = CT_TERNARY;
				case self.must("??"):  type = QUESTQUEST;
				case self.must("?:"):  type = ELVIS;
				case self.must("?"):   type = QUESTION;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '|':
			switch
			{
				case self.must("|||"): type = CT_OR_OP;
				case self.must("||"):  type = OR;
				case self.must("|="):  type = BIT_OR_ASSIGN;
				case self.must("|"):   type = BIT_OR;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '&':
			switch
			{
				case self.must("&&&"): type = CT_AND_OP;
				case self.must("&&"):  type = AND;
				case self.must("&="):  type = BIT_AND_ASSIGN;
				case self.must("&"):   type = AMP;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '=':
			switch
			{
				case self.must("=>"):  type = IMPLIES;
				case self.must("=="):  type = EQEQ;
				case self.must("="):   type = EQ;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);
		case '>':
			switch
			{
				case self.must(">>="): type = SHR_ASSIGN;
				case self.must(">>"):  type = SHR_OP;
				case self.must(">="):  type = GREATER_EQ;
				case self.must(">]"):  type = RVEC;
				case self.must(">"):   type = GREATER;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);

		case '[':
			switch
			{
				case self.must("[<"):  type = LVEC;
				case self.must("["):   type = LBRACKET;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);

		case ']': self.advance()!; return self.emit_token(RBRACKET);
		case '{': self.advance()!; return self.emit_token(LBRACE);
		case '}': self.advance()!; return self.emit_token(RBRACE);
		case '(': self.advance()!; return self.emit_token(LPAREN);
		case ')': self.advance()!; return self.emit_token(RPAREN);

		case '/':
			switch
			{
				case self.must("//"): self.scan_line_comment()!;  type = LINE_COMMENT;
				case self.must("/*"): self.scan_block_comment()!; type = BLOCK_COMMENT;
				case self.must("/="): type = DIV_ASSIGN;
				case self.must("/") : type = DIV;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);

		case '<':
			switch
			{
				case self.must("<*"):  self.scan_contract()!; type = CONTRACT;
				case self.must("<<="): type = SHL_ASSIGN;
				case self.must("<<"):  type = SHL_OP;
				case self.must("<="):  type = LESS_EQ;
				case self.must("<") :  type = LESS;
				default: return INVALID_CHAR~;
			}
			return self.emit_token(type);

		case '$':
			switch
			{
				case self.must("$$"): return self.emit_token(BUILTIN);
				case self.must("$"):  return self.lex_compile_time()!;
				default: return INVALID_CHAR~;
			}

		case '@':
		case '#':
			switch
			{
				case self.must("#!"):
					self.scan_line_comment()!;
					return self.emit_token(LINE_COMMENT);
				case self.must("#"):
				case self.must("@"):
					return self.lex_at_or_hash_ident()!;
				default: return INVALID_CHAR~;
			}

		case 'b':
		case 'x':
			switch
			{
				case self.must("b64\""): self.scan_until('"')!;
				case self.must("b64'"):  self.scan_until('\'')!;
				case self.must("b64`"):  self.scan_until('`')!;
				case self.must("x\""):   self.scan_until('"')!;
				case self.must("x'"):    self.scan_until('\'')!;
				case self.must("x`"):    self.scan_until('`')!;
				default: return self.lex_ident()!;
			}
			return self.emit_token(BYTES);

		case '\'':
			self.scan_string()!;
			return self.emit_token(CHAR_LITERAL);
		case '"':
		case '`':
			self.scan_string()!;
			return self.emit_token(STRING);

		case '\n':
			self.advance()!;
			return self.emit_token(EOL);

		default:
			if (is_digit(c)) return self.lex_number()!;
			if (is_ident(c)) return self.lex_ident()!;
			@pool() {
			self.report_error(string::tformat(
				"encountered invalid char: ""'%c'", c).tescape());
			};
			return INVALID_CHAR~;
	}
}

fn void? Lexer.scan_whitespace(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && is_ws(c))
	{
		if (self.emit_eol && c == '\n') break;
		self.advance()!;
	}
}

fn void? Lexer.scan_until(&self, char until)
{
	while (!self.at_end())
	{
		if (until == self.advance()!) return;
	}
}

fn void? Lexer.scan_string(&self)
{
	char quote, c;
	quote = self.peek();
	switch (quote)
	{
		case '"' :
		case '\'':
			self.advance()!; // Consume '"' or '\''
			while (!self.at_end() && (c = self.peek()) && c != quote)
			{
				if (c == '\\') self.advance()!; // Consume '\'
				self.advance()!;
			}
			self.advance()!; // Consume '"' or '\''
		case '`' :
			self.advance()!; // Consume '`'
			while(!self.at_end() && (c = self.peek()) && c != quote)
			{
				self.advance()!;
			}
			self.advance()!; // Consume '`'
	}
}

fn void? Lexer.scan_line_comment(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && (c != '\n' && c != '\r'))
	{
		self.advance()!;
	}
}

fn void? Lexer.scan_block_comment(&self)
{
	usz depth = 1;
	while (!self.at_end() && depth != 0)
	{
		switch
		{
			case self.must("/*"): depth++;
			case self.must("*/"): depth--;
			default: self.advance()!;
		}
	}
}

fn void? Lexer.scan_contract(&self)
{
	while (!self.at_end() && !self.must("*>")) self.advance()!;
}

fn Token? Lexer.lex_number(&self)
{
	char c, prev;
	int i = 0;
	while (!self.at_end() && (c = self.peek())
		&& (is_digit(c) || c == '-' || (i > 0 && (ascii::is_xdigit(c) || ascii::is_bdigit(c) || ascii::is_odigit(c)
			|| "+.eEpPbBxXoOuUlLifd_".contains_char(c))))
	)
	{
		if ("+-".contains_char(c) && !("eEpP".contains_char(prev))) break;
		if (c == '.' && c == self.peek(1)) break;
		self.advance()!;
		prev = c;
		i++;
	}

	return self.emit_token(number::classify(self.lexeme()));
}

fn Token? Lexer.lex_ident(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && is_ident(c))
	{
		self.advance()!;
	}

	String str = self.lexeme();
	switch (str)
	{
		// Top-Level Explicit Keywords
		case "alias":     return self.emit_token(ALIAS);
		case "attrdef":   return self.emit_token(ATTRDEF);
		case "bitstruct": return self.emit_token(BITSTRUCT);
		case "const":     return self.emit_token(CONST);
		case "constdef":  return self.emit_token(CONSTDEF);
		case "enum":      return self.emit_token(ENUM);
		case "faultdef":  return self.emit_token(FAULTDEF);
		case "fn":        return self.emit_token(FUNC);
		case "import":    return self.emit_token(IMPORT);
		case "interface": return self.emit_token(INTERFACE);
		case "macro":     return self.emit_token(MACRO);
		case "module":    return self.emit_token(MODULE);
		case "typedef":   return self.emit_token(TYPEDEF);
		case "struct":    return self.emit_token(STRUCT);
		case "union":     return self.emit_token(UNION);

		// Explicit Keywords
		case "any":       return self.emit_token(ANY);
		case "asm":       return self.emit_token(ASM);
		case "assert":    return self.emit_token(ASSERT);
		case "break":     return self.emit_token(BREAK);
		case "case":      return self.emit_token(CASE);
		case "catch":     return self.emit_token(CATCH);
		case "continue":  return self.emit_token(CONTINUE);
		case "default":   return self.emit_token(DEFAULT);
		case "defer":     return self.emit_token(DEFER);
		case "do":        return self.emit_token(DO);
		case "else":      return self.emit_token(ELSE);
		case "false":     return self.emit_token(FALSE);
		case "for":       return self.emit_token(FOR);
		case "foreach":   return self.emit_token(FOREACH);
		case "foreach_r": return self.emit_token(FOREACH_R);
		case "if":        return self.emit_token(IF);
		case "lengthof":  return self.emit_token(LENGTHOF);
		case "nextcase":  return self.emit_token(NEXTCASE);
		case "null":      return self.emit_token(NULL);
		case "return":    return self.emit_token(RETURN);
		case "static":    return self.emit_token(STATIC);
		case "switch":    return self.emit_token(SWITCH);
		case "true":      return self.emit_token(TRUE);
		case "try":       return self.emit_token(TRY);
		case "var":       return self.emit_token(VAR);
		case "while":     return self.emit_token(WHILE);

		case "extern":    return self.emit_token(EXTERN);
		case "inline":    return self.emit_token(INLINE);
		case "tlocal":    return self.emit_token(TLOCAL);

		// Base Types
		case "void":      return self.emit_token(VOID);
		case "bool":      return self.emit_token(BOOL);
		case "char":      return self.emit_token(CHAR);
		case "ichar":     return self.emit_token(ICHAR);
		case "short":     return self.emit_token(SHORT);
		case "ushort":    return self.emit_token(USHORT);
		case "int":       return self.emit_token(INT);
		case "uint":      return self.emit_token(UINT);
		case "long":      return self.emit_token(LONG);
		case "ulong":     return self.emit_token(ULONG);
		case "int128":    return self.emit_token(INT128);
		case "uint128":   return self.emit_token(UINT128);
		case "iptr":      return self.emit_token(IPTR);
		case "uptr":      return self.emit_token(UPTR);
		case "isz":       return self.emit_token(ISZ);
		case "usz":       return self.emit_token(USZ);
		case "float":     return self.emit_token(FLOAT);
		case "double":    return self.emit_token(DOUBLE);
		case "float16":   return self.emit_token(FLOAT16);
		case "bfloat16":  return self.emit_token(BFLOAT16);
		case "float128":  return self.emit_token(FLOAT128);
		case "fault":     return self.emit_token(FAULT);
		case "typeid":    return self.emit_token(TYPEID);

		default:
			return self.emit_token(ident::classify(str));
	}
}

fn Token? Lexer.lex_compile_time(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && is_ident(c))
	{
		self.advance()!;
	}

	String str = self.lexeme();
	switch (str)
	{
		// Compile time
		case "$alignof":    return self.emit_token(CT_ALIGNOF);
		case "$assert":     return self.emit_token(CT_ASSERT);
		case "$assignable": return self.emit_token(CT_ASSIGNABLE);
		case "$case":       return self.emit_token(CT_CASE);
		case "$default":    return self.emit_token(CT_DEFAULT);
		case "$defined":    return self.emit_token(CT_DEFINED);
		case "$echo":       return self.emit_token(CT_ECHO);
		case "$else":       return self.emit_token(CT_ELSE);
		case "$endfor":     return self.emit_token(CT_ENDFOR);
		case "$endforeach": return self.emit_token(CT_ENDFOREACH);
		case "$endif":      return self.emit_token(CT_ENDIF);
		case "$endswitch":  return self.emit_token(CT_ENDSWITCH);
		case "$error":      return self.emit_token(CT_ERROR);
		case "$eval":       return self.emit_token(CT_EVAL);
		case "$evaltype":   return self.emit_token(CT_EVALTYPE);
		case "$exec":       return self.emit_token(CT_EXEC);
		case "$extnameof":  return self.emit_token(CT_EXTNAMEOF);
		case "$feature":    return self.emit_token(CT_FEATURE);
		case "$for":        return self.emit_token(CT_FOR);
		case "$foreach":    return self.emit_token(CT_FOREACH);
		case "$if":         return self.emit_token(CT_IF);
		case "$is_const":   return self.emit_token(CT_IS_CONST);
		case "$include":    return self.emit_token(CT_INCLUDE);
		case "$kindof":     return self.emit_token(CT_KINDOF);
		case "$nameof":     return self.emit_token(CT_NAMEOF);
		case "$offsetof":   return self.emit_token(CT_OFFSETOF);
		case "$qnameof":    return self.emit_token(CT_QNAMEOF);
		case "$sizeof":     return self.emit_token(CT_SIZEOF);
		case "$stringify":  return self.emit_token(CT_STRINGIFY);
		case "$switch":     return self.emit_token(CT_SWITCH);
		case "$typefrom":   return self.emit_token(CT_TYPEFROM);
		case "$typeof":     return self.emit_token(CT_TYPEOF);
		case "$vaarg":      return self.emit_token(CT_VAARG);
		case "$vaconst":    return self.emit_token(CT_VACONST);
		case "$vacount":    return self.emit_token(CT_VACOUNT);
		case "$vaexpr":     return self.emit_token(CT_VAEXPR);
		case "$varef":      return self.emit_token(CT_VAREF);
		case "$vasplat":    return self.emit_token(CT_VASPLAT);
		case "$vatype":     return self.emit_token(CT_VATYPE);

		default:
			return self.emit_token(ident::classify(str));
	}
}

fn Token? Lexer.lex_at_or_hash_ident(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && is_ident(c))
	{
		self.advance()!;
	}

	String str = self.lexeme();
	switch (str)
	{
		case "@inline":   return self.emit_token(AT_INLINE);
		case "@pure":     return self.emit_token(AT_PURE);
		case "@noinline": return self.emit_token(AT_NOINLINE);
		default: return self.emit_token(ident::classify(str));
	}
}

struct ContractLexer
{
	Splitter splitter;
	Lexer    lexer;
	bool     lexer_init;
	<* intro is only available after the entire contract is lexed *>
	String   intro;
}

<*
 @require contract.len >= 4 : "Contract must contain at least 4 chars"
*>
fn ContractLexer* ContractLexer.init(&self, String contract)
{
	*self = {
		.splitter   = contract[2:^4].tokenize_all("\n", true),
		.lexer      = {},
		.lexer_init = false,
	};
	return self;
}

fn Token? ContractLexer.next(&self)
{
	if (!self.lexer_init)
	{
		usz pos;
		pos = self.splitter.current;
		while (try next_line = self.splitter.next())
		{
			if (next_line.trim().starts_with("@"))
			{
				self.intro = self.splitter.string[:pos];
				self.lexer.init(self.splitter.string[pos..], emit_eol: true);
				self.lexer_init = true;
				break;
			}
			pos = self.splitter.current;
		}
	}
	return self.lexer.next();
}

fn void test_contract_lexer() @test
{
	ContractLexer dl;
	dl.init(`<*
		 Check if a character is in a set.

		 @param c : "the character to check"


		 @param [in] set : "String containing the characters"
		 @pure
		 @return "True if a character is in the set"
		 *>`);

	TokenType[] want = {
		AT_IDENT, IDENT, COLON, STRING, EOL, EOL, EOL,
		AT_IDENT, LBRACKET, IDENT, RBRACKET, IDENT, COLON, STRING, EOL,
		AT_PURE, EOL,
		AT_IDENT, STRING, EOL,
	};

	while (try tok = dl.next() && want.len)
	{
		assert(tok.type == want[0], "Token type mismatch: got=%s, but want=%s", tok.type, want[0]);
		want = want[1..];
	}
	assert(dl.intro.trim() == "Check if a character is in a set.");
}

module c3::lexer::number;

enum NumberState : inline char (TokenType type) @private
{
	ERROR     { INVALID },
	INIT      { INVALID },
	INTEGER   { INTEGER },
	ZERO      { INTEGER },
	HEXINT    { INTEGER },
	OCTINT    { INTEGER },
	BININT    { INTEGER },
	INTSUFFIX { INTEGER },  // Integer suffix: ([iu](8|16|32|64|128)|[uU][lL]|[lL])
	REAL      { REAL },
	INTDEC    { REAL },     // Integer decimal: INT "." INT
	EDIGITS   { REAL },     // Exponent digits
	HEXDEC    { INVALID },  // Hexadecimal "decimal": HEXINT "." HEXINT
	EXPONENT  { INVALID },  // E-notation [eEpP]
	EXPSIGN   { INVALID },  // Exponent sign: + }, -
}

const NumberState[char.max+1][*] TRANSITIONS @private = {
	[NumberState.INIT] = {
		['1'..'9'] = INTEGER,
		['0']      = ZERO,
		['+']      = INIT,
		['-']      = INIT,
	},
	[NumberState.INTEGER] = {
		['0'..'9'] = INTEGER,
		['_']      = INTEGER,
		['e']      = EXPONENT,  ['E'] = EXPONENT,
		['d']      = REAL,      ['f'] = REAL,
		['i']      = INTSUFFIX,
		['u']      = INTSUFFIX, ['U'] = INTSUFFIX,
		['l']      = INTSUFFIX, ['L'] = INTSUFFIX,
		['.']      = INTDEC,
	},
	[NumberState.ZERO] = {
		['0'..'9'] = INTEGER,
		['_']      = INTEGER,
		['b']      = BININT,    ['B'] = BININT,
		['o']      = OCTINT,    ['O'] = OCTINT,
		['x']      = HEXINT,    ['X'] = HEXINT,
		['e']      = EXPONENT,  ['E'] = EXPONENT,
		['d']      = REAL,      ['f'] = REAL,
		['i']      = INTSUFFIX,
		['u']      = INTSUFFIX, ['U'] = INTSUFFIX,
		['l']      = INTSUFFIX, ['L'] = INTSUFFIX,
		['.']      = INTDEC,
	},
	[NumberState.HEXINT] = {
		['0'..'9'] = HEXINT,
		['a'..'f'] = HEXINT,
		['A'..'F'] = HEXINT,
		['_']      = HEXINT,
		['p']      = EXPONENT,  ['P'] = EXPONENT,
		['i']      = INTSUFFIX,
		['u']      = INTSUFFIX, ['U'] = INTSUFFIX,
		['l']      = INTSUFFIX, ['L'] = INTSUFFIX,
		['.']      = HEXDEC,
	},
	[NumberState.OCTINT] = {
		['0'..'7'] = OCTINT,
		['_']      = OCTINT,
		['i']      = INTSUFFIX,
		['u']      = INTSUFFIX, ['U'] = INTSUFFIX,
		['l']      = INTSUFFIX, ['L'] = INTSUFFIX,
	},
	[NumberState.BININT] = {
		['0'..'1'] = BININT,
		['_']      = BININT,
		['i']      = INTSUFFIX,
		['u']      = INTSUFFIX, ['U'] = INTSUFFIX,
		['l']      = INTSUFFIX, ['L'] = INTSUFFIX,
	},
	[NumberState.HEXDEC] = {
		['0'..'9'] = HEXDEC,
		['a'..'f'] = HEXDEC,
		['A'..'F'] = HEXDEC,
		['_']      = HEXDEC,
		['p']      = EXPONENT,  ['P'] = EXPONENT,
	},
	[NumberState.INTDEC] = {
		['0'..'9'] = INTDEC,
		['_']      = INTDEC,
		['e']      = EXPONENT, ['E'] = EXPONENT,
		['d']      = REAL,     ['f'] = REAL,
	},
	[NumberState.EXPONENT] = {
		['0'..'9'] = EDIGITS,
		['+']      = EXPSIGN,
		['-']      = EXPSIGN,
	},
	[NumberState.EDIGITS] = {
		['0'..'9'] = EDIGITS,
		['d']      = REAL, ['f'] = REAL,
	},
	[NumberState.EXPSIGN] = {
		['0'..'9'] = EDIGITS,
	},
	[NumberState.INTSUFFIX] = {
		['1'..'4'] = INTSUFFIX,
		['6']      = INTSUFFIX, ['8'] = INTSUFFIX,
		['l']      = INTSUFFIX, ['L'] = INTSUFFIX,
	},
};

fn TokenType classify(String s)
{
	NumberState state = INIT;
	foreach (c: s) state = TRANSITIONS[state][c];
	return state.type;
}

fn void test_number_classify() @test
{
	assert(classify("+")          ==  INVALID);
	assert(classify("-")          ==  INVALID);
	assert(classify("0")          ==  INTEGER);
	assert(classify("-1")         ==  INTEGER);
	assert(classify("123")        ==  INTEGER);
	assert(classify("123ul")      ==  INTEGER);
	assert(classify("123i32")     ==  INTEGER);
	assert(classify("0xdeadbeeF") ==  INTEGER);
	assert(classify("0xcafeUL")   ==  INTEGER);
	assert(classify("0b101UL")    ==  INTEGER);
	assert(classify("1xbeef")     ==  INVALID);
	assert(classify("0b1001.001") ==  INVALID);
	assert(classify("0b123")      ==  INVALID);
	assert(classify("0xbeeF.123p1") == REAL);
	assert(classify("0f")         ==   REAL);
	assert(classify("0.5f")       ==   REAL);
	assert(classify("123.0")      ==   REAL);
	assert(classify("123.0e-10")  ==   REAL);
	assert(classify("123f")       ==   REAL);
	assert(classify("123d")       ==   REAL);
}

module c3::lexer::ident;

enum IdentState : inline char (bool accept) @private {
	ERROR_STATE { false },
	INIT_STATE  { false },
	IDENT_STATE { true },
	TYPE_STATE  { true },
	CONST_STATE { true },
}

const IdentState[char.max+1][*] TRANSITIONS @private = {
	[IdentState.INIT_STATE] = {
		['A'..'Z'] = CONST_STATE,
		['a'..'z'] = IDENT_STATE,
		['_']      = INIT_STATE,
		['$']      = INIT_STATE,
		['#']      = INIT_STATE,
		['@']      = INIT_STATE,
	},
	[IdentState.IDENT_STATE] = {
		['A'..'Z'] = IDENT_STATE,
		['a'..'z'] = IDENT_STATE,
		['0'..'9'] = IDENT_STATE,
		['_']      = IDENT_STATE,
	},
	[IdentState.TYPE_STATE] = {
		['A'..'Z'] = TYPE_STATE,
		['a'..'z'] = TYPE_STATE,
		['0'..'9'] = TYPE_STATE,
		['_']      = TYPE_STATE,
	},
	[IdentState.CONST_STATE] = {
		['A'..'Z'] = CONST_STATE,
		['a'..'z'] = TYPE_STATE,
		['0'..'9'] = CONST_STATE,
		['_']      = CONST_STATE,
	},
};

fn TokenType classify(String s)
{
	// Verify order of TokenTypes
	assert(TokenType.IDENT + 1      == TokenType.TYPE_IDENT);
	assert(TokenType.IDENT + 2      == TokenType.CONST_IDENT);
	assert(TokenType.CT_IDENT + 1   == TokenType.CT_TYPE_IDENT);
	assert(TokenType.CT_IDENT + 2   == TokenType.CT_CONST_IDENT);
	assert(TokenType.AT_IDENT + 1   == TokenType.AT_TYPE_IDENT);
	assert(TokenType.AT_IDENT + 2   == TokenType.AT_CONST_IDENT);
	assert(TokenType.HASH_IDENT + 1 == TokenType.HASH_TYPE_IDENT);
	assert(TokenType.HASH_IDENT + 2 == TokenType.HASH_CONST_IDENT);

	IdentState state = IdentState.INIT_STATE;
	foreach (c: s) state = TRANSITIONS[state][c];
	if (state.accept)
	{
		char offset = state.ordinal - IdentState.IDENT_STATE.ordinal;
		switch (s[0])
		{
		case '$': return offset + TokenType.CT_IDENT;
		case '#': return offset + TokenType.HASH_IDENT;
		case '@': return offset + TokenType.AT_IDENT;
		default:  return offset + TokenType.IDENT;
		}
	}
	return INVALID;
}

fn void test_ident_classify() @test
{
	assert(classify("AABB") == CONST_IDENT);
	assert(classify("Aabb") == TYPE_IDENT);
	assert(classify("aabb") == IDENT);
	assert(classify("aaBb") == IDENT);
	assert(classify("@AABB") == AT_CONST_IDENT);
	assert(classify("@Aabb") == AT_TYPE_IDENT);
	assert(classify("@aabb") == AT_IDENT);
	assert(classify("#AABB") == HASH_CONST_IDENT);
	assert(classify("#Aabb") == HASH_TYPE_IDENT);
	assert(classify("#aabb") == HASH_IDENT);
	assert(classify("$AABB") == CT_CONST_IDENT);
	assert(classify("$Aabb") == CT_TYPE_IDENT);
	assert(classify("$aabb") == CT_IDENT);
}


