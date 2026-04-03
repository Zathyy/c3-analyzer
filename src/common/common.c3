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

bitstruct TypeFlags : uint
{
    bool is_none    : 0;
    bool is_vector  : 1;
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

struct TypeDescriptor 
{
    uint name;      // The StringPool handle
	uint ptr_count;
    Node array_size;   // AST Node for [expr]
    uint gen_count;
    Node[MAX_GENERICS] gen_args;
}