module analyzer::core;

import std::collections::list;
import std::collections::maybe;
import std::collections::map;

import analyzer::sema;

alias ModuleSection @if(!$feature(SEMA)) = ModSection;
alias ModuleSection @if($feature(SEMA)) = SemaModSection;

alias Module @if(!$feature(SEMA)) = Mod;
alias Module @if($feature(SEMA)) = SemaMod;

struct SourceFile
{
	String file_path;
	String source;
	LineMap line_map;
	List{ModuleSection*} sections;
	Ast* ast;
	sz id;
}

struct ModSection
{
	List{Diagnostic} diagnostics;
	NodeArray nodes;
	SourceFile* source_file;
	Module* parent_module;
	Allocator allocator;
	sz id;
}

struct Mod
{
	String name;
	List{ModuleSection*} sections;
	sz id;
}

alias PathString = String;

fn void ModuleSection.free(&self)
{
	foreach (diag : self.diagnostics)
	{
		alloc::free(self.allocator, diag.message);
	}

	self.diagnostics.free();
}
