module parser::ast;

import std::collections::list;
import parser::trie;

struct StringPool 
{
	Allocator allocator;
	List{String} stable_strings;
	CompressedTrie{StringID} lookup_trie;
}
alias StringID = sz;

fn void StringPool.init(&self, Allocator allocator, int capacity)
{
	self.allocator = allocator;
	self.stable_strings.init(allocator, capacity);
	self.lookup_trie.init(allocator);
}

fn void StringPool.clear(&self)
{
	self.free_stable_strings();
	self.stable_strings.clear();
	self.lookup_trie.free();
	self.lookup_trie.init(self.allocator);
}

fn void StringPool.free(&self)
{
	self.free_stable_strings();
	self.stable_strings.free();
	self.lookup_trie.free();
	*self = {};
}

fn StringID StringPool.internalize(&self, String s)
{
	if (try idx = self.lookup_trie.get(s))
	{
		return idx;
	}

	String c_s = s.copy(self.allocator);
	self.stable_strings.push(c_s);
	StringID id = self.stable_strings.len() - 1;
	self.lookup_trie.insert(c_s, id);
	return id;
}

fn String? StringPool.get(&self, StringID id) => self.stable_strings.get(id);

fn bool StringPool.contains(&self, String s) => self.lookup_trie.contains(s);

fn void StringPool.free_stable_strings(&self)
{
	foreach (s : self.stable_strings)
	{
		s.free(self.allocator);
	}
}
