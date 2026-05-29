module expr_tests @test;

import parser_tests;

import parser::workspace;
import parser::parser;
import parser::ast;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void test_literals()
{
	 String path = parser_tests::write_fixture("basic_contract", `
		module test_module; 

		// Primitives & Numbers
		void* a = null;
		bool b = true;
		bool c = false;
		ulong d = 1_000_000ul;
		uint e = 0xFF_AA_u32;
		int f = 0b1011_0101;
		int g = 0o755;
		
		// Floats & Real Exponents
		float h = 3.14159_f32;
		double i = 2e+10;
		float j = 0x1.Ap-2f;

		// Strings
		String k = "Hello";
		String l = "Raw string with structural text";

		// Bytes and Specialized Encodings (Emits TokenKind::BYTES)
		char[*] m = x"48 65 6c 6c 6f";                  // Hex with interior spacing
		char[*] n = x"414243";                          // Hex with single quotes
		char[*] o = b64"SGVsbG8gV29ybGQ=";              // Base64 chunk
	`
	);
    Workspace ws; ws.init();
    defer ws.free();
    ParseResult res = parser::parse_file(&ws, path)!!;
	test::eq(res.success, true);
    test::eq(ws.modules.len(), 1);
}