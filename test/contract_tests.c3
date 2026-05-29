module contract_tests @test;

import parser_tests;

import parser::workspace;
import parser::parser;
import parser::ast;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;


fn void basic_contract() 
{
    String path = parser_tests::write_fixture("basic_contract", `
		module hello; 

		<*
			Hello there
			@param [in] a : "my param"
			@require a > 0
			@ensure return > 0
		*>
		fn int foo(int a) {}
	`
	);
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
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, CONTRACT_DECL), 1);

	foreach (node : s.nodes)
	{
		if (node.kind == CONTRACT_DECL)
		{
			ContractDecl* decl = node.as(CONTRACT_DECL);
			io::printfn("%s", string::from_struct(tmem, *decl));
			test::eq(decl.get_comment(pool)!!, "Hello there");
			test::eq(decl.deprecated, null);
			test::eq(decl.ensures.len, 1);
			test::eq(decl.requires.len, 1);
			test::eq(decl.params.len, 1);
		}
	}
}
