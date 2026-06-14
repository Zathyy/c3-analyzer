module analyzer::core;

import std::collections::list;
import std::collections::maybe;
import std::collections::map;

struct SourceFile
{
	String file_path;
	String source;
	LineMap line_map;
	List{ModuleSection*} sections;
	Ast* ast;
	sz id;
}

struct ModuleSection
{
	SourceFile* source_file;
	Module* parent_module;
	NodeArray nodes;
	List{Diagnostic} diagnostics;
	HashMap{String, String} resolved_imports;
	sz id;
}

struct Module
{
	String name;
	List{ModuleSection*} sections;
	HashMap{String, Node*} symbols;
	sz id;
}

alias PathString = String;

