module analyzer::sema;

import analyzer::core::plog;
import analyzer::workspace @norecurse;
import analyzer::core;
import analyzer::cursor;

fn void run_symbols_pass(SemaContext* ctx)
{
	reindex_module(ctx);
}

fn void reindex_module(SemaContext* ctx)
{
	Module* mod = ctx.section.parent_module;
	if (mod == null) return;

	mod.symbols.clear();

	foreach (section : mod.sections)
	{
		foreach (node : section.nodes)
		{
			if (!should_index(node.kind)) continue;

			Cursor c = { section, node };
			String symbol_name = c.spelling(tmem) ?? "";
			
			if (symbol_name.len == 0)
			{
				ctx.warn(node, "Failed to acquire spelling");
				continue;
			}

			Node* existing = mod.symbols.get(symbol_name) ?? null;
			if (existing != null)
			{
				ctx.error(node, "Redefinition of symbol '%s' in module '%s'", symbol_name, mod.name);
				continue;
			}

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

fn bool should_index(NodeKind kind)
{
	switch (kind)
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