module analyzer::workspace;
import analyzer::core;

import std::collections::map;
import std::collections::list;
import std::collections::pair;
import std::io;

import analyzer::sema::registry @norecurse;
import analyzer::sema @norecurse;

faultdef
	INVALID_URI,
	NODE_NOT_FOUND,
	SYMBOL_NOT_FOUND, 
	MODULE_NOT_FOUND;

<*
 - `use_sema`: if true, after parsing sema passes will run
*>
struct WorkspaceOptions
{
	bool use_sema;
}

struct ProcessResult
{
    List{ModuleSection*} errored_sections;
    bool has_errors;
}

fn void ProcessResult.free(&self)
{
	self.errored_sections.free();
}

struct Workspace
{
	HashMap{PathString, SourceFile*} source_files;
	HashMap{String, Module*} modules;
	AstPool ast_pool;
	WorkspaceOptions options;
	Allocator allocator;
}

fn void Workspace.init(&self, Allocator allocator = mem, WorkspaceOptions options = {})
{
	self.allocator = allocator;
	self.modules.init(allocator, 16);
	self.source_files.init(allocator, 16);
	self.ast_pool.init(allocator);
	self.options = options;
}

fn void Workspace.free(&self)
{
	self.source_files.@each(; path, sf)
	{
		sf.ast.free();
		sf.line_map.free();
		foreach (section : sf.sections)
		{ 
			section.free();
			alloc::free(self.allocator, section);
		}
		sf.sections.free();
		sf.file_path.free(self.allocator);
		sf.source.free(self.allocator);
		alloc::free(self.allocator, sf);
	};

	self.source_files.free();

	self.modules.@each(; name, mod) 
	{
		mod.free(self.allocator);
		alloc::free(self.allocator, mod);
	};

	self.modules.free();
	self.ast_pool.free();
}

fn void Workspace.invalidate_module(&self, Module* mod)
{
	mod.version++;
}