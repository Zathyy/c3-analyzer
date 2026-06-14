module analyzer::sema;

import analyzer::core::plog;
import analyzer::workspace @norecurse;
import analyzer::core;

fn void run_symbols_pass(SemaContext* ctx)
{
	index_module_declarations(ctx);
}

fn void index_module_declarations(SemaContext* ctx)
{
	ctx.ws.modules.@each(; name, mod)
	{
		foreach (section : mod.sections)
		{
			foreach FOREACH: (node : section.nodes)
			{
				if (node.kind == STRUCT_DECL || node.kind == ENUM_DECL)
				{
					String type_name = "";
						
					if (type_name.len == 0) continue FOREACH;

					Node* existing_decl = mod.symbols.get(type_name) ?? null;
					if (existing_decl != null)
					{
						ctx.error(node, "Redefinition of type '%s' in module '%s'", type_name, mod.name);
						continue FOREACH;
					}

					mod.symbols.set(type_name, node);
				}
			}
		}
	};

	
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
			if (node.kind == STRUCT_DECL || node.kind == ENUM_DECL)
			{
				String type_name = "";
					
				if (type_name.len == 0) continue;

				Node* existing = mod.symbols.get(type_name) ?? null;
				if (existing != null)
				{
					ctx.error(node, "Redefinition of type '%s'", type_name);
					continue;
				}

				mod.symbols.set(type_name, node);
			}
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