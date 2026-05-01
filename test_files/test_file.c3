module bv;

import std::io;

fn int sum(int a, int b) 
{
	return a + b; 
}

macro HashMap* HashMap.init_with_key_values(&self, Allocator allocator, ..., sz capacity = DEFAULT_INITIAL_CAPACITY, float load_factor = DEFAULT_LOAD_FACTOR)
{
	self.init(allocator, capacity, load_factor);
	$for var $i = 0; $i < $vaarg.len; $i += 2:
		self.set($vaarg[$i], $vaarg[$i + 1]);
	$endfor
	return self;
}