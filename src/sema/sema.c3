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
	DynamicArenaAllocator arena;
	HashMap{String, List{SymbolEntry}} symbols;
	Registry registry;
}

fn void SemaMod.init(&self, String name, Allocator backing_allocator)
{
	Mod.init(self, name, backing_allocator);

	self.arena.init(backing_allocator, 4096);
	self.symbols.init(backing_allocator);
	self.registry.init(&self.arena);
}

fn void SemaMod.free(&self, Allocator allocator)
{
	Mod.free(self, allocator);

	self.symbols.free();
	self.registry.free();

	self.arena.free();
}

struct SemaModSection
{
	inline ModSection section;
	List{String} resolved_imports;
}

fn void SemaModSection.init(&self, Module* mod, SourceFile* sf, Allocator alloc)
{
	ModSection.init(self, mod, sf, alloc);

	self.resolved_imports.init(&mod.arena);
}

fn void SemaModSection.free(&self)
{
	ModSection.free(self);
}