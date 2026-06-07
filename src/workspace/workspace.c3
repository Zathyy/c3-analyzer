module parser::workspace;

import parser::cursor;
import line_map;

import std::collections::map;
import std::collections::list;
import std::collections::pair;

import parser::ast @norecurse;
import parser::ast::pool @norecurse;
import std::io;

faultdef
	NODE_NOT_FOUND, SYMBOL_NOT_FOUND, MODULE_NOT_FOUND
;

struct SourceFile
{
	String file_path;
	String source;
	LineMap line_map;
	List{ModuleSection*} sections;
	Ast* ast;
}

struct ModuleSection
{
	SourceFile* source_file;
	Module* parent_module;
	NodeArray nodes;
}

struct Module
{
	String name;
	List{ModuleSection*} sections;
}

alias PathString = String;

struct Workspace
{
	HashMap{PathString, SourceFile*} source_files;
	HashMap{String, Module*} modules;
	AstPool ast_pool;
	Allocator allocator;
}

fn void Workspace.init(&self, Allocator allocator = mem)
{
	self.allocator = allocator;
	self.modules.init(allocator, 16);
	self.source_files.init(allocator, 16);
	self.ast_pool.init(allocator);
}

fn void Workspace.free(&self)
{
	self.source_files.@each(; path, sf)
	{
		sf.ast.free();
		sf.line_map.free();
		foreach (section : sf.sections)
		{
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

fn SourceFile* Workspace.reset_source_file(&self, PathString path)
{
	if (try existing = self.source_files.get(path))
	{
		self.ast_pool.release(existing.ast)!!;
		foreach (section : existing.sections)
		{
			section.parent_module.sections.remove_using_test(fn (s, ctx)
			{
				Pair{String, Allocator}* args = (Pair{String, Allocator}*)ctx;
				if ((*s).source_file.file_path == args.first)
				{
					alloc::free(args.second, *s);
					return true;
				}
				return false;
			}, &&(Pair{String, Allocator}) { path, self.allocator });
		}
		existing.sections.clear();
		return existing;
	}

	SourceFile* sf = alloc::new(self.allocator, SourceFile);
	sf.file_path = path;
	sf.sections.init(self.allocator, 4);
	sf.line_map.init(self.allocator);

	sf.ast = self.ast_pool.obtain();

	self.source_files.set(path, sf);
	return sf;
}

fn Module* Workspace.get_or_create_module(&self, String name)
{
	if (try existing = self.modules.get(name))
	{
		return existing;
	}

	Module* mod = alloc::new(self.allocator, Module);
	mod.name = name.copy(self.allocator);
	mod.sections.init(self.allocator, 4);

	self.modules.set(name, mod);
	return mod;
}

fn ModuleSection* Workspace.get_or_create_section(&self, Module* mod, SourceFile* sf)
{
	if (try last = mod.sections.last())
	{
		if (last.source_file.file_path == sf.file_path)
		{
			return last;
		}
	}

	ModuleSection* next_section = alloc::new(self.allocator, ModuleSection);
	next_section.source_file = sf;
	next_section.parent_module = mod;
	mod.sections.push(next_section);
	sf.sections.push(next_section);

	return next_section;
}

<*
 Tries to find the ModuleSection associated to that file_path
  //TODO: should it just care about the full path?
          or should it also check if the base_name eq the file_path base_name?
*>
fn List{ModuleSection*} Workspace.find_section_by_path(&self, String file_path)
{
	List{ModuleSection*} sections;
	sections.tinit(1);

	foreach (mod : self.modules.value_iter())
	{
		foreach (section : mod.sections)
		{
			if (section.source_file.file_path == file_path) sections.push(section);
		}
	}

	return sections;
}

enum LookupTarget
{
	IDENT,
	MODULE
}

struct LookupOptions
{
	LookupTarget target;
	String name;
}

// ---
// fn Cursor? Workspace.lookup(&self, String symbol_name, LookupOptions options)
// {
// 	Module* mod = self.modules.get(module_name)!;
// 	if (!mod) return MODULE_NOT_FOUND~;
// ---
// 	// Search the module's top-level declarations
// 	foreach (section : mod.sections)
// 	{
// 		foreach (decl_handle : section.source_file.ast.top_level_nodes)
// 		{
// 			if (decl_handle < section.start_node_idx || decl_handle >= section.end_node_idx) continue;
// 			Cursor c = { section, (Node)decl_handle };
// 			if (c.spelling()! == symbol_name) return c;
// 		}
// 	}
// ---
// 	return SYMBOL_NOT_FOUND~;
// ---

fn Node*? Workspace.lookup(&self, String module_name, String symbol_name) @inline
{
	return self.lookup_in_module(module_name, symbol_name)!;
}

fn Node*? Workspace.lookup_in_module(&self, String module_name, String symbol_name) => @pool()
{
	Module* mod = self.modules.get(module_name)!;
	if (!mod) return MODULE_NOT_FOUND~;

	// Search the module's top-level declarations
	foreach (section : mod.sections)
	{
		foreach (node : section.source_file.ast.top_level_nodes)
		{
			Cursor c = { section, node };
			if (c.spelling(tmem)! == symbol_name) return node;
		}
	}

	return SYMBOL_NOT_FOUND~;
}
