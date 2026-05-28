module parser_tests @test;

import parser::workspace;
import parser::parser;
import parser::ast;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void type_ident()
{
	String path = write_fixture("basic", `module hello; 
		fn void greet(int foo, Bar baz) {}`
	);
    Workspace ws; ws.init();
    defer ws.free();
    ParseResult res = parser::parse_file(&ws, path)!!;
	assert(res.success == true, "Failed to parse");
}