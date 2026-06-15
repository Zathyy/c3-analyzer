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

	ctx.ws.registry.cleanup_section(ctx.section);

	mod.symbols.clear();

	foreach (section : mod.sections)
	{
		if (!section) continue;

		refresh_section_imports(ctx, section);

		foreach (node : section.nodes)
		{
			if (!node) continue;
		
			if (!node || !should_index(node)) continue;
			if (node.kind == FN_DECL)
			{
				FnDecl* func = node.as(FN_DECL);
				if (func.associated_type != null) continue;
			}

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

	foreach (section : mod.sections)
	{
		if (!section) continue;

		foreach (node : section.nodes)
		{
			if (!node || node.kind != FN_DECL) continue;
			
			FnDecl* func = node.as(FN_DECL);
			Node* type = func.associated_type;
			if (!type) continue;

			Cursor mc = { section, node };
			String? method_name = mc.spelling(tmem);
			if (catch method_name) continue;

			String target_type = expr::resolve_type_expr_spelling(ctx, type);
			if (target_type.len == 0) continue;

			plog::debug("Bound namespaced method: %s.%s", target_type, method_name);

			ctx.ws.registry.register_method(target_type, method_name, node);

			section.declared_methods.push({
				.type_name = target_type.copy(section.allocator),
				.method_name = method_name.copy(section.allocator)
			});
		}
	}
}

<*
 @param [&in] ctx
 @param [&in] section
*>
fn void refresh_section_imports(SemaContext* ctx, ModuleSection* section)
{
	section.resolved_imports.clear();

	foreach (node : section.nodes)
	{
		if (node.kind == IMPORT_DECL)
		{
			Cursor cursor = { section, node };
			String? path = cursor.spelling(tmem);
			if (catch path)
			{
				ctx.warn(node, "Failed to get import path");
				continue;
			}
			section.resolved_imports.push(path.copy(ctx.allocator));
		}

		//TODO: resolve alias module
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