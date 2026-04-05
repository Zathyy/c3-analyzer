module c3_parser::common;

import c3_parser::ast @norecurse;

import std::collections::list;

const uint MAX_GENERICS = 16;
const uint MAX_ATTRIBUTES = 16;

typedef FileID = ushort;

struct Position 
{
	usz line;
	usz column;
}

enum AttributeKind 
{
	ALIGN,
	ALLOW_DEPRECATED,
	BENCHMARK,
	BIGENDIAN,
	BUILTIN,
	CALLCONV,
	CNAME,
	COMPACT,
	CONST,
	CONSTINIT,
	DEPRECATED,
	DYNAMIC,
	EXPORT,
	EXTERN,
	FINALIZER,
	FORMAT,
	IF,
	INLINE,
	INIT,
	JUMP,
	LINK,
	LITTLEENDIAN,
	LOCAL,
	MAYDISCARD,
	NAKED,
	NOALIAS,
	NODISCARD,
	NOINIT,
	NOINLINE,
	NOPADDING,
	NORECURSE,
	NORETURN,
	NOSANITIZE,
	NOSTRIP,
	OBFUSCATE,
	OPERATOR,
	OPERATOR_R,
	OPERATOR_S,
	OPTIONAL,
	OVERLAP,
	PACKED,
	PRIVATE,
	PUBLIC,
	PURE,
	REFLECT,
	SAFEINFER,
	SAFEMACRO,
	SIMD,
	SECTION,
	STRUCTLIKE,
	TAG,
	TEST,
	UNUSED,
	USED,
	WASM,
	WEAK,
	WINMAIN,
	NONE,
}

fn AttributeKind get_attribute_from_string(String str)
{
    switch (str)
    {
        case "@align":            return AttributeKind.ALIGN;
        case "@allow_deprecated": return AttributeKind.ALLOW_DEPRECATED;
        case "@benchmark":        return AttributeKind.BENCHMARK;
        case "@bigendian":        return AttributeKind.BIGENDIAN;
        case "@builtin":          return AttributeKind.BUILTIN;
        case "@callconv":         return AttributeKind.CALLCONV;
        case "@cname":            return AttributeKind.CNAME;
        case "@compact":          return AttributeKind.COMPACT;
        case "@const":            return AttributeKind.CONST;
        case "@constinit":        return AttributeKind.CONSTINIT;

        case "@deprecated":       return AttributeKind.DEPRECATED;
        case "@dynamic":          return AttributeKind.DYNAMIC;
        case "@export":           return AttributeKind.EXPORT;
        case "@extern":           return AttributeKind.EXTERN;
        case "@finalizer":        return AttributeKind.FINALIZER;
        case "@format":           return AttributeKind.FORMAT;

        case "@if":               return AttributeKind.IF;
        case "@inline":           return AttributeKind.INLINE;
        case "@init":             return AttributeKind.INIT;
        case "@jump":             return AttributeKind.JUMP;
        case "@link":             return AttributeKind.LINK;
        case "@littleendian":     return AttributeKind.LITTLEENDIAN;
        case "@local":            return AttributeKind.LOCAL;

        case "@maydiscard":       return AttributeKind.MAYDISCARD;
        case "@naked":            return AttributeKind.NAKED;
        case "@noalias":          return AttributeKind.NOALIAS;
        case "@nodiscard":        return AttributeKind.NODISCARD;
        case "@noinit":           return AttributeKind.NOINIT;
        case "@noinline":         return AttributeKind.NOINLINE;
        case "@nopadding":        return AttributeKind.NOPADDING;
        case "@norecurse":        return AttributeKind.NORECURSE;
        case "@noreturn":         return AttributeKind.NORETURN;
        case "@nosanitize":       return AttributeKind.NOSANITIZE;
        case "@nostrip":          return AttributeKind.NOSTRIP;

        case "@obfuscate":        return AttributeKind.OBFUSCATE;
        case "@operator":         return AttributeKind.OPERATOR;
        case "@operator_r":       return AttributeKind.OPERATOR_R;
        case "@operator_s":       return AttributeKind.OPERATOR_S;
        case "@optional":         return AttributeKind.OPTIONAL;
        case "@overlap":          return AttributeKind.OVERLAP;
        case "@packed":           return AttributeKind.PACKED;
        case "@private":          return AttributeKind.PRIVATE;
        case "@public":           return AttributeKind.PUBLIC;
        case "@pure":             return AttributeKind.PURE;

        case "@reflect":          return AttributeKind.REFLECT;
        case "@safeinfer":        return AttributeKind.SAFEINFER;
        case "@safemacro":        return AttributeKind.SAFEMACRO;
        case "@section":          return AttributeKind.SECTION;
        case "@simd":             return AttributeKind.SIMD;
        case "@structlike":       return AttributeKind.STRUCTLIKE;

        case "@tag":              return AttributeKind.TAG;
        case "@test":             return AttributeKind.TEST;
        case "@unused":           return AttributeKind.UNUSED;
        case "@used":             return AttributeKind.USED;
        case "@wasm":             return AttributeKind.WASM;
        case "@weak":             return AttributeKind.WEAK;
        case "@winmain":          return AttributeKind.WINMAIN;

        default:                  return AttributeKind.NONE;
    }
}

bitstruct TypeFlags : uint
{
    bool is_none;
    bool is_vector;
	bool is_comptime;
	bool is_optional;
}

bitstruct GlobalFlags : uint
{
    bool is_const   : 0;
    bool is_extern  : 1;
    bool is_thread_local : 2; 
}

enum DeferKind : uint 
{
    NORMAL,      // defer ...
    TRY,         // defer try ...
    CATCH,       // defer catch ...
    CATCH_VAR    // defer (catch var) ...
}

enum OverloadKind : uint 
{
	ELEMENT_SET,
	ELEMENT_AT,
	ELEMENT_REF,
}

struct TypeDescriptor 
{
    uint name;      // The StringPool handle
	uint ptr_count;
    Node array_size;   // AST Node for [expr]
	Node base_expr; // for compile time types expr
    uint gen_count;
    Node[MAX_GENERICS] gen_args;
}