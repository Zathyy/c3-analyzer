module c3_parser::common;

import c3_parser::ast @norecurse;

import std::collections::list;

const uint MAX_GENERICS = 16;
const uint MAX_ATTRIBUTES = 16;

typedef FileID = ushort;

struct SourceSpan 
{
	usz start;
	usz end;
	FileID file_id;
}

// TODO: what is valid state?
// since start might be 0
fn bool SourceSpan.is_valid(self) @inline 
{
	return self.start != 0 && self.end != 0;
}

fn SourceSpan SourceSpan.combine(self, SourceSpan b) 
{
	return { .start = self.start, .end = b.end, .file_id = self.file_id };
}

struct Position 
{
	usz line;
	usz column;
}

//TODO: what name? Path clashes with std::io::path
// so i went with CPath - CommonPath
struct CPath
{
	SourceSpan span;
	String name;
}

struct ModuleSection
{
    String file_path;
    Ast* ast;
}

struct Module
{
    String module_name;
    List{ ModuleSection* } sections;
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

struct TypeDescriptor 
{
    uint name;      // The StringPool handle
	uint ptr_count;
    Node array_size;   // AST Node for [expr]
    uint gen_count;
    Node[MAX_GENERICS] gen_args;
}