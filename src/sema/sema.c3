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
	SemaScope scope;
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

struct SemaVar
{
	Node* def;
	ByteOffset lifetime;
}

<*
 - `parent`: can be null
 - `children`: list of all children defined in this scope
*>
struct SemaScope
{
	SemaScope* parent; // can be null
	ByteOffset range;
	List{SemaScope*} children; // a list of all children defined in this scope

	List{SemaVar} variables;
}

fn List{SemaVar} SemaModSection.get_active_vars(&self, int offset) => get_active_vars(offset, &self.scope);

fn List{SemaVar} get_active_vars(int offset, SemaScope* scope)
{
	List{SemaVar} active_vars; active_vars.tinit();
	SemaScope* current = scope;
	while LOOP: (true)
	{
		foreach (v : current.variables)
		{
			if (v.lifetime.start <= offset && v.lifetime.end >= offset)
			{
				active_vars.push(v);
			}
		}
		foreach (sub_scope : current.children) 
		{
			if (sub_scope.range.start <= offset && sub_scope.range.end >= offset) 
			{
				current = sub_scope;
				continue LOOP;
			}
		}
		break;
	}

	return active_vars;
}