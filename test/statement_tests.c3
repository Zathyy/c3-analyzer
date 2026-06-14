module stmt_tests @test;

import parser_tests;

import analyzer::workspace;
import analyzer::parser;
import analyzer::core;
import analyzer::core::string_pool;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void switch_stmt()
{
	String source_code = `
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
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

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
	String source_code = `
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
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

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
	String source_code = `
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
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

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
	String source_code = `
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
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

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
	String source_code = `
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
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);
	ForStmt* for_stmt     = fn_comp.statements[0].as(FOR_STMT);

	test::eq((sz)for_stmt.label, -1);
	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void while_stmt()
{
	// uses a function just to get a compound
	String source_code = `
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
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);

	WhileStmt* while_stmt = fn_comp.statements[0].as(WHILE_STMT);
	test::eq(pool.get(while_stmt.label)!!, "FOO");

	while_stmt = fn_comp.statements[1].as(WHILE_STMT);
	test::eq(while_stmt.label, string_pool::EMPTY_STR);
}

fn void ct_assert_stmt()
{
	// uses a function just to get a compound
	String source_code = `
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
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

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
	String source_code = `
		module hello; 
		fn void foo(int a) 
		{
			$error @sprintf("no %s", @bar());
			$error "no no";
		}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

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
	String source_code = `
		module hello; 
		fn void foo(int a) 
		{
			static bool boolean = true;
			const String MY_STRING = "foo";
			tlocal bool bar = false;
		}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* node            = ws.lookup("hello", "foo")!!;
	FnDecl* func          = node.as(FN_DECL);
	CompoundStmt* fn_comp = func.body.as(COMPOUND_STMT);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void foreach_stmt()
{
	String source_code = `
		module hello;
		fn void foo(int[] arr)
		{
			foreach LOOP: (x : arr) {}

			foreach (x : arr) {}
			foreach (int x : arr) {}
			foreach (&x : arr) {}
			foreach (i, x : arr) {}
			foreach (i, &x : arr) {}

			foreach_r LOOP_R: (x : arr) {}

			foreach_r (x : arr) {}
			foreach_r (int x : arr) {}
			foreach_r (&x : arr) {}
			foreach_r (i, x : arr) {}
			foreach_r (i, &x : arr) {}
		}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* fn_node           = ws.lookup("hello", "foo")!!;
	FnDecl* fn_decl         = fn_node.as(FN_DECL);
	CompoundStmt* body_stmt = fn_decl.body.as(COMPOUND_STMT);

	// foreach LOOP: (x : arr) — labeled, no reverse,  no index, no type, no ref
	ForeachStmt* foreach_stmt = body_stmt.statements[0].as(FOREACH_STMT);
	test::eq(pool.get(foreach_stmt.label)!!, "LOOP");
	test::eq(foreach_stmt.is_reverse, false);
	test::eq(foreach_stmt.index, null);
	VarDecl* var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::eq(var_decl.type, null);
	test::eq(foreach_stmt.value_by_ref, false);
	test::eq(pool.get(var_decl.name)!!, "x");

	// foreach (x : arr) — no label, no reverse, no index, no type, no ref
	foreach_stmt = body_stmt.statements[1].as(FOREACH_STMT);
	test::eq((sz)foreach_stmt.label, -1);
	test::eq(foreach_stmt.is_reverse, false);
	test::eq(foreach_stmt.index, null);
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::eq(var_decl.type, null);
	test::eq(foreach_stmt.value_by_ref, false);
	test::eq(pool.get(var_decl.name)!!, "x");

	// foreach (int x : arr) — typed value, no ref
	foreach_stmt = body_stmt.statements[2].as(FOREACH_STMT);
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::ne(var_decl.type, null);
	TypeExpr* type_expr = var_decl.type.as(TYPE_EXPR);
	test::eq(pool.get(type_expr.unresolved.name)!!, "int");
	test::eq(foreach_stmt.value_by_ref, false);

	// foreach (&x : arr) — ref value
	foreach_stmt = body_stmt.statements[3].as(FOREACH_STMT);
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::eq(var_decl.type == null, true);
	test::eq(foreach_stmt.value_by_ref, true);
	test::eq(var_decl.flags.is_ref, true);
	test::eq(pool.get(var_decl.name)!!, "x");

	// foreach (i, x : arr) — index + value, no ref on either
	foreach_stmt = body_stmt.statements[4].as(FOREACH_STMT);
	test::ne(foreach_stmt.index, null);
	test::eq(foreach_stmt.index_by_ref, false);
	test::eq(foreach_stmt.value_by_ref, false);
	VarDecl* var_idx_decl = foreach_stmt.index.as(VAR_DECL);
	test::eq(pool.get(var_idx_decl.name)!!, "i");
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::eq(pool.get(var_decl.name)!!, "x");

	// foreach (i, &x : arr) — index, ref value
	foreach_stmt = body_stmt.statements[5].as(FOREACH_STMT);
	test::ne(foreach_stmt.index, null);
	test::eq(foreach_stmt.index_by_ref, false);
	test::eq(foreach_stmt.value_by_ref, true);
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::eq(var_decl.flags.is_ref, true);

	// foreach_r LOOP_R: (x : arr) — reverse, label
	foreach_stmt = body_stmt.statements[6].as(FOREACH_STMT);
	test::eq(foreach_stmt.is_reverse, true);
	test::eq(pool.get(foreach_stmt.label)!!, "LOOP_R");
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::eq(pool.get(var_decl.name)!!, "x");

	// foreach_r (x : arr) no index, no type, no ref
	foreach_stmt = body_stmt.statements[7].as(FOREACH_STMT);
	test::eq(foreach_stmt.is_reverse, true);
	test::eq(foreach_stmt.index, null);
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::eq(var_decl.type, null);
	test::eq(foreach_stmt.value_by_ref, false);
	test::eq(pool.get(var_decl.name)!!, "x");

	// foreach_r (int x : arr) typed
	foreach_stmt = body_stmt.statements[8].as(FOREACH_STMT);
	test::eq(foreach_stmt.is_reverse, true);
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::ne(var_decl.type, null);
	type_expr = var_decl.type.as(TYPE_EXPR);
	test::eq(pool.get(type_expr.unresolved.name)!!, "int");
	test::eq(foreach_stmt.value_by_ref, false);
	test::eq(pool.get(var_decl.name)!!, "x");

	// foreach_r (&x : arr) no type, ref
	foreach_stmt = body_stmt.statements[9].as(FOREACH_STMT);
	test::eq(foreach_stmt.is_reverse, true);
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::eq(var_decl.type == null, true);
	test::eq(foreach_stmt.value_by_ref, true);
	test::eq(var_decl.flags.is_ref, true);
	test::eq(pool.get(var_decl.name)!!, "x");

	// foreach_r (i, x : arr)
	foreach_stmt = body_stmt.statements[10].as(FOREACH_STMT);
	test::eq(foreach_stmt.is_reverse, true);
	test::ne(foreach_stmt.index, null);
	test::eq(foreach_stmt.index_by_ref, false);
	test::eq(foreach_stmt.value_by_ref, false);
	var_idx_decl = foreach_stmt.index.as(VAR_DECL);
	test::eq(pool.get(var_idx_decl.name)!!, "i");
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::eq(pool.get(var_decl.name)!!, "x");

	// foreach_r (i, &x : arr)
	foreach_stmt = body_stmt.statements[11].as(FOREACH_STMT);
	test::eq(foreach_stmt.is_reverse, true);
	test::ne(foreach_stmt.index, null);
	test::eq(foreach_stmt.index_by_ref, false);
	test::eq(foreach_stmt.value_by_ref, true);
	var_decl = foreach_stmt.variable.as(VAR_DECL);
	test::eq(var_decl.flags.is_ref, true);
	test::eq(pool.get(var_decl.name)!!, "x");
}

fn void err_foreach_missing_name_after_type()
{
	String source_code = `
		module hello;
		fn void foo(int[] arr)
		{
			foreach (int : arr) {}
		}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, true);

	Node* fn_node           = ws.lookup("hello", "foo")!!;
	FnDecl* fn_decl         = fn_node.as(FN_DECL);
	CompoundStmt* body_stmt = fn_decl.body.as(COMPOUND_STMT);

	// foreach still produces a FOREACH_STMT node; value has type but name = -1
	ForeachStmt* foreach_stmt = body_stmt.statements[0].as(FOREACH_STMT);
	VarDecl* var_decl         = foreach_stmt.variable.as(VAR_DECL);
	test::ne(var_decl.type, null);
	test::eq((sz)var_decl.name, -1);
}

fn void err_foreach_missing_name_no_type()
{
	// '& :' — AMP consumed but no IDENT follows, no type was parsed
	String source_code = `
		module hello;
		fn void foo(int[] arr)
		{
			foreach (& : arr) {}
		}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, true);

	Node* node              = ws.lookup("hello", "foo")!!;
	FnDecl* fn_decl         = node.as(FN_DECL);
	CompoundStmt* body_stmt = fn_decl.body.as(COMPOUND_STMT);

	// value_by_ref set, no type, name = -1
	ForeachStmt* foreach_stmt = body_stmt.statements[0].as(FOREACH_STMT);
	VarDecl* var_decl         = foreach_stmt.variable.as(VAR_DECL);
	test::eq(var_decl.type == null, true);
	test::eq(foreach_stmt.value_by_ref, true);
	test::eq(var_decl.flags.is_ref, true);
	test::eq((sz)var_decl.name, -1);
}

fn void err_foreach_missing_colon()
{
	// missing ':' between vars and collection — foreach node becomes ERROR
	String source_code = `
		module hello;
		fn void foo(int[] arr)
		{
			foreach (x arr) {}
		}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, true);

	Node* node              = ws.lookup("hello", "foo")!!;
	FnDecl* func            = node.as(FN_DECL);
	CompoundStmt* body_stmt = func.body.as(COMPOUND_STMT);

	// the foreach node has kind ERROR due to the missing colon
	test::eq(body_stmt.statements[0].kind, NodeKind.ERROR);
}

fn void defer_stmt()
{
	String source_code = `
		module hello; 
		fn void foo() 
		{
			defer io::printn("");
			defer io::print("A");
			defer try io::print("X");
			defer catch io::print("B");
			defer (catch err) io::printf("%s", err);
			defer {
				defer (catch err) io::printf("%s", err);
			}
		}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void do_while_stmt()
{
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			do
			{
				a++;
			} while (a < 10);

			do FOO:
			{
				a--;
			} while (a > 0);

			do
			{
				a = 0;
			};
		}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);

	Node* node              = ws.lookup("hello", "foo")!!;
	FnDecl* fn_decl         = node.as(FN_DECL);
	CompoundStmt* func_body = fn_decl.body.as(COMPOUND_STMT);
	test::eq(func_body.statements.len, 3);

	// do { ... } while (cond); — has cond, no label
	DoWhileStmt* do_while_stmt = func_body.statements[0].as(DO_WHILE_STMT);
	test::eq(do_while_stmt.body.kind, NodeKind.COMPOUND_STMT);
	test::eq(do_while_stmt.label, string_pool::EMPTY_STR);

	// do LABEL: { ... } while (cond); — has cond and label
	do_while_stmt = func_body.statements[1].as(DO_WHILE_STMT);
	test::eq(do_while_stmt.body.kind, NodeKind.COMPOUND_STMT);
	test::eq(pool.get(do_while_stmt.label)!!, "FOO");

	// do { ... }; — no while clause, parses successfully
	do_while_stmt = func_body.statements[2].as(DO_WHILE_STMT);
	test::eq(do_while_stmt.body.kind, NodeKind.COMPOUND_STMT);
	test::eq(do_while_stmt.label, string_pool::EMPTY_STR);
}

fn void assert_stmt()
{
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			assert(false, "urmom %s", foo);
			assert(false, "urmom");
		}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void ct_expand_stmt()
{
	String source_code = `
		module hello;
		fn void foo(int a)
		{
			$expand("fn int foo() {}");
		}
	`;

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}
