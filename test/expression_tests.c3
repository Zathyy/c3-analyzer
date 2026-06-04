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
	String text = `
		module test_module; 
		
		tlocal bool blocal = true;
		
		int [*] arr = {};
		int [*] arr2 = {1};
		
		// Primitives & Numbers
		void* ax = {};
		void* a = null;
		bool b = true;
		bool bx = {};
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
		String kx = {};
		String l = "Raw string with structural text";
		String lx = ``Raw string with structural text``;

		// Bytes and Specialized Encodings (Emits TokenKind::BYTES)
		char[*] m = x"4865 6c6c 6f20 776f 726c 6421";                  // Hex with interior spacing
		char[*] n = x"414243";                          // Hex with single quotes
		char[*] o = b64"SGVsbG8gV29ybGQ=";              // Base64 chunk
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "test_literals", text)!!;
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
		test::eq(var_decl.kind, VarDeclKind.VAR_GLOBAL);
		String var_name = pool.get(var_decl.name)!!;

		test::ne(var_decl.init_expr, null);
		Node* expr_node = var_decl.init_expr;

		if (var_name == "blocal")
		{
			test::eq(var_decl.flags.is_thread_local, true);
			test::eq(expr_node.kind, NodeKind.LITERAL_EXPR);
			LiteralExpr* lit = expr_node.as(LITERAL_EXPR);
			test::eq(lit.kind, LiteralKind.BOOL_LITERAL);
			test::eq(lit.boolean, true);
			continue;
		}

		// {} is a zero initializer — an empty compound literal
		if (var_name == "ax" || var_name == "bx" || var_name == "kx" || var_name == "arr" || var_name == "arr2")
		{
			test::eq(expr_node.kind, NodeKind.EXPR_LIST);
			ExprList* zl = expr_node.as(EXPR_LIST);
			test::eq(zl.exprs.len, var_name == "arr2" ? 1 : 0);
			continue;
		}

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
		} // Integers (Decimal, Hex, Binary, Octal)
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
		else if (var_name == "l" || var_name == "lx")
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
		else
		{
			unreachable("missing assertions for variable %s", var_name);
		}
	}
}

fn void unary()
{
	String path = `
		module hello;
		bool x = !foo;
        bool x = !!foo;
        int x = -foo;
        int x = ~foo;
        void* x = &foo;
        void* x = &&foo;
        int x = *foo;
	`;
	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "unary", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, VAR_DECL), 7);
}

fn void try_catch()
{
	String path = `
		module hello;

		fn void hello()
		{
			int? a = bar();
			if (try foo)
			{
			}

			if (try val = foo)
			{
			}

			if (catch err = foo)
			{
			}

			if (catch foo)
			{
			}

			if (try a = func() && try b = func())
			{
			}
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "try_catch", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void call()
{
	String path = `
		module hello;

		fn void hello()
		{
			int a = foo() @inline;
			int b = bar() @noinline;
			int c = bar() @pure;

			int a = baz(a, b, c; err)
			{
				Foo foo;
			};
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "call", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void builtin()
{
	String path = `
		module hello;

		fn void hello()
		{
			return $$swizzle(v, ...$vaarg);
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "call", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void lambda()
{
	String path = `
		module hello;

		alias IntTransform = fn int(int);
		fn void apply(int[] arr, IntTransform t)
		{
		}
		
		fn void main()
		{
			int[] x = { 1, 2, 5 };
			apply(x, fn (i) => i * i);
			io::printfn("%s", x);
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "call", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 2);
}
