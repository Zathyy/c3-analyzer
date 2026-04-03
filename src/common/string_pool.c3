module string_pool;

import std::collections::list;
import std::collections::map;

struct StringPool 
{
    List{char} data;
	List{uint} offsets;  // Where each string starts
    List{uint} lengths;  // How long each string is
    HashMap{String, uint} lookup; // string -> ID (Temp solution)
}

fn void StringPool.init(&self, Allocator alloc = tmem)
{
    self.data.init(alloc, 1024);
    self.offsets.init(alloc, 256);
    self.lengths.init(alloc, 256);
    self.lookup.init(alloc, 256);
}

fn void StringPool.free(&self)
{
	self.data.free();
	self.offsets.free();
	self.lengths.free();
	self.lookup.free();
}

fn uint StringPool.intern(StringPool* self, String s)
{
    if (try existing = self.lookup.get(s)) 
	{
		return existing;
	}

    uint id = (uint)self.offsets.len();
    uint start_pos = (uint)self.data.len();

    self.offsets.push(start_pos);
    self.lengths.push((uint)s.len);

    for (usz i = 0; i < s.len; i++) 
	{
        self.data.push(s[i]);
    }

    self.lookup.set(s, id);
    return id;
}

/**
 * Recovers the string from the id
 */
fn String StringPool.get(StringPool* self, uint id)
{
    uint start = self.offsets[(usz)id];
    uint len = self.lengths[(usz)id];
    
    // Return a slice of the internal data
    return (String)self.data.array_view()[start:len];
}