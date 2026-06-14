module reparse_tests @test;

import parser_tests;

import analyzer::workspace;
import analyzer::parser;
import analyzer::core;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void reparsing_simple()
{
	String source_code = `
		module hello;
        
        fn void greet() {}
        fn void old_function() {}
	`;

	String source_code_2 = `
        module helloo;
        
        fn void greet() {}
        fn void new_function() {}
    `;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process_batch(&ws, mem, { { .uri = "test_1", .source_text = source_code}, { .uri = "test_2", .source_text = source_code_2 }})!!;
	defer res.free();
	test::eq(res.has_errors, false);
	test::eq(ws.modules.len(), 2);
}

fn void multi_reparsing()
{
	String source_code = `
		module hello;
        
        fn void greet() {}
        fn void old_function() {}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	

	for (int i = 0; i < 99; i++)
	{
		ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
		test::eq(res.has_errors, false);
		res.free();
		test::eq(ws.modules.len(), 1);
	}

	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	test::eq(res.has_errors, false);
	res.free();

	Module* mod = ws.modules.get("hello")!!;

	test::eq(ws.modules.len(), 1);
	test::eq(mod.sections.len(), 1);
}
