module contract_tests @test;

import parser_tests;

import analyzer::workspace;
import analyzer::parser;
import analyzer::core;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;


fn void contract_with_expr_checks()
{
	String source_code = `
		module hello; 

		<*
			Hello there
			@param [in] a : "my param"
			@require a > 0
			@ensure return > 0
		*>
		fn int foo(int a) {}
	`;
	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

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



			{
				Node* req_expr     = decl.requires[0];
				ContractExpr* expr = req_expr.as(CONTRACT_EXPR);
				ExprList* list     = expr.exprs.as(EXPR_LIST);
				BinaryExpr* bin    = list.exprs[0].as(BINARY_EXPR);
				test::eq(bin.left.as(IDENT_EXPR).get_ident(pool)!!, "a");
				test::eq(bin.op, OperatorKind.OP_GT);
				test::eq(bin.right.as(LITERAL_EXPR).integer, 0);
			}



			{
				Node* req_expr     = decl.ensures[0];
				ContractExpr* expr = req_expr.as(CONTRACT_EXPR);
				ExprList* list     = expr.exprs.as(EXPR_LIST);
				BinaryExpr* bin    = list.exprs[0].as(BINARY_EXPR);
				test::eq(bin.left.as(IDENT_EXPR).get_ident(pool)!!, "return");
				test::eq(bin.op, OperatorKind.OP_GT);
				test::eq(bin.right.as(LITERAL_EXPR).integer, 0);
			}



			{
				Node* param         = decl.params[0];
				ContractParam* expr = param.as(CONTRACT_PARAM);
				test::eq(expr.name.as(IDENT_EXPR).get_ident(pool)!!, "a");
				test::eq(expr.modifier, InOutModifier.IN);
				test::eq(expr.get_description(pool)!!, "\"my param\"");
			}
		}
	}
}

fn void module_duplicate_contract_error()
{
	String source_code = `
		<* first doc *>
		<* second doc *>
		module hello;

		fn void foo() {}
	`;
	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, true);
}

fn void function_duplicate_contract_error()
{
	String source_code = `
		module hello;

		<* first doc *>
		<* second doc *>
		fn void foo() {}
	`;
	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, true);
}

fn void contract_with_deprecated()
{
	String source_code = `
		module hello; 

		<*
			Hello there
			@param [in] a : "my param"
			@require a > 0
			@ensure return > 0
			@deprecated "This is deprecated!"
			@pure
		*>
		fn int foo(int a) {}
	`;
	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);
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
			test::eq(decl.ensures.len, 1);
			test::eq(decl.requires.len, 1);
			test::eq(decl.params.len, 1);
			test::eq(decl.is_pure, true);

			AttributeDecl* attr = decl.deprecated.as(ATTRIBUTE_DECL);
			test::eq(attr.kind, AttributeKind.DEPRECATED);
			LiteralExpr* lit = attr.exprs[0].as(LITERAL_EXPR);
			test::eq(pool.get(lit.string)!!, "This is deprecated!");



			{
				Node* req_expr     = decl.requires[0];
				ContractExpr* expr = req_expr.as(CONTRACT_EXPR);
				ExprList* list     = expr.exprs.as(EXPR_LIST);
				BinaryExpr* bin    = list.exprs[0].as(BINARY_EXPR);
				test::eq(bin.left.as(IDENT_EXPR).get_ident(pool)!!, "a");
				test::eq(bin.op, OperatorKind.OP_GT);
				test::eq(bin.right.as(LITERAL_EXPR).integer, 0);
			}



			{
				Node* req_expr     = decl.ensures[0];
				ContractExpr* expr = req_expr.as(CONTRACT_EXPR);
				ExprList* list     = expr.exprs.as(EXPR_LIST);
				BinaryExpr* bin    = list.exprs[0].as(BINARY_EXPR);
				test::eq(bin.left.as(IDENT_EXPR).get_ident(pool)!!, "return");
				test::eq(bin.op, OperatorKind.OP_GT);
				test::eq(bin.right.as(LITERAL_EXPR).integer, 0);
			}



			{
				Node* param         = decl.params[0];
				ContractParam* expr = param.as(CONTRACT_PARAM);
				test::eq(expr.name.as(IDENT_EXPR).get_ident(pool)!!, "a");
				test::eq(expr.modifier, InOutModifier.IN);
				test::eq(expr.get_description(pool)!!, "\"my param\"");
			}
		}
	}
}
