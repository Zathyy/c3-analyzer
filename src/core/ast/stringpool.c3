module analyzer::core::string_pool;

import std::io;

import std::collections::list;
import std::collections::map;

import analyzer::core;

faultdef
	OUT_OF_RANGE;

struct StringPool
{
	Allocator allocator;
	List{String} stable_strings;
	HashMap{String, sz} lookup_map;
}
typedef StringID = sz;

const StringID EMPTY_STR = (StringID)-1;

fn void StringPool.init(&self, Allocator allocator, int capacity)
{
	self.allocator = allocator;
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
		return (StringID) idx;
	}

	String c_s = s.copy(self.allocator);

	self.stable_strings.push(c_s);
	self.lookup_map.set(c_s, self.stable_strings.len() - 1);
	return (StringID) (self.stable_strings.len() - 1);
}

fn String? StringPool.get(&self, StringID id) 
{
	if ((sz)id >= self.stable_strings.len() || (sz)id < 0) return OUT_OF_RANGE~;
	return self.stable_strings.get((sz)id);
}
