module parser;

import lexer;

enum OperatorKind
{
	OP_ERROR,
	OP_MULT,
	OP_SUB,
	OP_ADD,
	OP_DIV,
	OP_MOD,
	OP_SHR,
	OP_SHL,
	OP_BIT_OR,
	OP_BIT_XOR,
	OP_BIT_AND,
	OP_AND,
	OP_OR,
	OP_ELSE,
	OP_CT_AND,
	OP_CT_OR,
	OP_CT_CONCAT,
	OP_CT_CONCAT_ASSIGN,
	// Don't change the ordering for GT to EQ or things will break



	OP_GT,
	OP_GE,
	OP_LT,
	OP_LE,
	OP_NE,
	OP_EQ,
	// Vec comparisons



	OP_VEC_GT,
	OP_VEC_GE,
	OP_VEC_LT,
	OP_VEC_LE,
	OP_VEC_NE,
	OP_VEC_EQ,
	// Only "assign" BINOPS after this point



	OP_ASSIGN,
	OP_ADD_ASSIGN,
	OP_BIT_AND_ASSIGN,
	OP_BIT_OR_ASSIGN,
	OP_BIT_XOR_ASSIGN,
	OP_DIV_ASSIGN,
	OP_MOD_ASSIGN,
	OP_MULT_ASSIGN,
	OP_SHR_ASSIGN,
	OP_SHL_ASSIGN,
	OP_SUB_ASSIGN,
}

fn OperatorKind binaryop_from_token(TokenKind kind)
{
	switch (kind)
	{
		case ASTERISK: return OP_MULT;
		case DIV: return OP_DIV;
		case PLUS: return OP_ADD;
		case MINUS: return OP_SUB;
		case MOD: return OP_MOD;
		case LSHIFT: return OP_SHL;
		case RSHIFT: return OP_SHR;
		case AND: return OP_AND;
		case CT_AND_OP: return OP_CT_AND;
		case CT_OR_OP: return OP_CT_OR;
		case CT_CONCAT_OP: return OP_CT_CONCAT;
		case CT_CONCAT_ASSIGN: return OP_CT_CONCAT_ASSIGN;
		case QUESTQUEST: return OP_ELSE;
		case AMP: return OP_BIT_AND;
		case BIT_OR: return OP_BIT_OR;
		case BIT_XOR: return OP_BIT_XOR;
		case EQEQ: return OP_EQ;
		case NOT_EQUAL: return OP_NE;
		case LESS: return OP_LT;
		case LESS_EQ: return OP_LE;
		case GREATER: return OP_GT;
		case GREATER_EQ: return OP_GE;
		case EQ: return OP_ASSIGN;
		case MULT_ASSIGN: return OP_MULT_ASSIGN;
		case PLUS_ASSIGN: return OP_ADD_ASSIGN;
		case MINUS_ASSIGN: return OP_SUB_ASSIGN;
		case DIV_ASSIGN: return OP_DIV_ASSIGN;
		case MOD_ASSIGN: return OP_MOD_ASSIGN;
		case BIT_AND_ASSIGN: return OP_BIT_AND_ASSIGN;
		case BIT_OR_ASSIGN: return OP_BIT_OR_ASSIGN;
		case BIT_XOR_ASSIGN: return OP_BIT_XOR_ASSIGN;
		case RSHIFT_ASSIGN: return OP_SHR_ASSIGN;
		case LSHIFT_ASSIGN: return OP_SHL_ASSIGN;
		default:
			unreachable("unknown binaryop kind");
	}
}

enum VarDeclKind
{
	VAR_LOCAL,
	VAR_GLOBAL,
	VAR_FIELD,
	VAR_PARAM
}

enum UnaryOpKind
{
	UNARYOP_ERROR,
	UNARYOP_DEREF,
	UNARYOP_ADDR,
	UNARYOP_NEG,
	UNARYOP_PLUS,
	UNARYOP_BITNEG,
	UNARYOP_NOT,
	UNARYOP_INC,
	UNARYOP_DEC,
	UNARYOP_TADDR,
}

fn UnaryOpKind? unaryop_from_token(TokenKind kind)
{
	switch (kind)
	{
		case ASTERISK: return UNARYOP_DEREF;
		case AMP: return UNARYOP_ADDR;
		case AND: return UNARYOP_TADDR;
		case BIT_NOT: return UNARYOP_BITNEG;
		case BANG: return UNARYOP_NOT;
		case BANGBANG: return UNARYOP_NOT;
		case MINUS: return UNARYOP_NEG;
		case PLUS: return UNARYOP_PLUS;
		case PLUSPLUS: return UNARYOP_INC;
		case MINUSMINUS: return UNARYOP_DEC;
		default: return parser::UNEXPECTED_TOKEN~;
	}
}
