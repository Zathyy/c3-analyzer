module utils::ast;

import std::io;
import std::encoding::json;
import std::collections::list;

import dessert;
import json;

import c3_parser::ast;
import lexer;
import string_pool;
import c3_parser::common;
import c3_parser::workspace;
import c3_parser::cursor;

import std::collections::maybe;

struct JsonNode
{
  uint id;
  String kind;

  String name       @DessertSer({ .skip_if_empty = true });
  String value      @DessertSer({ .skip_if_empty = true });

  String op         @DessertSer({ .skip_if_empty = true });
  String numeric   @DessertSer({ .skip_if_empty = true });

  String[] attributes @DessertSer({ .skip_if_empty = true });
  JsonNode[] children @DessertSer({ .skip_if_empty = true });
}

fn void? JsonNode.serialize(&self, Serializer serializer)
{
  ser::impl_serialize(self, serializer)!;
}

struct ModuleExport 
{
  String module_name;
  JsonNode[] nodes;
}

fn void? ModuleExport.serialize(&self, ser::Serializer serializer)
{
  ser::impl_serialize(self, serializer)!;
}

fn JsonNode build_json_node(Cursor c, Allocator allocator)
{ 
	NodeView v = c.section.source_file.ast.get_node(c.node);

	JsonNode dto;
	dto.id = (uint)c.node;
	dto.kind = v.kind.description;

	String raw = c.spelling() ?? "";

	switch (v.kind)
	{
	case BINARY_EXPR:
		dto.op = raw; 
	case INT_LITERAL:
	case FLOAT_LITERAL:
		dto.numeric = raw;
	case IDENT_EXPR:
	case FN_DECL:
	case STRUCT_DECL:
		dto.name = raw;

	default:
		dto.name = raw;
	}

	//TODO: Attributes

	List{JsonNode} children_list;
	children_list.tinit(); 
	cursor::visit_children(c, (CursorVisitor)&visit_json_node, &children_list);
	dto.children = mem::@tclone_slice(children_list.array_view());

	return dto;
}

fn ChildVisitResult visit_json_node(Cursor child, Cursor parent, void* data)
{
	List{JsonNode}* list_ptr = (List{JsonNode}*)data;
	list_ptr.push(build_json_node(child, tmem)); 
	return ChildVisitResult.CONTINUE;
}

fn void print_prefix(String prefix, bool is_last)
	{
	io::print(prefix);
	if (is_last) 
	{
	io::print("└─ ");
	}
	else        
	{
	io::print("├─ ");
	}
}

fn String make_child_prefix(String prefix, bool is_last)
{
	if (is_last) 
	{
	return prefix.tconcat("   ");
	}
	else         
	{
	return prefix.tconcat("│  ");
	}
	}

struct PrintContext
	{
	uint depth;
	String prefix;
	StringPool* strings;
}

fn ChildVisitResult printer_callback(Cursor c, Cursor p, void* data, bool is_last)
{
	PrintContext* ctx = (PrintContext*)data;

	print_prefix(ctx.prefix, is_last);

	NodeView v = c.section.source_file.ast.get_node(c.node);
	String name = c.spelling() ?? "";
	io::printfn("%s: %s : Idx = %s", v.kind.description, name, c.node);

	String old_prefix = ctx.prefix;

	ctx.prefix = make_child_prefix(old_prefix, is_last);
	switch (v.kind)
	{
	case INT_LITERAL:
	case FLOAT_LITERAL:
	case IDENT_EXPR:
		return ChildVisitResult.CONTINUE; 

	default:
		cursor::visit_children(c, (CursorVisitor)&printer_callback, ctx);
	}
	ctx.prefix = old_prefix;

	return ChildVisitResult.CONTINUE;
}

fn void dump_workspace(Workspace* ws)
{
	ws.modules.@each(; name, mod)
	{
		io::printfn("=== Module: %s ===", mod.name);
		io::printfn("=== Num module sections: %s ===", mod.sections.len());

		foreach (section : mod.sections) 
		{
		io::printfn("=== Module Section: %s ===", section.source_file.file_path);
		PrintContext ctx = { .depth = 0, .strings = section.source_file.strings };

		foreach (i, root_node : section.source_file.ast.top_level_nodes)
		{
			bool is_last = (i == section.source_file.ast.top_level_nodes.len() - 1);
			Cursor c = { section, (Node)root_node };

			log::debug("Node belongs to: (%s)", c.file_path());
			log::debug("Node belongs to module_decl: (%s)", c.module_decl());

			printer_callback(c, {null, {}}, &ctx, is_last);
		}
		}
	};
}

fn ChildVisitResult panic_on_invalid(Cursor c, Cursor p, void* data, bool is_last)
{
	NodeView v = c.section.source_file.ast.get_node(c.node);
	switch (v.kind)
	{
		case INVALID:
			abort("INVALID NODE: %s", p.source_text());

		default:
			cursor::visit_children(c, (CursorVisitor)&panic_on_invalid, data);
	}
	return CONTINUE;
}

fn void? dump_workspace_json(Workspace* ws, String base_path) => @pool()
{
	ws.source_files.@each(; path, file)
	{
		List{JsonNode} root_nodes;
		root_nodes.tinit();
		
		foreach (root_node : file.ast.top_level_nodes)
		{
			Cursor? c = ws.cursor_from_file(file, (Node)root_node);
			if (catch c) continue;
			root_nodes.push(build_json_node(c, tmem));
		}
		
		String mod_name = file.sections[0].parent_module.name;
		ModuleExport export_data = {
			.module_name = mod_name,
			.nodes = root_nodes.array_view()
		};
		
		JsonSerializer s = json::serializer();   
		JsonValue? json_val = ser::serialize(&s, export_data)!;
		
		String json_str = json_val.to_pretty_string()!;
		
		String file_name = mod_name.treplace("::", "_").tconcat(".json");
		String filename = base_path.tconcat(file_name);
		io::path::mkdir(base_path)!;
		
		io::file::save(filename, json_str)!;
	};
}




