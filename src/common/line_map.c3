<*
 0 based line-map
*>
module line_map;

import std::collections::list;

import parser;

struct LineMap
{
	List{sz} line_offsets;
}

fn void LineMap.init(LineMap* map, Allocator alloc = mem)
{
	map.line_offsets.init(alloc);
}

fn void LineMap.free(LineMap* map)
{
	map.line_offsets.free();
}

fn void LineMap.clear(LineMap* self)
{
	self.line_offsets.clear();
}

fn void LineMap.build(LineMap* self, String src)
{
	self.clear();

	self.line_offsets.push(0);

	for (sz i = 0; i < src.len; i++)
	{
		if (src[i] == '\n')
		{
			// The NEXT line starts at i + 1
			self.line_offsets.push(i + 1);
		}
	}
}

<*
 returns the Location as 1 based
 @require pos >= 0
*>
fn Location LineMap.resolve(LineMap* self, sz pos)
{
	// Binary search for the line index
	sz line_idx = 0;
	sz low      = 0;
	sz high     = self.line_offsets.len() - 1;

	while (low <= high)
	{
		sz mid = low + (high - low) / 2;
		if (self.line_offsets[mid] <= pos)
		{
			line_idx = mid;
			low = mid + 1;
		}
		else
		{
			high = mid - 1;
		}
	}

	sz line_start_offset = self.line_offsets[line_idx];
	return { .line = line_idx + 1, .column = (pos - line_start_offset) + 1 };
}

fn sz LineMap.get_offset(LineMap* self, String src, Location loc)
{
	sz line_idx = loc.line - 1;
	if (line_idx >= self.line_offsets.len()) return src.len;

	sz line_start = self.line_offsets[line_idx];

	// Find where this line actually ends (\n or EOF)
	sz next_line_start = (line_idx + 1 < self.line_offsets.len()) ? self.line_offsets[line_idx + 1] : src.len;

	sz offset = line_start + (loc.column - 1);

	// Clamp to the end of the current line so we don't bleed into the next one
	if (offset >= next_line_start) return next_line_start - 1;

	return offset;
}

fn String LineMap.get_line_from_src(&self, String src, sz line_num)
{
	if (line_num == 0 || line_num > self.line_offsets.len()) return "";

	sz start = self.line_offsets[line_num - 1];
	sz end;

	if (line_num < self.line_offsets.len())
	{
		end = self.line_offsets[line_num];
	}
	else
	{
		end = src.len;
	}

	if (start > src.len || end > src.len || start > end) return "";

	String line = src[start..end - 1];
	return line.trim_right();
}
