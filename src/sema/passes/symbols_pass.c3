module analyzer::sema;

import analyzer::core::plog;
import analyzer::core;
import analyzer::cursor;

fn void run_symbols_pass(SemaContext* ctx)
{
	reindex_module(ctx);
}

<*
 @require ctx.section != null
*>
fn void reindex_module(SemaContext* ctx)
{
	Module* mod = ctx.section.parent_module;
	if (!mod) return;

	plog::debug("SEMA: reindex_module");

	mod.symbols.clear();

	foreach (section : mod.sections)
	{
		if (!section) continue;

		foreach (node : section.nodes)
		{
			if (!node) continue;
			if (!should_index(node)) continue;

			Cursor c = { section, node };
			String symbol_name = c.spelling(tmem) ?? "";


			plog::debug("symbol_name: %s", symbol_name);
			
			if (symbol_name.len == 0)
			{
				plog::debug("Failed to acquire spelling");
				continue;
			}

			Node* existing = mod.symbols.get(symbol_name) ?? null;
			if (existing != null)
			{
				plog::error("Redefinition of symbol '%s' in module '%s'", symbol_name, mod.name);
				ctx.error(node, "Redefinition of symbol '%s' in module '%s'", symbol_name, mod.name);
				ctx.info(existing, "Previous definition of '%s' is here", symbol_name);
				continue;
			}

			plog::debug("reindex_module: Set node: %s in module %s", node.kind.description, mod.name);
			mod.symbols.set(symbol_name, node);
		}
	}

	refresh_section_imports(ctx);
}

fn void refresh_section_imports(SemaContext* ctx)
{
	ctx.section.resolved_imports.clear();

	foreach (node : ctx.section.nodes)
	{
		if (node.kind == IMPORT_DECL)
		{
			ImportDecl* imp = node.as(IMPORT_DECL);
			
		}
	}
}

<*
 @require node != null
*>
fn bool should_index(Node* node)
{
	switch (node.kind)
	{
		case FN_DECL:
		case MACRO_DECL:
		case VAR_DECL:
		case STRUCT_DECL:
		case ENUM_DECL:
		case INTERFACE_DECL:
		case FAULTDEF_DECL:
		case TYPEDEF_DECL:
		case ALIAS_DECL:
			return true;
		default:
			return false;
	}
}