module parser::workspace;

import parser::cursor;

import line_map;

import std::collections::map;
import std::collections::list;
import std::collections::pair;

import parser::diagnostics @norecurse;

import parser::ast @norecurse;
import parser::ast::pool @norecurse;
import parser::plog;
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
	List{Diagnostic} diagnostics;
	HashMap{String, String} resolved_imports;
}

struct Module
{
	String name;
	List{ModuleSection*} sections;
	HashMap{String, Node*} symbols;
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