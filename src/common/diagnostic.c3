module parser::diagnostics;

import line_map;
import parser;

import std::io;

struct Diagnostic
{
    LogPriority level;
    Location start_loc;
    Location end_loc;
    String message;
    String file_path;
}

<*
 @param alloc : "allocator"
 @param [&in] section
*>
fn void diagnose(
	Allocator alloc,
	ModuleSection* section,
	int byte_offset_start,
	int byte_offset_end,
	LogPriority level,
	String fmt,
	args...
)
{
	LineMap* map = &section.source_file.line_map;
	Location loc = map.resolve((sz)byte_offset_start);
	Location end_loc = map.resolve((sz)byte_offset_end);
	String file_path = section.source_file.file_path;

	String msg = string::format(alloc, fmt, ...args);
	section.diagnostics.push({ level, loc, end_loc, msg, file_path });
	
	$if $feature(PARSER_CLI):
 		io::printf("%s:%s:%s: %s%s:%s ", file_path, loc.line + 1, loc.column + 1, Ansi.RED, level.description, Ansi.RESET);
		io::printf(fmt, ...args);
		io::printn("");

		String line_text = map.get_line_from_src(section.source_file.source, loc.line);
		io::printf(" %4s | %s\n", loc.line + 1, line_text);

		io::printf(" %4s | ", "");
		for (sz i = 0; i < loc.column; i++)
		{
			if (i < line_text.len && line_text[i] == '\t') 
			{
				io::print("\t");
			}
			else 
			{
				io::print(" ");
			}
		}
		io::printf("%s^%s\n", Ansi.RED, Ansi.RESET);
	$endif
}