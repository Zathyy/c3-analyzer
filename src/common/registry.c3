module c3_parser::registry;

import c3_parser::common;
import c3_parser::ast;

import std::collections::map;
import std::core::builtin;

const usz REGISTRY_ALLOC_SIZE = 100;

struct Registry
{
    HashMap{TypeKey, Node} interned_types;
    HashMap{String, Node} type_definitions;
    HashMap{String, Node} global_definitions;
}

struct TypeKey 
{
    Node name;
    uint ptr_count;
    Node array_size; // expr
    uint gen_count;
    Node[common::MAX_GENERICS] gen_args;
}

fn uint TypeKey.hash(&self)
{
	uint seed = 0;

	seed = builtin::@generic_hash_core(seed, self.name);
	seed = builtin::@generic_hash_core(seed, self.ptr_count);
	seed = builtin::@generic_hash_core(seed, self.array_size);
	seed = builtin::@generic_hash_core(seed, self.gen_count);
	
	for (uint i = 0; i < self.gen_count; i++) 
    {
        seed = builtin::@generic_hash_core(seed, self.gen_args[i]);
    }

	return seed;
}

fn bool TypeKey.equals(self, TypeKey b) @operator(==)
{
    if (self.name != b.name)   return false;
    if (self.ptr_count != b.ptr_count)   return false;
    if (self.array_size != b.array_size) return false;
    if (self.gen_count != b.gen_count)   return false;

    for (uint i = 0; i < self.gen_count; i++) 
    {
        if (self.gen_args[i] != b.gen_args[i]) return false;
    }
    return true;
}

fn void init(Registry* self, Allocator alloc = tmem)
{
	self.interned_types.init(alloc, REGISTRY_ALLOC_SIZE);
}

fn void free(Registry* self)
{
	self.interned_types.free();
}

fn Node Registry.get_interned_type(Registry* self, TypeKey* key)
{
    if (self.interned_types.has_key(*key)) 
    {
        Node? node = self.interned_types.get(*key);
		if (try node)
		{
			return node;
		}
    }

    return ((Node)0);
}

fn void Registry.register_type_shape(Registry* self, TypeKey* key, Node node)
{
    self.interned_types.set(*key, node);
}