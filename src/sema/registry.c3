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

fn void Registry.reset(&self)
{
	self.methods.clear();
}

fn void Registry.register_method(&self, String type_name, String method_name, Node* node, Node* condition)
{	
	MethodKey key;
	key.type_name = type_name.copy(self.allocator);
	key.method_name = method_name.copy(self.allocator);

	List{SymbolEntry}* list = self.methods.get_ref(key) ?? null;

	if (!list)
	{
		List{SymbolEntry} sub_list;
		sub_list.init(self.allocator, 4);
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