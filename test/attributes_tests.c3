module attributes_tests @test;

import parser_tests;

import analyzer::workspace;
import analyzer::parser;
import analyzer::core;
import analyzer::sema;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void module_private_test_weak_if()
{
	String source_code = `
		module hello @private @test @weak @if(1 == 1 && 2 == 2);
	`;
	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	Node* module_node       = s.nodes[0];
	ModuleDecl* module_decl = module_node.as(MODULE_DECL);
	test::eq(module_node.visibility, Visibility.PRIVATE);

	test::eq(module_decl.attributes.len, 4);

	// @private
	test::eq(parser_tests::@attr(module_decl, 0).kind, AttributeKind.PRIVATE);
	// @weak
	test::eq(parser_tests::@attr(module_decl, 1).kind, AttributeKind.TEST);
	// @test
	test::eq(parser_tests::@attr(module_decl, 2).kind, AttributeKind.WEAK);

	// @if(1 == 1 && 2 == 2)
	AttributeDecl* attr = parser_tests::@attr(module_decl, 3);
	test::eq(attr.kind, AttributeKind.IF);
	test::eq(attr.exprs.len, 1);

	// (1 == 1 && 2 == 2)
	BinaryExpr* and_expr = attr.exprs[0].as(BINARY_EXPR);
	test::eq(and_expr.op, OperatorKind.OP_AND);

	// 1 == 1
	BinaryExpr* left_eq_expr = and_expr.left.as(BINARY_EXPR);
	test::eq(left_eq_expr.left.as(LITERAL_EXPR).integer, 1u);
	test::eq(left_eq_expr.right.as(LITERAL_EXPR).integer, 1u);

	// 2 == 2
	BinaryExpr* right_eq_expr = and_expr.right.as(BINARY_EXPR);
	test::eq(right_eq_expr.left.as(LITERAL_EXPR).integer, 2u);
	test::eq(right_eq_expr.right.as(LITERAL_EXPR).integer, 2u);
}

fn void module_tag_if()
{
	String source_code = `
		module hello @tag("my_tag", "my_value") @if($feature(MY_FEATURE));
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

	ModuleDecl* module_decl = s.nodes[0].as(MODULE_DECL);
	test::eq(module_decl.attributes.len, 2);

	// @tag("my_tag", "my_value")
	AttributeDecl* attr = parser_tests::@attr(module_decl, 0);
	test::eq(attr.kind, AttributeKind.TAG);
	test::eq(attr.exprs.len, 2);

	LiteralExpr* lit_expr = attr.exprs[0].as(LITERAL_EXPR);
	test::eq(lit_expr.kind, LiteralKind.STRING_LITERAL);
	test::eq(pool.get(lit_expr.string)!!, "my_tag");

	lit_expr = attr.exprs[1].as(LITERAL_EXPR);
	test::eq(lit_expr.kind, LiteralKind.STRING_LITERAL);
	test::eq(pool.get(lit_expr.string)!!, "my_value");
	// end @tag()

	// @if($feature(MY_FEATURE))
	attr = parser_tests::@attr(module_decl, 1);
	test::eq(attr.kind, AttributeKind.IF);
	test::eq(attr.exprs.len, 1);

	CtFeatureExpr* feat          = attr.exprs[0].as(CT_FEATURE_EXPR);
	IdentExpr* callee_ident_expr = feat.inner_expr.as(IDENT_EXPR);
	test::eq(pool.get(callee_ident_expr.ident)!!, "MY_FEATURE");
}

fn void function_if()
{
	String source_code = `
		module hello;
		fn void greet() @private @if($feature(MY_FEATURE)) {}
	`;
	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);
	Module* mod      = ws.modules.get("hello")!!;
	test::ne(mod, null);
	ModuleSection* s = mod.sections[0];
	test::ne(s, null);
	StringPool* pool = &s.source_file.ast.string_pool;
	test::ne(pool, null);

	Node* node = parser_tests::@node(ws.lookup("hello", "greet")!!);
	test::ne(node, null);
	test::eq(node.kind, NodeKind.FN_DECL);

	FnDecl* fn_decl = node.as(FN_DECL);

	test::eq(node.visibility, Visibility.PRIVATE);

	// @private @if($feature(MY_FEATURE))
	test::eq(fn_decl.attributes.len, 2);

	// @if($feature(MY_FEATURE))
	AttributeDecl* attr = parser_tests::@attr(fn_decl, 1);
	test::eq(attr.kind, AttributeKind.IF);
	test::eq(attr.exprs.len, 1);

	CtFeatureExpr* feat          = attr.exprs[0].as(CT_FEATURE_EXPR);
	IdentExpr* callee_ident_expr = feat.inner_expr.as(IDENT_EXPR);
	test::eq(pool.get(callee_ident_expr.ident)!!, "MY_FEATURE");
}

fn void const_var_private_if()
{
	String source_code = `
		module hello;
		
		const MY_CONST @private @if($feature(MY_FEATURE)) = 1;
		void* my_var @private @if($feature(MY_FEATURE)) = null;
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

	foreach (node : s.nodes)
	{
		if (node.kind != VAR_DECL) continue;

		VarDecl* var_decl = node.as(VAR_DECL);

		test::eq(node.visibility, Visibility.PRIVATE);
		test::eq(node.flags.has_attributes, true);

		String var_name = pool.get(var_decl.name)!!;

		test::eq(var_decl.kind, VarDeclKind.VAR_GLOBAL);
		test::eq(var_decl.attributes.len, 2);
		if (var_decl.flags.is_const)
		{
			test::eq(var_name, "MY_CONST");
		}
		else
		{
			test::eq(var_name, "my_var");
		}

		// @if($feature(MY_FEATURE))
		AttributeDecl* attr = parser_tests::@attr(var_decl, 1);
		test::eq(attr.kind, AttributeKind.IF);
		test::eq(attr.exprs.len, 1);

		// $feature()
		CtFeatureExpr* call          = attr.exprs[0].as(CT_FEATURE_EXPR);
		IdentExpr* callee_ident_expr = call.inner_expr.as(IDENT_EXPR);
		test::eq(pool.get(callee_ident_expr.ident)!!, "MY_FEATURE");
	}
}
