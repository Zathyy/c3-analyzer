module stmt_tests @test;

import parser_tests;

import parser::workspace;
import parser::parser;
import parser::ast;
import lexer;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void switch_stmt()
{
	String path = `
		module hello; 
		fn void foo() 
		{
			int a = 5;
			switch LABEL: (a)
			{
				case 1: break;
				case 2:
					{
					}
				case 3:
				case 4: continue LABEL;
				case 5: break LABEL;
				case 6: continue;
				case 7: break;
				case 8:
					{
					}
					nextcase;
				default:
			}
		}
	`;
	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "method_with_params", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);
	SwitchStmt* sw        = fn_comp.statements[1].as(SWITCH_STMT);
	test::eq(sw.cases.len, 9);
	CondExpr* cond = sw.cond.as(COND_EXPR);
	test::eq(cond.exprs[0].as(IDENT_EXPR).get_ident(pool)!!, "a");
	test::eq(pool.get(sw.label)!!, "LABEL");

	CaseStmt* case0      = sw.cases[0].as(CASE_STMT);
	CompoundStmt* comp_0 = case0.body.as(COMPOUND_STMT);
	test::eq(comp_0.statements[0].kind, NodeKind.CONTINUE_BREAK_STMT);
	CaseStmt* case1      = sw.cases[1].as(CASE_STMT);
	CompoundStmt* comp_1 = case1.body.as(COMPOUND_STMT);
	test::eq(comp_1.statements.len, 1);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void ct_switch_stmt()
{
	// uses a function just to get a compound
	String path = `
		module hello; 
		fn void foo() 
		{
			$switch $x:
				$case 1:
					#y += $x * $x;
				$case 2:
					#y += $x;
				$case 3:
					#y *= $x;
				$default:
					#y -= $x;
			$endswitch
		}
	`;
	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "ct_switch_stmt", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);
	CtSwitchStmt* sw      = fn_comp.statements[0].as(CT_SWITCH_STMT);
	test::eq(sw.cases.len, 4);
	test::eq(sw.cond[0].as(IDENT_EXPR).get_ident(pool)!!, "$x");

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void if_elseif_else()
{
	// uses a function just to get a compound
	String path = `
		module hello; 
		fn void foo(int a) 
		{
			if LABEL: (a > 0 && a < 10)
			{
			}
			else if (a == 5)
			{
			}
			else
			{
			}
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "if_elseif_else", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);
	IfStmt* if_stmt       = fn_comp.statements[0].as(IF_STMT);
	IfStmt* if_stmt_2     = if_stmt.else_body.as(IF_STMT);
	test::eq(if_stmt_2.then_body.kind, NodeKind.COMPOUND_STMT);
	test::eq(if_stmt_2.else_body.kind, NodeKind.COMPOUND_STMT);
	test::eq(if_stmt.then_body.kind, NodeKind.COMPOUND_STMT);
	test::ne(if_stmt.else_body, null);
	test::eq(pool.get(if_stmt.label)!!, "LABEL");
	test::eq(fn_comp.statements.len, 1);
	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void ct_if_else()
{
	// uses a function just to get a compound
	String path = `
		module hello; 
		fn void foo(int a) 
		{
			$if $x > 3:
				#y += $x * $x;
			$else
				#y += $x;
			$endif

			$if $x > 3:
				#y += $x * $x;
			$endif
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "if_elseif_else", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void for_stmt()
{
	// uses a function just to get a compound
	String path = `
		module hello; 
		fn void foo(int a) 
		{
			for (;;)
			{
			}

			for (sz i = 0; i < 10; i++)
			{
			}

			for (sz i = 0; i < 10;)
			{
			}
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "if_elseif_else", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);

	if (try label = fn_comp.statements[0].as(FOR_STMT).label.get())
	{
		assert(false, "label should not be defined");
	}

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void while_stmt()
{
	// uses a function just to get a compound
	String path = `
		module hello; 
		fn void foo(int a) 
		{
			while FOO: (true)
			{
			}

			while (a > b)
			{
			}

			while (a > b) return a;
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "if_elseif_else", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void ct_assert_stmt()
{
	// uses a function just to get a compound
	String path = `
		module hello; 
		fn void foo(int a) 
		{
			$assert 2 == 2;
			$assert @bar() == MY_CONST;
			$assert 98 == -2 : "no no";
			$assert 98 == -2 : @sprintf("no %s", @bar());
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "ct_assert_stmt", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void ct_error_stmt()
{
	// uses a function just to get a compound
	String path = `
		module hello; 
		fn void foo(int a) 
		{
			$error @sprintf("no %s", @bar());
			$error "no no";
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "ct_error_stmt", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void var_decl_stmt()
{
	// uses a function just to get a compound
	String path = `
		module hello; 
		fn void foo(int a) 
		{
			static bool boolean = true;
			const String MY_STRING = "foo";
			tlocal bool bar = false;
		}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "var_decl_stmt", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}
