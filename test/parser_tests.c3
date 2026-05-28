module parser_tests;

import parser::workspace;
import parser::parser;
import parser::ast;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void test_basic_module() @test
{
    String path = write_fixture("basic", `module hello; fn void greet() {}`);

    Workspace ws; ws.init();
    defer ws.free();
    ParseResult res = parser::parse_file(&ws, path)!!;

    assert(ws.modules.len() == 1, "Expected one module");

    Module* mod = ws.modules.get("hello")!!;
    assert(mod != null, "Module 'hello' not found");
    assert(mod.name == "hello", "Module name mismatch");
    assert(mod.sections.len() == 1, "Expected one section inside module 'hello'");

    ModuleSection* s = mod.sections[0];
	io::printfn("%s", string::from_struct(tmem, s.source_file.ast));

    assert(count_kind(s, MODULE_DECL) == 1, "Expected exactly 1 MODULE_DECL");
    assert(count_kind(s, FN_DECL) == 1, "Expected exactly 1 FN_DECL");
}