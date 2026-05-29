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
		uint e = 0xFF_AAu;
		int f = 0b1011_0101;
		int g = 0o755;
		
		// Floats & Real Exponents
		float h = 3.14159f32;
		double i = 2e+10f64;
		float j = 0x1.Ap-2f;

		// Strings
		String k = "Hello";
		String l = "Raw string with structural text";

		// Bytes and Specialized Encodings (Emits TokenKind::BYTES)
		char[*] m = x"4865 6c6c 6f20 776f 726c 6421";                  // Hex with interior spacing
		char[*] n = x"414243";                          // Hex with single quotes
		char[*] o = b64"SGVsbG8gV29ybGQ=";              // Base64 chunk
	`
	);
	Workspace ws; ws.init();
	defer ws.free();
	ParseResult res = parser::parse_file(&ws, path)!!;
	test::eq(res.success, true);
	test::eq(ws.modules.len(), 1);

	Module* mod = ws.modules.get("test_module")!!;
	test::ne(mod, null);
	io::printfn("%s", mod.name);
	test::eq(mod.name, "test_module");
	test::eq(mod.sections.len(), 1);

	ModuleSection* s = mod.sections[0];
	io::printfn("%s", string::from_struct(tmem, s.source_file.ast));
	StringPool* pool = &s.source_file.ast.string_pool;

	foreach (node : s.nodes)
	{
		if (node.kind != VAR_DECL) continue;

		VarDecl* var_decl = node.as(VAR_DECL);
		String var_name = pool.get(var_decl.name)!!;
		
		test::ne(var_decl.init_expr, null);
		Node* expr_node = var_decl.init_expr;
		test::eq(expr_node.kind, NodeKind.LITERAL_EXPR);

		LiteralExpr* lit = expr_node.as(LITERAL_EXPR);

		if (var_name == "a")
		{
			test::eq(lit.kind, LiteralKind.NULL_LITERAL);
		}
		else if (var_name == "b")
		{
			test::eq(lit.kind, LiteralKind.BOOL_LITERAL);
			test::eq(lit.boolean, true);
		}
		else if (var_name == "c")
		{
			test::eq(lit.kind, LiteralKind.BOOL_LITERAL);
			test::eq(lit.boolean, false);
		}
		// Integers (Decimal, Hex, Binary, Octal)
		else if (var_name == "d")
		{
			test::eq(lit.kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 1000000);
		}
		else if (var_name == "e")
		{
			test::eq(lit.kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 0xFFAA); // 65450
		}
		else if (var_name == "f")
		{
			test::eq(lit.kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 0b10110101); // 181
		}
		else if (var_name == "g")
		{
			test::eq(lit.kind, LiteralKind.INT_LITERAL);
			test::eq(lit.integer, 0o755); // 493
		}
		else if (var_name == "h")
		{
			test::eq(lit.kind, LiteralKind.REAL_LITERAL);
			test::eq_approx(lit.real, 3.14159);
		}
		else if (var_name == "i")
		{
			test::eq(lit.kind, LiteralKind.REAL_LITERAL);
			test::eq_approx(lit.real, 2e+10);
		}
		else if (var_name == "j")
		{
			test::eq(lit.kind, LiteralKind.REAL_LITERAL);
			test::eq_approx(lit.real, 0.40625); // 0x1.Ap-2 is 1.625 * 0.25 = 0.40625
		}
		else if (var_name == "k")
		{
			test::eq(lit.kind, LiteralKind.STRING_LITERAL);
			test::eq(pool.get(lit.string)!!, "Hello");
		}
		else if (var_name == "l")
		{
			test::eq(lit.kind, LiteralKind.STRING_LITERAL);
			test::eq(pool.get(lit.string)!!, "Raw string with structural text");
		}
		else if (var_name == "m")
		{
			test::eq(lit.kind, LiteralKind.BYTES_LITERAL);
			test::eq(lit.bytes.len, 12);
			// "Hello world!" in bytes
			test::eq((char)lit.bytes[0], 'H');
			test::eq((char)lit.bytes[11], '!');
		}
		else if (var_name == "n")
		{
			test::eq(lit.kind, LiteralKind.BYTES_LITERAL);
			test::eq(lit.bytes.len, 3);
			// "ABC"
			test::eq((char)lit.bytes[0], 'A');
			test::eq((char)lit.bytes[1], 'B');
			test::eq((char)lit.bytes[2], 'C');
		}
		else if (var_name == "o")
		{
			test::eq(lit.kind, LiteralKind.BYTES_LITERAL);
			test::eq(lit.bytes.len, 11);
			// "Hello World" decoded from Base64
			test::eq((char)lit.bytes[0], 'H');
			test::eq((char)lit.bytes[6], 'W');
		}
	}
}