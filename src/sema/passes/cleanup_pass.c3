module analyzer::sema @if($feature(SEMA));

import analyzer::core::plog;
import analyzer::core;
import analyzer::cursor;

import std::collections::list;

fn void run_cleanup_pass(SemaContext* ctx)
{
	Module* mod = ctx.section.parent_module;
	
	mod.symbols.clear();
	mod.registry.reset();
	mod.arena.reset();

	foreach (section : mod.sections)
	{
		section.resolved_imports.init(ctx.allocator, 4);
		section.scope = {};
		section.scope.children.init(ctx.allocator);
		section.scope.variables.init(ctx.allocator);
	}
}