module analyzer::sema::registry;

import std::collections::map;

import analyzer::core::ast;

alias MethodMap = HashMap{String, HashMap{String, Node*}};

<*
 -`methods`: Maps a type string (e.g., "int", "String") to a sub-map of its methods (Name -> AST Node)
   User defined types will be prefixd with module name
*>
struct Registry
{
	MethodMap methods;
	Allocator allocator;
}

fn void Registry.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.methods.init(allocator, 8);
}

fn void Registry.free(&self)
{
	self.methods.@each(; String type_name, HashMap{String, Node*} methods)
	{
		methods.free();
	};
	self.methods.free();
}

fn void Registry.cleanup_section(&self, ModuleSection* section)
{
    foreach (method : section.declared_methods)
    {
        self.remove_method(method.type_name, method.method_name);
		method.type_name.free(section.allocator);
		method.method_name.free(section.allocator);
    }
    
    section.declared_methods.clear();
}

fn void Registry.register_method(&self, String type_name, String method_name, Node* node)
{
	if (!self.methods.has_key(type_name))
	{
		HashMap{String, Node*} sub_map;
		sub_map.init(self.allocator, 4);
		self.methods[type_name] = sub_map;
	}

	self.methods[type_name][method_name] = node;
}

fn Node* Registry.find_method(&self, String type_name, String method_name)
{
	HashMap{String, Node*}*? sub_map = self.methods.get_ref(type_name);
	if (catch sub_map) return null;
	return sub_map.get(method_name) ?? null;
}

fn void Registry.remove_method(&self, String type_name, String method_name)
{    
    HashMap{String, Node*}*? method_map = self.methods.get_ref(type_name);
	if (catch method_map) return;
    method_map.remove(method_name);
    
    if (method_map.len() == 0)
    {
        method_map.free();
        self.methods.remove(type_name);
    }
}

fn HashMap{String, Node*}*? Registry.get_all_methods(&self, String type_name)
{
    HashMap{String, Node*}*? direct_map = self.methods.get_ref(type_name);
    if (try direct_map)
    {
        return direct_map;
    }

    String suffix = string::tformat("::%s", type_name);
    
    HashMap{String, Node*}*? matched_map = null;
    uint match_count = 0;

	self.methods.@each(; key, sub_map)
	{
		if (key.ends_with(suffix))
        {
            match_count++;
            matched_map = self.methods.get_ref(key);
        }
	};
	
    if (match_count == 1)
    {
        return matched_map;
    }
    
    return null;
}