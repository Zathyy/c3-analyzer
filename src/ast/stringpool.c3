module parser::ast;

import std::collections::list;
import std::collections::map;

struct StringPool 
{
	List{String} stable_strings;
	HashMap{String, sz} lookup_map;
}
alias StringID = sz;

fn void StringPool.init(&self, Allocator allocator, int capacity)
{
	self.stable_strings.init(allocator, capacity);
	self.lookup_map.init(allocator, capacity);
}

fn void StringPool.clear(&self)
{
	self.stable_strings.clear();
	self.lookup_map.clear();
}

fn void StringPool.free(&self)
{
	self.stable_strings.free();
	self.lookup_map.free();
}

fn StringID StringPool.internalize(&self, String s)
{
	if (try idx = self.lookup_map.get(s))
	{
		return idx;
	}

	self.stable_strings.push(s);
	self.lookup_map.set(s, self.stable_strings.len() - 1);
	return self.stable_strings.len() - 1;
}

fn String? StringPool.get(&self, StringID id) => self.stable_strings.get(id);
