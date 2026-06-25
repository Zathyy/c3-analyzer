module analyzer::workspace;

import analyzer::cursor;
import analyzer::parser;
import analyzer::sema;
import analyzer::core;

import std::collections::map;
import std::collections::list;
import std::collections::pair;
import std::io;

const ARENA_PAGE_SIZE = 4096;

struct FileInput
{
	PathString path;
	String uri;
	String source_text;
}

struct ParserCallbackData
{
	Workspace* ws;
	SourceFile* sf;
	HashMap{String, Module*}* affected_modules;
}

fn ModuleSection* on_parser_found_module(void* user_data, String module_name)
{
	ParserCallbackData* data = (ParserCallbackData*)user_data;

	Module* mod = data.ws.get_or_create_module(module_name);
	ModuleSection* sec = data.ws.get_or_create_section(mod, data.sf);
	data.affected_modules.set(mod.name, mod);
	return sec;
}

<*
 parse either from a file, or directly from a source string
 see `process_batch`
*>
fn ProcessResult? process(Workspace* self, Allocator allocator, FileInput input)
{
	FileInput[] slice = { input };
	return process_batch(self, allocator, slice);
}

<*
 @param allocator : "The allocator to use for the returned `ProccessResult`"
 @return "`ProcessResult` which needs to be freed"
*>
fn ProcessResult? process_batch(Workspace* self, Allocator allocator, FileInput[] inputs) => @pool()
{
	ProcessResult result;
	result.errored_sections.init(allocator, 4);
	result.has_errors = false;

	defer (catch err)
	{
		result.free();
	}

	HashMap{String, Module*} affected_modules;
	affected_modules.init(self.allocator, 8);
	defer affected_modules.free();

	HashMap{ulong, bool} reported_sections;
	reported_sections.init(self.allocator, 8);
	defer reported_sections.free();

	foreach (input : inputs)
	{
		if (!input.path && !input.source_text)
		{
			plog::error("No input specified.");
			continue;
		}

		if (!input.uri && !input.path)
		{
			plog::error("No uri set");
			return INVALID_URI~;
		}

		if (!input.uri) input.uri = input.path;

		ParseContext ctx;
		SourceFile* sf = self.reset_source_file(input.uri);
		ctx.ast = sf.ast;
		ctx.arena = &ctx.ast.arena;
		ctx.allocator = self.allocator;
		ctx.line_map = &sf.line_map;
		ctx.uri = input.uri;

		if (input.path)
		{
			ctx.src = (String)file::load(tmem, input.path)!;
		}
		else if (input.source_text)
		{
			ctx.src = input.source_text;
		}

		sf.source = ctx.src;

		ctx.line_map.build(ctx.src);

		ParserCallbackData callback_bundle = {
			.ws = self,
			.sf = sf,
			.affected_modules = &affected_modules
		};	

		ctx.on_new_module = &on_parser_found_module;
		ctx.user_data = (void*)&callback_bundle;

		(void)parser::parse(&ctx);

		foreach (section : sf.sections)
		{
			assert(section != null, "section null");

			if (section.parent_module != null)
			{
				affected_modules.set(section.parent_module.name, section.parent_module);
			}

			if (section.diagnostics.len() > 0 && !reported_sections.has_key(section.id))
			{
				result.errored_sections.push(section);
				reported_sections.set(section.id, true);
				result.has_errors = true;
			}
		}
	}

	if (!self.options.use_sema) return result;
	affected_modules.@each(; mod_name, mod)
	{
		foreach (section : mod.sections)
		{
			assert(section != null, "section null");

			SemaContext sema_ctx = {
				.section = section,
				.ws = self,
				.allocator = &mod.arena
			};

			sema::run_symbols_pass(&sema_ctx);

			if (section.diagnostics.len() > 0 && !reported_sections.has_key(section.id))
			{
				result.errored_sections.push(section);
				reported_sections.set(section.id, true);
				result.has_errors = true;
			}
		}
	};

	return result;
}

fn SourceFile* Workspace.reset_source_file(&self, PathString path)
{
	if (try existing = self.source_files.get(path))
	{
		self.ast_pool.release(existing.ast)!!;
		Module* mod;
		foreach (section : existing.sections)
		{
			if (!mod)
			{
				mod = section.parent_module;
			}
			mod.sections.remove_using_test(fn (s, ctx)
			{
				ModuleSection* target = *(ModuleSection**)ctx;
				return *s == target;
			}, &section);
		}
		self.invalidate_module(mod);
	
		foreach (section : existing.sections)
		{
			section.free();
			alloc::free(self.allocator, section);
		}

		existing.sections.clear();

		return existing;
	}

	SourceFile* sf = alloc::new(self.allocator, SourceFile);
	sf.id = core::next_source_file_id++;
	sf.file_path = path.copy(self.allocator);
	sf.sections.init(self.allocator, 4);
	sf.line_map.init(self.allocator);

	sf.ast = self.ast_pool.obtain();

	self.source_files.set(path, sf);
	return sf;
}

fn Module* Workspace.get_or_create_module(&self, String name)
{
	if (try existing = self.modules.get(name))
	{
		return existing;
	}

	Module* mod = alloc::new(self.allocator, Module);
	mod.init(name, self.allocator);
	self.modules.set(name, mod);
	return mod;
}

fn ModuleSection* Workspace.get_or_create_section(&self, Module* mod, SourceFile* sf)
{
	if (try last = mod.sections.last())
	{
		if (last.source_file.file_path == sf.file_path)
		{
			return last;
		}
	}

	ModuleSection* next_section = alloc::new(self.allocator, ModuleSection);
	next_section.init(mod, sf, self.allocator);
	mod.sections.push(next_section);
	sf.sections.push(next_section);

	return next_section;
}

<*
 Tries to find the ModuleSection associated to that file_path
  //TODO: should it just care about the full path?
          or should it also check if the base_name eq the file_path base_name?
*>
fn List{ModuleSection*} Workspace.find_section_by_path(&self, String file_path)
{
	List{ModuleSection*} sections;
	sections.tinit(1);

	foreach (mod : self.modules.value_iter())
	{
		foreach (section : mod.sections)
		{
			if (section.source_file.file_path == file_path) sections.push(section);
		}
	}

	return sections;
}

fn Cursor Workspace.find_top_level_statement_at_location(&self, String file_path, Location loc) @if($feature(SEMA))
{
    List{ModuleSection*} secs = self.find_section_by_path(file_path);
    if (secs.len() == 0) return {};

    foreach (sec : secs)
    {
        sz offset = sec.source_file.line_map.get_offset(sec.source_file.source, loc);
        
        foreach (global_decl : sec.source_file.ast.top_level_nodes)
        {
            if (!global_decl) continue;

            if ((int)offset >= global_decl.offset.start && (int)offset <= global_decl.offset.end)
            {
                return { .node = global_decl, .section = sec };
            }
        }
    }

    return {};
}

fn Cursor Workspace.find_leaf_at_location(&self, String file_path, Location loc) @if($feature(SEMA))
{
	List{ModuleSection*} secs = self.find_section_by_path(file_path);
	if (secs.len() == 0) return { };

	foreach (sec : secs)
	{
		sz offset = sec.source_file.line_map.get_offset(sec.source_file.source, loc);
		plog::debug("find_at_location - %s", offset);
		Cursor candidate = cursor::find_at(sec, (int)offset);
		if (candidate.node)
		{
			return candidate;
		}
	}

	return {};
}

fn List{SymbolEntry}*? Workspace.lookup(&self, String module_name, String symbol_name) @if($feature(SEMA)) @inline
{
	return self.lookup_in_module(module_name, symbol_name)!;
}

<*
 @param [in] module_name
 @param [in] symbol_name
*>
fn List{SymbolEntry}*? Workspace.lookup_in_module(&self, String module_name, String symbol_name) @if($feature(SEMA))
{
	if (!module_name || !symbol_name) return null;
	Module* mod = self.modules.get(module_name) ?? null;
	if (!mod) return null;

	return mod.symbols.get_ref(symbol_name) ?? null;
}

<*
 Global search across all tracked modules to find a type or symbol by its raw spelling.
 Returns the matching Node* or a fault if not found.
*>
fn List{SymbolEntry} Workspace.find_symbol_by_name(&self, String symbol_name) @if($feature(SEMA))
{
	List{SymbolEntry} all_candidates; all_candidates.tinit();

	foreach (mod : self.modules.value_iter())
	{
		List{SymbolEntry}* list = mod.symbols.get_ref(symbol_name) ?? null;
		if (list != null)
		{
			foreach (entry : *list) all_candidates.push(entry);
		}
	}
	return all_candidates;
}

<*
 @param [&in] section
 @require symbol_name.len > 0
*>
fn List{String} Workspace.lookup_symbol_in_section(&self, ModuleSection* section, String symbol_name) @if($feature(SEMA))
{
	List{String} matching_modules; matching_modules.tinit();
	if (!section) return matching_modules;

	foreach (target_module : section.resolved_imports)
	{
		if (!target_module) continue;
		List{SymbolEntry}* list = self.lookup_in_module(target_module, symbol_name) ?? null;

		if (list != null && list.len() > 0)
		{
			matching_modules.push(target_module);
		}
	}
	return matching_modules;
}