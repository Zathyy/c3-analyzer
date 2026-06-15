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
