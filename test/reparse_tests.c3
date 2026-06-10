module reparse_tests @test;

import parser_tests;

import parser::workspace;
import parser::parser;
import parser::ast;
import lexer;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void reparsing_simple()
{
	String text = `
		module hello;
        
        fn void greet() {}
        fn void old_function() {}
	`;

	String text2 = `
        module hello;
        
        fn void greet() {}
        fn void new_function() {}
    `;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "reparsing_simple", text)!!;
	test::eq(res.success, true);
	test::eq(ws.modules.len(), 1);

	res = parser::parse(&ws, "reparsing_simple", text)!!;
	test::eq(res.success, true);
	test::eq(ws.modules.len(), 1);
}

fn void multi_reparsing()
{
	String text = `
		module hello;
        
        fn void greet() {}
        fn void old_function() {}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	for (int i = 0; i < 99; i++)
	{
		ParseResult res = parser::parse(&ws, "reparsing_simple", text)!!;
		test::eq(res.success, true);
		test::eq(ws.modules.len(), 1);
	}

	ParseResult res = parser::parse(&ws, "reparsing_simple", text)!!;
	test::eq(res.success, true);

	Module* mod = ws.modules.get("hello")!!;

	test::eq(ws.modules.len(), 1);
	test::eq(mod.sections.len(), 1);
}
