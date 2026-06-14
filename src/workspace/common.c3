module analyzer::workspace;
import analyzer::core;

import std::collections::map;
import std::collections::list;
import std::collections::pair;
import std::io;

faultdef
	INVALID_URI,
	NODE_NOT_FOUND, 
	SYMBOL_NOT_FOUND, 
	MODULE_NOT_FOUND
;

sz next_source_file_id = 1;
sz next_section_id     = 1;
sz next_module_id      = 1;

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

fn void Workspace.init(&self, WorkspaceOptions options = {}, Allocator allocator = mem)
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
			foreach (diag : section.diagnostics)
			{
				alloc::free(self.allocator, diag.message);
			}

			section.diagnostics.free();
			section.resolved_imports.free();
			alloc::free(self.allocator, section);
		}
		sf.sections.free();
		alloc::free(self.allocator, sf);
	};

	self.source_files.free();

	self.modules.@each(; name, mod)
	{
		mod.sections.free();
		mod.name.free(self.allocator);
		alloc::free(self.allocator, mod);
	};

	self.modules.free();
	self.ast_pool.free();
}