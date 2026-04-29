module line_map;

import std::collections::list;
import c3_parser::common;

struct LineMap
{
	List{Size} line_offsets;
}

fn void LineMap.init(LineMap* map, Allocator alloc = tmem)
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
	if (!self.line_offsets.is_initialized())
	{
		self.line_offsets.tinit(100);
	}

	self.line_offsets.push(0);

	for (Size i = 0; i < src.len; i++)
	{
		if (src[i] == '\n')
		{
			// The NEXT line starts at i + 1
			self.line_offsets.push(i + 1);
		}
	}
}

fn Location LineMap.resolve(LineMap* self, Size pos)
{
	// Binary search for the line index
	Size line_idx = 0;
	Size low = 0;
	Size high = self.line_offsets.len() - 1;

	while (low <= high)
	{
		Size mid = low + (high - low) / 2;
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

	// Line is 1-based, Col is 1-based
	Size line_start_offset = self.line_offsets[line_idx];
	return (Location) { .line = line_idx + 1, .column = (pos - line_start_offset) + 1 };
}

fn uint LineMap.get_offset(LineMap* self, String src, Location loc)
{
	Size line_idx = loc.line - 1;
	if (line_idx >= self.line_offsets.len()) return (uint)src.len;

	Size line_start = self.line_offsets[line_idx];

	// Find where this line actually ends (\n or EOF)
	Size next_line_start = (line_idx + 1 < self.line_offsets.len()) ? self.line_offsets[line_idx + 1] : src.len;

	Size offset = line_start + (loc.column - 1);

	// Clamp to the end of the current line so we don't bleed into the next one
	if (offset >= next_line_start) return (uint)next_line_start - 1;

	return (uint)offset;
}

fn String LineMap.get_line_from_src(&self, String src, Size line_num)
{
	if (line_num == 0 || line_num > self.line_offsets.len()) return "";

	Size start = (Size)self.line_offsets[line_num - 1];
	Size end;

	if (line_num < self.line_offsets.len())
	{
		end = (Size)self.line_offsets[line_num];
	}
	else
	{
		end = src.len;
	}

	if (end >= src.len) return "";

	String line = src[start..end];
	return line.trim_right();
}
