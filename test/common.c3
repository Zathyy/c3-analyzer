module c3_parser_tests;

import c3_parser::workspace;
import c3_parser::parser;
import c3_parser::cursor;
import c3_parser::ast;
import c3_parser::ast::views;
import c3_parser::common;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

// ------------------------------------------------------------
// Helpers
// ------------------------------------------------------------

<*
 Write a C3 source string to a named temp file under /tmp/ and
  return the path.  Panics on I/O failure so tests fail fast.
*>
fn String write_fixture(String name, String content) @private
{
	String path = string::tformat("%s/c3_test_%s.c3", path::temp_directory(tmem)!!, name);
	File f = file::open(path, "w")!!;
	f.write(content)!!;
	(void)f.close()!!;
	return path;
}

<*
 Count how many top-level nodes in a section have a given kind.
*>
fn uint count_kind(ModuleSection* s, NodeKind kind) @private
{
	uint n = 0;
	foreach (h : s.source_file.ast.top_level_nodes)
	{
		if (h < s.start_node_idx || h >= s.end_node_idx) continue;
		if (s.source_file.ast.get_kind((Node)h) == kind) n++;
	}
	return n;
}

