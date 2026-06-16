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
	List{String} resolved_imports;
	List{Method} declared_methods;
	List{Diagnostic} diagnostics;
	NodeArray nodes;
	SourceFile* source_file;
	Module* parent_module;
	Allocator allocator;
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

struct Method
{
	String type_name;
	String method_name;
}

fn void ModuleSection.free(&self)
{
	foreach (path : self.resolved_imports)
	{
		path.free(self.allocator);
	}

	self.resolved_imports.free();

	foreach (method : self.declared_methods)
    {
        method.type_name.free(self.allocator);
        method.method_name.free(self.allocator);
    }

    self.declared_methods.free();

	foreach (diag : self.diagnostics)
	{
		alloc::free(self.allocator, diag.message);
	}

	self.diagnostics.free();
}
