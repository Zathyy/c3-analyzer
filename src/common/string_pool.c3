module string_pool;

import std::collections::list;
import std::collections::map;
import c3_parser::common;

typedef StringHandle = inline uint;

struct StringPool
{
	List{char} data;
	List{uint} offsets; // Where each string starts
	List{uint} lengths; // How long each string is
	HashMap{String, uint} lookup; // string -> ID (Temp solution)
}

fn void StringPool.init(&self, Allocator alloc = tmem)
{
	self.data.init(alloc, 1024);
	self.offsets.init(alloc, 256);
	self.lengths.init(alloc, 256);
	self.lookup.init(alloc, 256);

	// 0 is invalid state
	self.data.push(0);
	self.offsets.push(0);
	self.lengths.push(0);
}

fn void StringPool.free(&self)
{
	self.data.free();
	self.offsets.free();
	self.lengths.free();
	self.lookup.free();
}

fn StringHandle StringPool.intern(StringPool* self, String s)
{
	if (try existing = self.lookup.get(s))
	{
		return (StringHandle)existing;
	}

	uint id = (uint)self.offsets.len();
	uint start_pos = (uint)self.data.len();

	self.offsets.push(start_pos);
	self.lengths.push((uint)s.len);

	for (Size i = 0; i < s.len; i++)
	{
		self.data.push(s[i]);
	}

	self.lookup.set(s, id);
	return (StringHandle)id;
}

<*
 Get string from id
*>
fn String StringPool.get(StringPool* self, StringHandle id)
{
	if ((Size)id >= self.offsets.len())
    {
        return ""; 
    }

	uint start = self.offsets[(Size)id];
	uint len = self.lengths[(Size)id];

	if ((Size)start + len > self.data.len())
    {
        return "";
    }

	// Return a slice of the internal data
	return (String)self.data.array_view()[start:len];
}
