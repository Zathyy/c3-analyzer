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
