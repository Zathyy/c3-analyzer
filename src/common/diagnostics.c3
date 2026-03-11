module c3_parser::diagnostics;

import std::io;
import std::collections::list;

import c3_parser::common;

enum DiagnosticLevel 
{
    INFO,
    WARN,
    ERROR
}

struct FileEntry 
{
	String name;
	String source;
	List{ uint } line_starts;
}

Allocator alloc;
List{ FileEntry* } files;
bool use_diagnostics = false;

fn void init(Allocator allocator)
{
	alloc = allocator;
	files.init(alloc);
	use_diagnostics = true;
}

fn void free()
{
	files.free();
}

<*
	add a file to be recognized by the diangostics.
	adds support to map a 'SourceSpan' to (line, culumn)

	@require files.is_initialized() : "files list is not initialized"
*>
fn FileID add_file(String name, String source)
{
	FileEntry* entry = allocator::new(alloc, FileEntry);
	entry.name = name;
	entry.source = source;
	
	//TODO?: calculate approximate num of line endings before allocating
	entry.line_starts.init(alloc, 100);
	entry.line_starts.push(0);
	
	for (uint i = 0; i < (uint)source.len; i++)
	{
		if (source[i] == '\n')
		{
			entry.line_starts.push(i + 1);
		}
	}

	files.push(entry);
	return (FileID)files.len() - 1;
}

fn Position get_pos(FileID id, uint offset)
{
	assert((usz)id < files.len());
	
	FileEntry* entry = files[(usz)id];

	// Binary search to find the line
    // We want the index of the largest value <= offset
	usz low = 0;
	usz high = entry.line_starts.len() - 1;
	usz line_index = 0;

	while (low <= high)
	{
		usz mid = low + (high - low) / 2;
		if (entry.line_starts[mid] <= offset)
		{
			line_index = mid;
			low = mid + 1;
		}
		else
		{
			high = mid - 1;
		}
	}

	return (Position){
		.line = line_index + 1,
		.column = (usz)offset - entry.line_starts[line_index] + 1
	};
}

fn String get_string(SourceSpan span)
{
	if (span.start > span.end)
	{
		return "Invalid";
	}

	FileEntry* entry = files[(usz)span.file_id];
	return entry.source[span.start..span.end];
}

fn void report(DiagnosticLevel level, SourceSpan span, String format, args...)
{
	Position pos = get_pos(span.file_id, (uint)span.start);
    FileEntry* file = files[(usz)span.file_id];

    (void)io::printf("%s:%d:%d: ", file.name, pos.line, pos.column);
	(void)io::printf("[%s] ", level);
    (void)io::printfn(format, args);
}