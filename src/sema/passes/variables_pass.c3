module analyzer::sema @if($feature(SEMA));

import analyzer::core::plog;
import analyzer::core;
import analyzer::cursor;

import std::collections::list;

struct SemaLocalContext @local
{
	SemaScope* current_scope;
	ModuleSection* section;
	Allocator arena;
}

fn void run_variable_pass(SemaContext* ctx)
{
	SemaModSection* section = ctx.section;
	SemaMod* mod = section.section.parent_module;

	if (!section || !mod) return;

	String source = section.source_file.source;

    section.scope.range = {
        .start = 0,
        .end = (int)source.len - 1,
    };

	SemaLocalContext build_ctx = {
		.current_scope = &section.scope,
		.section = section,
		.arena = &mod.arena
	};

	foreach (root_node : section.section.nodes)
	{
		if (!root_node) continue;
		
		build_ctx.current_scope = &section.scope;
		
		Cursor root_cursor = { .section = (ModuleSection*)section, .node = root_node };
		cursor::visit(root_cursor, {}, (CursorVisitor)&build_section_scopes_callback, &build_ctx);
	}
}

fn ChildVisitResult build_section_scopes_callback(Cursor cursor, Cursor parent, void* user_data)
{
	SemaLocalContext* ctx = (SemaLocalContext*)user_data;
	Node* node = cursor.node;
	if (!node) return CONTINUE;

	while (ctx.current_scope.parent && node.offset.start > ctx.current_scope.range.end)
	{
		ctx.current_scope = ctx.current_scope.parent;
	}

	switch (node.kind)
	{
		case COMPOUND_STMT:
		{
			SemaScope* sub_scope = alloc::new(ctx.arena, SemaScope);
			sub_scope.parent = ctx.current_scope;
			sub_scope.range = node.offset;
			
			sub_scope.children.init(ctx.arena, 4);
			sub_scope.variables.init(ctx.arena, 4);

			ctx.current_scope.children.push(sub_scope);
			ctx.current_scope = sub_scope;
			
			if (parent.node && parent.node.kind == FN_DECL)
			{
				FnDecl* func = parent.node.as(FN_DECL);
				foreach (param_node : func.params)
				{
					if (!param_node) continue;
					SemaVar param_entry = {
						.def = param_node,
						.lifetime = { 
							.start = param_node.offset.start, 
							.end = sub_scope.range.end 
						}
					};
					sub_scope.variables.push(param_entry);
				}
			}
			
			break;
		}

		case VAR_DECL:
		{
			if (parent.node && parent.node.kind == FN_DECL) break;
			SemaVar var_entry = {
				.def = node,
				.lifetime = { 
					.start = node.offset.start, 
					.end = ctx.current_scope.range.end 
				}
			};
			
			ctx.current_scope.variables.push(var_entry);
			break;
		}

		default:
			break;
	}

	return RECURSE;
}