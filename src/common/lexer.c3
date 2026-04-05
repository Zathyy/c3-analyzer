module lexer;

import std::ascii;
import std::io;

faultdef
	INVALID,
	CONTRACT_NOT_CLOSED,
	INVALID_CONTRACT,
	EOF;

enum TokenKind : ushort
{
 	INVALID,     // Invalid

    // Operators
    AMP,          // & 
    BIT_OR,       // | 
    BIT_XOR,      // ^ 
    BIT_NOT,      // ~ 
    BANG,         // ! 
    PLUS,         // + 
    MINUS,        // -
    ASTERISK,         // *
    DIV,          // /
    MOD,          // %
    QUESTION,    // ? 
    QUESTQUEST,   // ?? 
    ELVIS,        // ?: 
    BANGBANG,     // !! 
    BUILTIN,      // $$ 
    RSHIFT,       // >> 
    LSHIFT,       // <<
    PLUSPLUS,     // ++ 
    MINUSMINUS,   // -- 
    CT_CONCAT_OP, // +++ 
    CT_TERNARY,   // ???

    // Assignment
    EQ,               // = 
    SHR_ASSIGN,       // >>= 
    SHL_ASSIGN,       // <<= 
    PLUS_ASSIGN,      // += 
    MINUS_ASSIGN,     // -= 
    MULT_ASSIGN,      // *=
    DIV_ASSIGN,       // /= 
    MOD_ASSIGN,       // %= 
    BIT_AND_ASSIGN,   // &=
    BIT_XOR_ASSIGN,   // ^= 
    BIT_OR_ASSIGN,    // |=
    CT_CONCAT_ASSIGN, // +++=

    // Comparison
    LESS,        // < 
    GREATER,     // > 
    AND,         // && 
    OR,          // || 
    LESS_EQ,     // <= 
    GREATER_EQ,  // >= 
    EQEQ,        // == 
    NOT_EQUAL,   // != 
    CT_AND_OP,   // &&&
    CT_OR_OP,    // |||

    // Punctuation
    EOS,       // ; 
    COLON,     // : 
    SCOPE,     // :: 
    COMMA,     // , 
    DOT,       // . 
    DOTDOT,    // .. 
    ELLIPSIS,  // ...

    // Structure
    LBRACE,    // { 
    RBRACE,    // } 
    LBRACKET,  // [
    RBRACKET,  // ] 
    LPAREN,    // ( 
    RPAREN,    // ) 
    ARROW,     // -> 
    IMPLIES,   // =>
    LVEC,      // [< 
    RVEC,      // >]

    // Comments and Contracts
    CONTRACT,      // <*
    LINE_COMMENT,  // // 
    BLOCK_COMMENT, // /*

    // Literals (Identifiers and Strings)
    STRING,           // STRING 
    CHAR_LITERAL,     // CHAR 
    BYTES,            // BYTES 
    INTEGER,          // 123 
    REAL,             // 0.00 
    IDENT,            // foo 
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
    VOID,     // void 
    BOOL,     // bool 
    CHAR,     // char 
    ICHAR,    // ichar 
    SHORT,    // short 
    USHORT,   // ushort 
    INT,      // int 
    UINT,     // uint 
    LONG,     // long 
    ULONG,    // ulong 
    INT128,   // int128
    UINT128,  // uint128 
    FLOAT,    // float 
    DOUBLE,   // double 
    FLOAT16,  // float16 
    BFLOAT16, // bfloat16 
    FLOAT128, // float128 
    IPTR,     // iptr 
    UPTR,     // uptr 
    ISZ,      // isz
    USZ,      // usz 
    FAULT,    // fault 
    ANY,      // any 
    TYPEID,   // typeid

    // Keywords
    ALIAS,      // alias 
    ASM,        // asm 
    ASSERT,     // assert 
    ATTRDEF,    // attrdef 
    BITSTRUCT,  // bitstruct 
    CONST,      // const 
    CONSTDEF,   // constdef 
    ENUM,       // enum
    FAULTDEF,   // faultdef 
    FN,       // fn 
    IMPORT,     // import 
    INTERFACE,  // interface 
    MACRO,      // macro 
    MODULE,     // module 
    STRUCT,     // struct 
    UNION,      // union
    TYPEDEF,    // typedef 
    BREAK,      // break 
    CASE,       // case 
    CATCH,      // catch 
    CONTINUE,   // continue 
    DEFAULT,    // default 
    DEFER,      // defer 
    DO,         // do 
    ELSE,       // else
    EXTERN,     // extern 
    FALSE,      // false 
    FOR,        // for 
    FOREACH,    // foreach 
    FOREACH_R,  // foreach_r 
    IF,         // if 
    INLINE,     // inline 
    LENGTHOF,   // lengthof 
    NEXTCASE,   // nextcase
    NULL,       // null 
    RETURN,     // return 
    STATIC,     // static 
    SWITCH,     // switch 
    TLOCAL,     // tlocal 
    TRUE,       // true 
    TRY,        // try 
    VAR,        // var 
    WHILE,      // while

    CT_ALIGNOF,   // $alignof, 
    CT_ASSERT,    // $assert, 
    CT_ASSIGNABLE,// $assignable, 
    CT_CASE,      // $case, 
    CT_DEFAULT,   // $default, 
    CT_DEFINED,   // $defined,
    CT_ECHO,      // $echo, 
    CT_ELSE,      // $else, 
    CT_ENDFOR,    // $endfor, 
    CT_ENDFOREACH,// $endforeach, 
    CT_ENDIF,     // $endif, 
    CT_ENDSWITCH, // $endswitch,
    CT_ERROR,     // $error, 
    CT_EVAL,      // $eval, 
    CT_EVALTYPE,  // $evaltype, 
    CT_EXEC,      // $exec, 
    CT_EXTNAMEOF, // $extnameof, 
    CT_FEATURE,   // $feature,
    CT_FOR,       // $for, 
    CT_FOREACH,   // $foreach, 
    CT_IF,        // $if, 
    CT_IS_CONST,  // $is_const, 
    CT_INCLUDE,   // $include, 
    CT_KINDOF,    // $kindof,
    CT_NAMEOF,    // $nameof, 
    CT_OFFSETOF,  // $offsetof, 
    CT_QNAMEOF,   // $qnameof, 
    CT_SIZEOF,    // $sizeof, 
    CT_STRINGIFY, // $stringify, 
    CT_SWITCH,    // $switch,
    CT_TYPEFROM,  // $typefrom, 
    CT_TYPEOF,    // $typeof, 
    CT_VAARG,     // $vaarg, 
    CT_VACONST,   // $vaconst, 
    CT_VACOUNT,   // $vacount, 
    CT_VAEXPR,    // $vaexpr,
    CT_VAREF,     // $varef, 
    CT_VATYPE,    // $vatype, 
    CT_VASPLAT,   // $vasplat, 

	AT_INLINE,
	AT_PURE,
	AT_NOINLINE,

    EOL, 
    EOF
}

struct Token
{
	TokenKind kind;
	uint pos;  // Offset in the source buffer
    uint len;  // Length of the lexeme
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
fn bool is_hex(char c) @inline => ascii::is_xdigit_m(c);

fn bool is_all_upper(String text) 
{
    bool has_alpha = false;
    for (usz i = 0; i < text.len; i++) 
    {
        char c = text[i];
        if (c >= 'a' && c <= 'z') return false;
        if (c >= 'A' && c <= 'Z') has_alpha = true;
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
    self.index += 2;
    while (self.index < self.buffer.len)
    {
        if (self.buffer[self.index] == '*' && self.peek_next() == '/')
        {
            self.index += 2;
            return;
        }
        self.advance()!;
    }
}

fn Token? Lexer.lex_string(Lexer* self, uint start)
{
    self.advance()!;
    
    while (self.index < self.buffer.len)
    {
        char c = self.buffer[self.index];
        
        if (c == '\\' && self.index + 1 < self.buffer.len)
        {
            self.index += 2; 
            continue;
        }
        
        if (c == '"')
        {
            self.advance()!;
            uint len = (uint)self.index - start;
            return (Token){ TokenKind.STRING, start, len };
        }
        
        if (c == '\n') 
        {
            break;
        }

        self.advance()!;
    }

    return (Token){ INVALID, start, (uint)self.index - start };
}

fn TokenKind lookup_keyword(String text)
{
    switch (text)
    {
		// Top-Level Explicit Keywords
		case "alias":     return ALIAS;
		case "attrdef":   return ATTRDEF;
		case "bitstruct": return BITSTRUCT;
		case "const":     return CONST;
		case "constdef":  return CONSTDEF;
		case "enum":      return ENUM;
		case "faultdef":  return FAULTDEF;
		case "fn":        return FN;
		case "import":    return IMPORT;
		case "interface": return INTERFACE;
		case "macro":     return MACRO;
		case "module":    return MODULE;
		case "typedef":   return TYPEDEF;
		case "struct":    return STRUCT;
		case "union":     return UNION;
		// Explicit Keywords
		case "any":       return ANY;
		case "asm":       return ASM;
		case "assert":    return ASSERT;
		case "break":     return BREAK;
		case "case":      return CASE;
		case "catch":     return CATCH;
		case "continue":  return CONTINUE;
		case "default":   return DEFAULT;
		case "defer":     return DEFER;
		case "do":        return DO;
		case "else":      return ELSE;
		case "false":     return FALSE;
		case "for":       return FOR;
		case "foreach":   return FOREACH;
		case "foreach_r": return FOREACH_R;
		case "if":        return IF;
		case "lengthof":  return LENGTHOF;
		case "nextcase":  return NEXTCASE;
		case "null":      return NULL;
		case "return":    return RETURN;
		case "static":    return STATIC;
		case "switch":    return SWITCH;
		case "true":      return TRUE;
		case "try":       return TRY;
		case "var":       return VAR;
		case "while":     return WHILE;
		case "extern":    return EXTERN;
		case "inline":    return INLINE;
		case "tlocal":    return TLOCAL;
		// Base
		case "void":       return VOID;
		case "bool":      return BOOL;
		case "char":      return CHAR;
		case "ichar":     return ICHAR;
		case "short":     return SHORT;
		case "ushort":    return USHORT;
		case "int":       return INT;
		case "uint":      return UINT;
		case "long":      return LONG;
		case "ulong":     return ULONG;
		case "int128":    return INT128;
		case "uint128":   return UINT128;
		case "iptr":      return IPTR;
		case "uptr":      return UPTR;
		case "isz":       return ISZ;
		case "usz":       return USZ;
		case "float":     return FLOAT;
		case "double":    return DOUBLE;
		case "float16":   return FLOAT16;
		case "bfloat16":  return BFLOAT16;
		case "float128":  return FLOAT128;
		case "fault":     return FAULT;
		case "typeid":    return TYPEID;
        default:       return TokenKind.IDENT;
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
	if (self.peek() == '0' && (self.peek_next() == 'x' || self.peek_next() == 'X'))
    {
        self.advance(2)!; // Skip '0x'
        
        while (!self.eof() && is_hex(self.peek()))
        {
            self.advance()!;
        }
        return self.emit(TokenKind.INTEGER, start_pos, (uint)self.index - start_pos);
    }	

    while (!self.eof() && is_digit(self.peek()))
    {
        self.advance()!;
    }

    if (!self.eof() && self.peek() == '.' && is_digit(self.peek_next()))
    {
        self.advance()!; // consume '.'
        while (!self.eof() && is_digit(self.peek()))
        {
            self.advance()!;
        }
        return self.emit(TokenKind.REAL, start_pos, (uint)self.index - start_pos);
    }

    return self.emit(TokenKind.INTEGER, start_pos, (uint)self.index - start_pos);
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
	if (self.eof()) return EOF~;
    self.index += len;
}

fn Token Lexer.emit(&self, TokenKind kind, uint pos, uint len) @inline
{
	return (Token){ 
		.kind = kind,
		.pos = pos,
		.len = len
	};
}

fn Token? Lexer.next(&self)
{
    self.skip_whitespace()!;

    if (self.eof()) 
    {
        return EOF~;
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
				case '|': self.advance()!; return self.emit(OR, start, 2);
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
			if (self.peek() == ':') {
				self.advance()!;
				return self.emit(SCOPE, start, 2);
			}
			return self.emit(COLON, start, 1);
		case '[':
			self.advance()!;
			if (self.peek() == '<') {
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
				case '>': self.advance()!; return self.emit(RSHIFT, start, 2);
				case '=': self.advance()!; return self.emit(GREATER_EQ, start, 2);
				case ']': self.advance()!; return self.emit(RVEC, start, 2);
			}
			return self.emit(GREATER, start, 1);
		case '<':
			self.advance()!;
			switch (self.peek())
			{
				case '<': self.advance()!; return self.emit(LSHIFT, start, 2);
				case '=': self.advance()!; return self.emit(LESS_EQ, start, 2);
				case '*': self.advance()!; return self.skip_contract(start);
			}	
			return self.emit(LESS, start, 1);
		case '&':
			self.advance()!;
			if (self.peek() == '&')
			{
				self.advance()!;
				return self.emit(AND, start, 2);
			}
			return self.emit(AMP, start, 1);
        case '*':
			self.advance()!; 
			return self.emit(ASTERISK, start, 1);
		case '?':
			self.advance()!;
			switch (self.peek())
			{
				case '?': self.advance()!; return self.emit(QUESTQUEST, start, 2);
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
		case '~': self.advance()!; return self.emit(BIT_NOT, start, 1);
        case '(': self.advance()!; return self.emit(LPAREN, start, 1);
        case ')': self.advance()!; return self.emit(RPAREN, start, 1);
        case '{': self.advance()!; return self.emit(LBRACE, start, 1);
        case '}': self.advance()!; return self.emit(RBRACE, start, 1);
        case ';': self.advance()!; return self.emit(EOS, start, 1);
        case ',': self.advance()!; return self.emit(COMMA, start, 1);
        case '+': self.advance()!; return self.emit(PLUS, start, 1);
        case '-': self.advance()!; return self.emit(MINUS, start, 1);
        case '/': self.advance()!; return self.emit(DIV, start, 1);
		case '"':
		case '`':
			return self.lex_string(start);
		case '$':
			if (self.peek(1) == '$')
			{
				self.advance(2)!;
				return self.emit(BUILTIN, start, 2);
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
    if (text.len == 0) return TokenKind.INVALID;

    char prefix = text[0];
    String base;
    bool has_prefix = false;

    if (prefix == '@' || prefix == '$' || prefix == '#')
    {
        base = text[1 : text.len - 1];
        has_prefix = true;

        if (prefix == '$')
        {
			switch (base)
			{
				case "alignof": return CT_ALIGNOF;    
				case "assert": return CT_ASSERT; 
				case "assignable": return CT_ASSIGNABLE; 
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
				case "evaltype": return CT_EVALTYPE; 
				case "exec": return CT_EXEC; 
				case "extnameof": return CT_EXTNAMEOF; 
				case "feature": return CT_FEATURE; 
				case "for": return CT_FOR; 
				case "foreach": return CT_FOREACH; 
				case "if": return CT_IF; 
				case "is_const": return CT_IS_CONST; 
				case "include": return CT_INCLUDE; 
				case "kindof": return CT_KINDOF; 
				case "nameof": return CT_NAMEOF; 
				case "offsetof": return CT_OFFSETOF; 
				case "qnameof": return CT_QNAMEOF; 
				case "sizeof": return CT_SIZEOF; 
				case "stringify": return CT_STRINGIFY; 
				case "switch": return CT_SWITCH; 
				case "typefrom": return CT_TYPEFROM; 
				case "typeof": return CT_TYPEOF; 
				case "vaarg": return CT_VAARG; 
				case "vaconst": return CT_VACONST; 
				case "vacount": return CT_VACOUNT; 
				case "vaexpr": return CT_VAEXPR; 
				case "varef": return CT_VAREF; 
				case "vasplat": return CT_VASPLAT; 
				case "vatype": return CT_VATYPE;
				default: break;
			}
        }
    }	
    else
    {
        base = text;
        TokenKind kind = lookup_keyword(base);
        if (kind != TokenKind.IDENT) return kind;
    }

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
        if (is_const) return TokenKind.AT_CONST_IDENT;
        if (is_type)  return TokenKind.AT_TYPE_IDENT;
        return TokenKind.AT_IDENT;
    }
    if (prefix == '$')
    {
        if (is_const) return TokenKind.CT_CONST_IDENT;
        if (is_type)  return TokenKind.CT_TYPE_IDENT;
        return TokenKind.CT_IDENT;
    }
    if (prefix == '#')
    {
        if (is_const) return TokenKind.HASH_CONST_IDENT;
        if (is_type)  return TokenKind.HASH_TYPE_IDENT;
        return TokenKind.HASH_IDENT;
    }

    if (is_const) return TokenKind.CONST_IDENT;
    if (is_type)  return TokenKind.TYPE_IDENT;
    return TokenKind.IDENT;
}

fn void test_lexer() @test 
{
	String src = "module foo; \nfn void bar() {}";
	Lexer lexer = (Lexer){
		.buffer = src,
		.index = 0,
	};

	while (!lexer.eof())
	{
		Token token = lexer.next()!!;
		io::printf("token: %s", lexer.buffer[token.pos:token.len]);
	}
}