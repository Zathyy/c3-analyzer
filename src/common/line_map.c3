module line_map;

import std::collections::list;

struct Location
{
	usz line; 
	usz col; 
}

struct LineMap
{
    List{usz} line_offsets;
}

fn void LineMap.init(LineMap* map, Allocator alloc = tmem)
{
	map.line_offsets.init(alloc);
}

fn void LineMap.free(LineMap* map)
{
	map.line_offsets.free();
}

fn void LineMap.build(LineMap* self, String src)
{	
	if (!self.line_offsets.is_initialized())
	{
		self.line_offsets.tinit(100);
	}

    self.line_offsets.push(0);

    for (usz i = 0; i < src.len; i++)
    {
        if (src[i] == '\n')
        {
            // The NEXT line starts at i + 1
            self.line_offsets.push(i + 1);
        }
    }
}

fn Location LineMap.resolve(LineMap* self, usz pos)
{
    // Binary search for the line index
    usz line_idx = 0;
    usz low = 0;
    usz high = self.line_offsets.len() - 1;

    while (low <= high)
    {
        usz mid = low + (high - low) / 2;
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
    usz line_start_offset = self.line_offsets[line_idx];
    return (Location){
        .line = line_idx + 1,
        .col = (pos - line_start_offset) + 1
    };
}