module analyzer::sema::expr;

import analyzer::core;
import analyzer::cursor;

import std::collections::list;

<*
 @param [&in] ctx
 @param [&inout] type
*>
fn String resolve_type_expr_spelling(SemaContext* ctx, Node* type)
{
	Cursor cursor = { ctx.section, type };
	if (!type) return "";
	if (type.kind == ERROR || type.kind == MISSING) return "";

	String name_str = cursor.spelling(tmem) ?? "<not-found>";

	if (constants::is_primitive(name_str))
	{
		return name_str;
	}

	TypeExpr* type_expr = type.as(TYPE_EXPR);

	if (type_expr.unresolved.path != null)
	{
		Cursor path_cursor = { ctx.section, type_expr.unresolved.path };
		String path_str = path_cursor.spelling(tmem) ?? "";
		return string::tformat("%s::%s", path_str, name_str);
	}

	List{String} matching_modules = ctx.ws.lookup_symbol_in_section(ctx.section, name_str);

	if (matching_modules.len() == 1)
	{
		String matched_mod = matching_modules.get(0);
		return string::tformat("%s::%s", matched_mod, name_str);
	}
	else if (matching_modules.len() > 1)
	{
		ctx.error(
			type,
			"The struct '%s' is defined in multiple imported modules, please use explicit namespacing.",
			name_str
		);
		return "";
	}

	Module* current_mod = ctx.section.parent_module;
	return string::tformat("%s::%s", current_mod.name, name_str);
}
