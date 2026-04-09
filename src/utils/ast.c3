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
    NodeView v = ast::get_node(&c.mod.ast, c.node);
    
    JsonNode dto;
    dto.id = (uint)c.node;
    dto.kind = v.kind.nameof;
    
    String raw = cursor::spelling(&c) ?? "";

    switch (v.kind)
    {
        case NodeKind.BINARY_EXPR:
            dto.op = raw; 
        case NodeKind.INT_LITERAL:
        case NodeKind.FLOAT_LITERAL:
            dto.numeric = raw;
        case NodeKind.IDENT_EXPR:
        case NodeKind.FN_DECL:
        case NodeKind.STRUCT_DECL:
            dto.name = raw;

        default:
            dto.name = raw;
    }
	
	dto.attributes = cursor::get_attribute_names(c, allocator);

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

    NodeView v = ast::get_node(&c.mod.ast, c.node);
    String name = cursor::spelling(&c) ?? "";
    io::printfn("%s: %s : Idx = %s", v.kind.nameof, name, c.node);

    String old_prefix = ctx.prefix;

    ctx.prefix = make_child_prefix(old_prefix, is_last);
    switch (v.kind)
	{
		case NodeKind.INT_LITERAL:
		case NodeKind.FLOAT_LITERAL:
		case NodeKind.IDENT_EXPR:
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
        
        PrintContext ctx = { .depth = 0, .strings = mod.strings };
        
        foreach (i, root_node : mod.ast.top_level_nodes)
        {
			bool is_last = (i == mod.ast.top_level_nodes.len() - 1);
            Cursor c = { mod, (Node)root_node };

			log::debug("Node belongs to: (%s)", cursor::file_path(&c));
			log::debug("Node belongs to module_decl: (%s)", cursor::module_decl(&c));

            printer_callback(c, {null, 0}, &ctx, is_last);
        }
    };
}

fn void? dump_workspace_json(Workspace* ws, String base_path) => @pool()
{
    ws.modules.@each(; name, mod)
    {
        List{JsonNode} root_nodes;
        root_nodes.tinit();

        foreach (root_node : mod.ast.top_level_nodes)
        {
            Cursor c = { mod, (Node)root_node };
            root_nodes.push(build_json_node(c, tmem));

			
			log::info(cursor::source_text(&c));
        }

        ModuleExport export_data = {
            .module_name = mod.name,
            .nodes = root_nodes.array_view()
        };

  		JsonSerializer s = json::serializer();   
		JsonValue? json_val = ser::serialize(&s, export_data)!;

		String json_str = json_val.to_pretty_string()!;

        String file_name = mod.name.treplace("::", "_").tconcat(".json");
        String filename = base_path.tconcat(file_name);
        io::path::mkdir(base_path)!;
        
        io::file::save(filename, json_str)!;
    };
}




