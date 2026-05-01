module c3_parser::workspace;

import c3_parser::common;
import string_pool;
import line_map;

import std::collections::map;
import std::collections::list;

import c3_parser::ast @norecurse;
import c3_parser::cursor;

faultdef
	SYMBOL_NOT_FOUND, MODULE_NOT_FOUND
;

struct SourceFile
{
	String file_path;
	String source;
	LineMap line_map;
	List{ModuleSection*} sections;
	Ast ast;
	StringPool* strings;
}

struct ModuleSection
{
	SourceFile* source_file;
	Module* parent_module;
	uint start_node_idx;
	uint end_node_idx;
	Node header_node;
}

struct Module
{
	String name;
	List{ModuleSection*} sections;
	StringPool* strings;
}

alias PathString = String;

struct Workspace
{
	HashMap{PathString, SourceFile*} source_files;
	HashMap{String, Module*} modules;
	StringPool strings;
	Allocator alloc;
}

fn List{uint} ModuleSection.top_level_nodes(&self)
{
	List{uint} top_level_nodes;
	top_level_nodes.tinit(self.source_file.ast.top_level_nodes.len() / self.source_file.sections.len());
	foreach (node : self.source_file.ast.top_level_nodes)
	{
		if (node >= self.start_node_idx && node < self.end_node_idx)
		{
			top_level_nodes.push(node);
		}
	}

	return top_level_nodes;
}

fn void Workspace.init(&self, Allocator alloc = tmem)
{
	self.alloc = alloc;
	self.strings.init(alloc);
	self.modules.init(alloc, 16);
	self.source_files.init(alloc, 16);
}

// fn SourceFile* Workspace.get_or_create_source_file(&self, PathString path)
// {
// if (try existing = self.source_files.get(path))
// {
// return existing;
// }
// 
// SourceFile* sf = mem::tnew(SourceFile);
// sf.file_path = path;
// sf.sections.tinit(4);
// sf.strings = &self.strings;
// 
// ast::init(&sf.ast, 100);
// 
// self.source_files.set(path, sf);
// return sf;
// }

fn SourceFile* Workspace.reset_source_file(&self, PathString path)
{
	if (try existing = self.source_files.get(path))
	{
		foreach (section : existing.sections)
		{
			section.parent_module.sections.remove_using_test(
				fn (s, ctx) => (*s).source_file.file_path == *((String*)ctx),
				&path
			);
		}
		existing.sections.clear();
		return existing;
	}

	SourceFile* sf = mem::tnew(SourceFile);
	sf.file_path = path;
	sf.sections.tinit(4);
	sf.strings = &self.strings;

	ast::init(&sf.ast, 100);

	self.source_files.set(path, sf);
	return sf;
}

fn Module* Workspace.get_or_create_module(&self, String name)
{
	if (try existing = self.modules.get(name))
	{
		return existing;
	}

	Module* mod = mem::tnew(Module);
	mod.name = name;
	mod.sections.tinit(4);
	mod.strings = &self.strings;

	// ast::init(&mod.ast, 100);

	self.modules.set(name, mod);
	return mod;
}

fn ModuleSection* Workspace.get_or_create_section(&self, Module* mod, SourceFile* sf)
{
	// Check if the current last section matches this file and header
	if (try last = mod.sections.last())
	{
		if (last.source_file.file_path == sf.file_path)
		{
			return last;
		}
	}

	ModuleSection* next_section = mem::tnew(ModuleSection);
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

fn Cursor Workspace.find_at_location(&self, String file_path, Location loc)
{
	List{ModuleSection*} secs = self.find_section_by_path(file_path);
	if (secs.len() == 0) return { null, { } };

	foreach (sec : secs)
	{
		uint offset = sec.source_file.line_map.get_offset(sec.source_file.source, loc);
		Cursor candidate = cursor::find_at(sec, offset);
		if (candidate.node.is_valid())
		{
			return candidate;
		}
	}

	return { null, { } };
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

// 
// fn Cursor? Workspace.lookup(&self, String symbol_name, LookupOptions options)
// {
// 	Module* mod = self.modules.get(module_name)!;
// 	if (!mod) return MODULE_NOT_FOUND~;
//
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
//
// 	return SYMBOL_NOT_FOUND~;
// }

fn Cursor? Workspace.lookup(&self, String module_name, String symbol_name)
	=> self.lookup_in_module(module_name, symbol_name);

fn Cursor? Workspace.lookup_in_module(&self, String module_name, String symbol_name)
{
	Module* mod = self.modules.get(module_name)!;
	if (!mod) return MODULE_NOT_FOUND~;

	// Search the module's top-level declarations
	foreach (section : mod.sections)
	{
		foreach (decl_handle : section.source_file.ast.top_level_nodes)
		{
			if (decl_handle < section.start_node_idx || decl_handle >= section.end_node_idx) continue;
			Cursor c = { section, (Node)decl_handle };
			if (c.spelling()! == symbol_name) return c;
		}
	}

	return SYMBOL_NOT_FOUND~;
}

fn Cursor[]? Workspace.lookup_symbol(&self, String symbol_name) 
{
	List{Cursor} candidates;

	self.modules.@each(; mod_name, mod)
	{
			if (try c = self.lookup_in_module(mod_name, symbol_name))
			{
				candidates.push(c);
			}
	};

	return candidates.to_tarray();
}
