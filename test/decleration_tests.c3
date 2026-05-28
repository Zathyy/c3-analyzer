module decl_tests @test;

import parser_tests;

import parser::workspace;
import parser::parser;
import parser::ast;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void basic_module() 
{
    String path = parser_tests::write_fixture("basic", `module hello; fn void greet() {}`);
    Workspace ws; ws.init();
    defer ws.free();
    ParseResult res = parser::parse_file(&ws, path)!!;
	test::eq(res.success, true);
    test::eq(ws.modules.len(), 1);

    Module* mod = ws.modules.get("hello")!!;
	test::ne(mod, null);
	io::printfn("%s", mod.name);
	test::eq(mod.name, "hello");
	test::eq(mod.sections.len(), 1);

    ModuleSection* s = mod.sections[0];
	io::printfn("%s", string::from_struct(tmem, s.source_file.ast));

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void function_with_params()
{
	String path = parser_tests::write_fixture("basic", `
		module hello; 
		fn void greet(int foo, Bar baz) {}
		fn void foo(int foo, Bar baz) {}
		fn void bar(int foo, Bar baz) {}
		`
	);
    Workspace ws; ws.init();
    defer ws.free();
    ParseResult res = parser::parse_file(&ws, path)!!;
	test::eq(res.success, true);

	Node* node = ws.lookup("hello", "greet")!!;
	FnDecl* func = node.as(FN_DECL);

	Node* node_2 = ws.lookup("hello", "foo")!!;
	FnDecl* func_2 = node.as(FN_DECL);

	Node* node_3 = ws.lookup("hello", "bar")!!;
	FnDecl* func_3 = node.as(FN_DECL);
}

