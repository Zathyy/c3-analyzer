module c3_parser::ast::views;

import string_pool;
import c3_parser::common;
import lexer;

constdef AsmOffsetViewFields : inline uint 
{
	EXPR = 0,
}
typedef AsmOffsetView = inline View;

constdef AsmArgAddrViewFields : inline uint
{
	BASE = 0,
	INDEX,
	SCALE,
	DISP,
}
typedef AsmArgAddrView = inline View;

constdef AsmInstViewFields : inline uint 
{
	INSTRUCTION = 0,
	VARIANT,
	ARGS, 
}
typedef AsmInstView = inline View;

constdef AsmViewFields : inline uint
{
	FLAGS,
	STRING_EXPR,
	BLOCK, 
}
typedef AsmView = inline View;