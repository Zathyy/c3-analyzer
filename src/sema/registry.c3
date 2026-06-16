module analyzer::sema::registry @if($feature(SEMA));

import std::collections::map;
import std::collections::list;

import analyzer::core::ast;

struct MethodKey 
{
    String type_name;
    String method_name;
}

fn uint MethodKey.hash(&self)
{
	uint seed;
	seed ^= (uint)self.type_name.hash();
	seed ^= (uint)self.method_name.hash();
	return seed;
}

fn bool MethodKey.eq(self, MethodKey other) @operator(==)
{
	return self.type_name == other.type_name
		&& self.method_name == other.method_name;
}

fn void MethodKey.free(&self, Allocator allocator)
{
	self.type_name.free(allocator);
	self.method_name.free(allocator);
}

// Type -> MethodName -> List of potential candidates
alias MethodMap = HashMap{MethodKey, List{SymbolEntry}};

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
	self.methods.init(allocator);
}

fn void Registry.free(&self)
{
	self.methods.@each(; MethodKey key, List{SymbolEntry} list) 
	{
		key.free(self.allocator);
        list.free(); 
    };
	self.methods.free();
}

fn void Registry.cleanup_section(&self, sz section_id)
{
	self.methods.@each(; MethodKey key, List{SymbolEntry} list)
	{
		for (sz i = list.len() - 1; i >= 0; i--)
		{
			if (list[i].section_id == section_id)
			{
				list.remove_at(i);
			}
		}

		if (list.len() == 0)
		{
			list.free();
			self.methods.remove(key);
		}
	};
}

fn void Registry.register_method(&self, String type_name, String method_name, Node* node, Node* condition)
{	
	MethodKey key = { .type_name = type_name, .method_name = method_name };

	List{SymbolEntry}* list = self.methods.get_ref(key) ?? null;

	if (!list)
	{
		List{SymbolEntry} sub_list;
		sub_list.init(self.allocator, 4);
		key.type_name.copy(self.allocator);
		key.method_name.copy(self.allocator);
		self.methods[key] = sub_list;
		list = self.methods.get_ref(key)!!;
	}

	list.push({ .node = node, .condition = condition });
}

fn List{SymbolEntry}*? Registry.get_candidates(&self, String type_name, String method_name)
{
	MethodKey key = { .type_name = type_name, .method_name = method_name };
	return self.methods.get_ref(key);
}

fn void Registry.remove_method(&self, String type_name, String method_name)
{    
	MethodKey key = { .type_name = type_name, .method_name = method_name };
	List{SymbolEntry}* list = self.methods.get_ref(key) ?? null;

	if (list) 
	{
		list.free();
		self.methods.remove(key);
	}
}

fn List{SymbolEntry}*? Registry.get_all_methods(&self, String type_name)
{
	self.methods.@each(; MethodKey key, List{SymbolEntry} list)
	{
		if (key.type_name == type_name) 
		{
			return self.methods.get_ref(key)!;
		}
	};
	return null;
}