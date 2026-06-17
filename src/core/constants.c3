module analyzer::core::constants;

const String KW_AT_DEPRECATED = "@deprecated";
const String KW_AT_PURE       = "@pure";
const String KW_AT_ENSURE     = "@ensure";
const String KW_AT_REQUIRE    = "@require";
const String KW_AT_PARAM      = "@param";
const String KW_AT_RETURN     = "@return";

constdef Primitives : inline String
{
	PRIM_BOOL   = "bool",
	PRIM_VOID   = "void",
	PRIM_ANY    = "any",
	PRIM_TYPEID = "typeid",

	PRIM_ICHAR  = "ichar",
	PRIM_CHAR   = "char",
	PRIM_SHORT  = "short",
	PRIM_USHORT = "ushort",

	PRIM_INT   = "int",
	PRIM_UINT  = "uint",
	PRIM_LONG  = "long",
	PRIM_ULONG = "ulong",

	PRIM_INT128  = "int128",
	PRIM_UINT128 = "uint128",
	PRIM_IPTR    = "iptr",
	PRIM_UPTR    = "uptr",

	PRIM_SZ  = "sz",
	PRIM_USZ = "usz",

	PRIM_FLOAT  = "float",
	PRIM_DOUBLE = "double",
}

<*
*>
fn bool is_primitive(String name)
{
	foreach (member : Primitives::values)
	{
		if (member == name) return true;
	}

	return false;
}

constdef Keywords : inline String
{
	KEYW_CONSTDEF   = "constdef",
	KEYW_ALIAS      = "alias",
	KEYW_ASSERT     = "assert",
	KEYW_ASM        = "asm",
	KEYW_ATTRDEF    = "attrdef",
	KEYW_BITSTRUCT  = "bitstruct",
	KEYW_BREAK      = "break",
	KEYW_CASE       = "case",
	KEYW_CATCH      = "catch",
	KEYW_CONST      = "const",
	KEYW_CONTINUE   = "continue",
	KEYW_DEFAULT    = "default",
	KEYW_DEFER      = "defer",
	KEYW_DO         = "do",
	KEYW_ELSE       = "else",
	KEYW_ENUM       = "enum",
	KEYW_EXTERN     = "extern",
	KEYW_FALSE      = "false",
	KEYW_FAULTDEF   = "faultdef",
	KEYW_FOR        = "for",
	KEYW_FOREACH    = "foreach",
	KEYW_FOREACH_R  = "foreach_r",
	KEYW_FN         = "fn",
	KEYW_TLOCAL     = "tlocal",
	KEYW_IF         = "if",
	KEYW_INLINE     = "inline",
	KEYW_IMPORT     = "import",
	KEYW_LENGTHOF   = "lengthof",
	KEYW_MACRO      = "macro",
	KEYW_MODULE     = "module",
	KEYW_NEXTCASE   = "nextcase",
	KEYW_NULL       = "null",
	KEYW_INTERFACE  = "interface",
	KEYW_RETURN     = "return",
	KEYW_STATIC     = "static",
	KEYW_STRUCT     = "struct",
	KEYW_SWITCH     = "switch",
	KEYW_TRUE       = "true",
	KEYW_TRY        = "try",
	KEYW_TYPEDEF    = "typedef",
	KEYW_UNION      = "union",
	KEYW_VAR        = "var",
	KEYW_WHILE      = "while",
}

<*
*>
fn bool is_keyword(String name)
{
	foreach (member : Keywords::values)
	{
		if (member == name) return true;
	}

	return false;
}

fn bool is_valid_name(String name)
{
	if (is_primitive(name)) return false;
	if (is_keyword(name)) return false;
	return true;
}