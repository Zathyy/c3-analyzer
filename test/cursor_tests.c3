module cursor_tests @test;

import parser_tests;

import analyzer::workspace;
import analyzer::parser;
import analyzer::core;
import analyzer::cursor;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void basic_cursor_test()
{
	String source_code = `
		module hello;
        
        fn void greet() {}
        fn void old_function() {}
	`;

	String source_code_2 = `
		module foo;
        
        fn void greet() {}
        fn void old_function() {}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process_batch(&ws, mem, { 
		{ .uri = "hello.c3", .source_text = source_code }, 
		{ .uri = "foo.c3",   .source_text = source_code_2 }
	})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	Node* module_node       = s.nodes[0];
	ModuleDecl* module_decl = module_node.as(MODULE_DECL);

	foreach (node : s.nodes)
	{
		Location loc = s.source_file.line_map.resolve((sz)node.start_token);
		io::printfn("Node (%s) - %s:%s", node.kind.description, loc.line, loc.column);
	}

	Cursor hello_cursor = ws.find_at_location("hello.c3", { .line = 4, .column = 10 });
	test::ne(hello_cursor.node, null);
	test::eq(hello_cursor.node.kind, NodeKind.FN_DECL);
}
