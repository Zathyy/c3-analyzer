module lexer;

import std::ascii;
import std::io;

faultdef
	INVALID,
	EOF;

enum TokenKind : char
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
    SHR_OP,       // >> 
    SHL_OP,       // <<
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
    INTEGER,          // INTEGER 
    REAL,             // REAL 
    IDENT,            // IDENT 
    TYPE_IDENT,       // TYPE_IDEN,
    CONST_IDENT,      // CONST_IDENT 
    AT_IDENT,         // MACRO_IDENT 
    AT_TYPE_IDENT,    // MACRO_TYPE_IDENT 
    AT_CONST_IDENT,   // MACRO_CONST_IDENT 
    HASH_IDENT,       // HASH_IDEN,
    HASH_TYPE_IDENT,  // TYPE_IDENT 
    HASH_CONST_IDENT, // CONST_IDENT 
    CT_IDENT,         // CT_IDENT 
    CT_TYPE_IDENT,    // CT_TYPE_IDEN,
    CT_CONST_IDENT,   // CT_TYPE_IDEN,

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

struct Lexer 
{
	String buffer;
	usz index;
}

fn bool is_digit(char c) @inline => c >= '0' && c <= '9';
fn bool is_alpha(char c) @inline => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
fn bool is_ident(char c) @inline => is_alpha(c) || is_digit(c) || c == '_';
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
		case "vod":       return VOID;
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
    while (!self.eof())
    {
		char c = self.peek();
		if (is_ident(c))
		{
        	self.advance()!;
		}
		else
		{
			break;
		}
    }

    uint length = (uint)self.index - start_pos;
	if (length == 0) return INVALID~;

    String text = self.buffer[start_pos:length];

    TokenKind kind = self.categorize_identifier(text);

    return self.emit(kind, start_pos, length);
}

fn Token? Lexer.lex_number(Lexer* self, uint start_pos)
{
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

fn void? Lexer.advance(Lexer* self) @inline
{
	if (self.eof()) return EOF~;
    self.index++;
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
            if (self.peek() == '=') {
                self.advance()!;
                return self.emit(EQEQ, start, 2); 
            }
            return self.emit(EQ, start, 1);

        case '!':
            self.advance()!;
            if (self.peek() == '=') {
                self.advance()!;
                return self.emit(NOT_EQUAL, start, 2);
            }
            return self.emit(INVALID, start, 1);
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
				case '=': self.advance()!; return self.emit(GREATER_EQ, start, 2);
				case ']': self.advance()!; return self.emit(RVEC, start, 2);
			}
			return self.emit(GREATER, start, 1);
		case '<':
			self.advance()!;
			switch (self.peek())
			{
				case '=': self.advance()!; return self.emit(LESS_EQ, start, 2);
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
        case '(': self.advance()!; return self.emit(LPAREN, start, 1);
        case ')': self.advance()!; return self.emit(RPAREN, start, 1);
        case '{': self.advance()!; return self.emit(LBRACE, start, 1);
        case '}': self.advance()!; return self.emit(RBRACE, start, 1);
        case ';': self.advance()!; return self.emit(EOS, start, 1);
        case ',': self.advance()!; return self.emit(COMMA, start, 1);
        case '.': self.advance()!; return self.emit(DOT, start, 1);
        case '+': self.advance()!; return self.emit(PLUS, start, 1);
        case '-': self.advance()!; return self.emit(MINUS, start, 1);
        case '*': self.advance()!; return self.emit(ASTERISK, start, 1);
        case '/': self.advance()!; return self.emit(DIV, start, 1);

		case '"':
		case '`':
			return self.lex_string(start);
        default:
            if (is_digit(c)) return self.lex_number(start)!;
            if (is_ident(c)) return self.lex_identifier(start)!;
			return INVALID~;
    }
}

fn TokenKind Lexer.categorize_identifier(Lexer* self, String text)
{
    TokenKind kind = lookup_keyword(text);
    if (kind != TokenKind.IDENT) return kind;

    char first = text[0];

    if (first >= 'A' && first <= 'Z')
    {
        if (is_all_upper(text)) return TokenKind.CONST_IDENT;
        
        return TokenKind.TYPE_IDENT;
    }

    // Starts with a-z or _? (like my_var or _internal)
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