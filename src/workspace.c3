module c3_parser::workspace;

import c3_parser::common;
import string_pool;
import line_map;

import std::collections::map;
import std::collections::list;

import c3_parser::ast @norecurse;
import c3_parser::cursor;

faultdef	
	SYMBOL_NOT_FOUND,
	MODULE_NOT_FOUND;

struct ModuleSection
{
    String file_path;
	String source;
	LineMap line_map;
	uint start_node_idx;
    uint node_count;
	Node header_node;
}

struct Module
{
    String name;
	Ast ast;
    List{ ModuleSection* } sections;
	StringPool* strings;
}

struct Workspace
{
    HashMap{String, Module*} modules;
    StringPool strings;
	Allocator alloc;
}

fn void init(Workspace* self, Allocator alloc = tmem)
{
	self.alloc = alloc;
    self.strings.init(alloc);
    self.modules.init(alloc, 16);
}

fn Module* get_or_create_module(Workspace* self, String name)
{
	if (try existing = self.modules.get(name))
	{
		return existing;
	}

    Module* mod = mem::tnew(Module);
    mod.name = name;
    mod.sections.tinit(4);
	mod.strings = &self.strings;
    
    ast::init(&mod.ast, 100); 
    
    self.modules.set(name, mod);
    return mod;
}

fn ModuleSection* get_or_create_section(Module* mod, String file_path)
{
    // Check if the current last section matches this file and header
    if (try last = mod.sections.last())
    {
        if (last.file_path == file_path)
        {
            return last;
        }
    }

    ModuleSection* next_section = mem::tnew(ModuleSection);
    next_section.file_path = file_path;
    
    next_section.start_node_idx = (uint)mod.ast.len();
    next_section.node_count = 0; 
    
    mod.sections.push(next_section);
    return next_section;
}

fn Cursor? lookup(Workspace* self, String module_name, String symbol_name)
{
    Module* mod = self.modules.get(module_name)!;
    if (!mod) return MODULE_NOT_FOUND~;

    // Search the module's top-level declarations
    foreach (decl_handle : mod.ast.top_level_nodes)
    {
        Cursor c = { mod, (Node)decl_handle };
        if (cursor::spelling(&c)! == symbol_name) return c;
    }

    return SYMBOL_NOT_FOUND~;
}