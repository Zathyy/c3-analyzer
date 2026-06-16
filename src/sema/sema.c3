module analyzer::sema @if($feature(SEMA));

import analyzer::core;

import analyzer::workspace @norecurse;
import analyzer::core::diagnostics;

import std::collections::map;
import std::collections::list;

struct SemaContext
{
	ModuleSection* section;
	Workspace* ws;
	Allocator allocator;
}

struct SemaMod
{
	inline Mod mod;
	HashMap{String, List{SymbolEntry}} symbols;
}

struct SemaModSection
{
	inline ModSection section;
	List{String} resolved_imports;
}
