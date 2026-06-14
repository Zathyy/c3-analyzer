module constdef_enum_tests @test;

import parser_tests;

import analyzer::workspace;
import analyzer::parser;
import analyzer::core;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void basic_enum()
{
	String source_code = `
	module hello;
	enum MyEnum { AAA, BBB }
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(pool.get(enum_decl.name)!!, "MyEnum");
	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VAR_DECL);
		String variant_description = pool.get(var_decl.name)!!;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
	}
}

fn void values()
{
	String source_code = `
	module hello;
	enum MyEnum { AAA = 1, BBB @if(true) = 2 }
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(pool.get(enum_decl.name)!!, "MyEnum");
	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VAR_DECL);
		String variant_description = pool.get(var_decl.name)!!;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
		test::ne(var_decl.init_expr, null);
		LiteralExpr* enum_value = var_decl.init_expr.as(LITERAL_EXPR);
		test::eq(enum_value.kind, LiteralKind.INT_LITERAL);
		assert(enum_value.integer == 1 || enum_value.integer == 2, "Failed to parse enum value");
	}
}

fn void char_backing_type()
{
	String source_code = `
	module hello;
	enum MyEnum : char { AAA, BBB }
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(pool.get(enum_decl.name)!!, "MyEnum");

	TypeExpr* backing_type_expr = enum_decl.backing_type.as(TYPE_EXPR);
	test::eq(backing_type_expr.kind, TypeKind.TYPE_IDENTIFIER);

	String type_name = pool.get(backing_type_expr.unresolved.name)!!;
	test::eq(type_name, "char");

	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VAR_DECL);
		String variant_description = pool.get(var_decl.name)!!;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
	}
}

fn void assoc_param_values()
{
	String source_code = `
	module hello;
	enum MyEnum : (int a, String b) { AAA {0, "aaa"}, BBB {1, "bbb"} }
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(pool.get(enum_decl.name)!!, "MyEnum");
	test::eq(enum_decl.backing_type == null, true);

	test::eq(enum_decl.assoc_params.len, 2);

	VarDecl* a_param = enum_decl.assoc_params[0].as(VAR_DECL);
	TypeExpr* a_type = a_param.type.as(TYPE_EXPR);
	test::eq(pool.get(a_type.unresolved.name)!!, "int");
	test::eq(pool.get(a_param.name)!!, "a");

	VarDecl* b_param = enum_decl.assoc_params[1].as(VAR_DECL);
	TypeExpr* b_type = b_param.type.as(TYPE_EXPR);
	test::eq(pool.get(b_type.unresolved.name)!!, "String");
	test::eq(pool.get(b_param.name)!!, "b");

	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* variant_decl      = variant.as(VAR_DECL);
		String variant_description = pool.get(variant_decl.name)!!;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
		InitializerListExpr* assoc_values = variant_decl.assoc_values.as(INITIALIZER_LIST_EXPR);
		test::eq(assoc_values.exprs.len, 2);

		foreach (expr : assoc_values.exprs)
		{
			LiteralExpr* lit_expr = expr.as(LITERAL_EXPR);
			if (lit_expr.kind == LiteralKind.INT_LITERAL)
			{
				assert(lit_expr.integer == 0 || lit_expr.integer == 1, "Failed to parse \"a\" assoc value");
			}
			if (lit_expr.kind == LiteralKind.STRING_LITERAL)
			{
				String string_value = pool.get(lit_expr.string)!!;
				assert(string_value == "aaa" || string_value == "bbb", "Failed to parse \"b\" assoc value");
			}
		}
	}
}

fn void interfaces()
{
	String source_code = `
	module hello;
	enum MyEnum (Printable, OutStream) { AAA, BBB }
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(pool.get(enum_decl.name)!!, "MyEnum");

	test::eq(enum_decl.interfaces.len, 2);
	TypeExpr* interface_type = enum_decl.interfaces[0].as(TYPE_EXPR);
	test::eq(pool.get(interface_type.unresolved.name)!!, "Printable");
	interface_type = enum_decl.interfaces[1].as(TYPE_EXPR);
	test::eq(pool.get(interface_type.unresolved.name)!!, "OutStream");

	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VAR_DECL);
		String variant_description = pool.get(var_decl.name)!!;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
	}
}

fn void constdef_interfaces_inline_backing()
{
	String source_code = `
	module hello;
	constdef MyConstdef (Printable, OutStream) : inline uint {
		AAA @tag("constdef_member_tag", 420) = 69
	}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(pool.get(enum_decl.name)!!, "MyConstdef");
	test::eq(enum_decl.interfaces.len, 2);

	TypeExpr* interface_type = enum_decl.interfaces[0].as(TYPE_EXPR);
	test::eq(pool.get(interface_type.unresolved.name)!!, "Printable");
	interface_type = enum_decl.interfaces[1].as(TYPE_EXPR);
	test::eq(pool.get(interface_type.unresolved.name)!!, "OutStream");

	TypeExpr* backing_type_expr = enum_decl.backing_type.as(TYPE_EXPR);
	test::eq(pool.get(backing_type_expr.unresolved.name)!!, "uint");
	test::eq(enum_decl.is_inline_backing, true);

	test::eq(enum_decl.variants.len, 1);
	VarDecl* var_decl = enum_decl.variants[0].as(VAR_DECL);
	test::eq(pool.get(var_decl.name)!!, "AAA");
	test::eq(var_decl.attributes.len, 1);
	test::eq(parser_tests::@attr(var_decl, 0).kind, AttributeKind.TAG);
	test::ne(var_decl.init_expr, null);
	LiteralExpr* enum_value = var_decl.init_expr.as(LITERAL_EXPR);
	test::eq(enum_value.kind, LiteralKind.INT_LITERAL);
	test::eq(enum_value.integer, 69);
}

fn void basic_constdef()
{
	String source_code = `
	module hello;
	constdef MyConstdef {
		AAA = 1,
		BBB,
		CCC
	}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(pool.get(enum_decl.name)!!, "MyConstdef");
	test::eq(enum_decl.interfaces.len, 0);
	test::eq(enum_decl.backing_type == null, true);
	test::eq(enum_decl.is_inline_backing, false);
	test::eq(enum_decl.variants.len, 3);

	VarDecl* var_decl = enum_decl.variants[0].as(VAR_DECL);
	test::eq(pool.get(var_decl.name)!!, "AAA");
	test::ne(var_decl.init_expr, null);
	LiteralExpr* value = var_decl.init_expr.as(LITERAL_EXPR);
	test::eq(value.integer, 1);

	var_decl = enum_decl.variants[1].as(VAR_DECL);
	test::eq(pool.get(var_decl.name)!!, "BBB");
	test::eq(var_decl.init_expr == null, true);
}

fn void constdef_backing_type_and_attributes()
{
	String source_code = `
	module hello;
	constdef MyConstdef : uint @tag("decl_tag", 1) @if(true) {
		AAA @tag("value_tag", 2) = 10
	}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(pool.get(enum_decl.name)!!, "MyConstdef");
	test::eq(enum_decl.is_inline_backing, false);

	TypeExpr* backing_type_expr = enum_decl.backing_type.as(TYPE_EXPR);
	test::eq(pool.get(backing_type_expr.unresolved.name)!!, "uint");
	test::eq(enum_decl.attributes.len, 2);
	test::eq(parser_tests::@attr(enum_decl, 0).kind, AttributeKind.TAG);
	test::eq(parser_tests::@attr(enum_decl, 1).kind, AttributeKind.IF);

	test::eq(enum_decl.variants.len, 1);
	VarDecl* var_decl = enum_decl.variants[0].as(VAR_DECL);
	test::eq(pool.get(var_decl.name)!!, "AAA");
	test::eq(var_decl.attributes.len, 1);
	test::eq(parser_tests::@attr(var_decl, 0).kind, AttributeKind.TAG);
	LiteralExpr* value = var_decl.init_expr.as(LITERAL_EXPR);
	test::eq(value.integer, 10);
}

fn void enum_interfaces_backing_type()
{
	String source_code = `
	module hello;
	enum MyEnum (Printable, OutStream) : uint {
		BBB @tag("enum_member_tag", 240)
	}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(pool.get(enum_decl.name)!!, "MyEnum");
	test::eq(enum_decl.interfaces.len, 2);

	TypeExpr* interface_type = enum_decl.interfaces[0].as(TYPE_EXPR);
	test::eq(pool.get(interface_type.unresolved.name)!!, "Printable");
	interface_type = enum_decl.interfaces[1].as(TYPE_EXPR);
	test::eq(pool.get(interface_type.unresolved.name)!!, "OutStream");

	TypeExpr* backing_type_expr = enum_decl.backing_type.as(TYPE_EXPR);
	test::eq(pool.get(backing_type_expr.unresolved.name)!!, "uint");
	test::eq(enum_decl.is_inline_backing, false);

	test::eq(enum_decl.variants.len, 1);
	VarDecl* var_decl = enum_decl.variants[0].as(VAR_DECL);
	test::eq(pool.get(var_decl.name)!!, "BBB");
	test::eq(var_decl.attributes.len, 1);
	test::eq(parser_tests::@attr(var_decl, 0).kind, AttributeKind.TAG);
	test::eq(var_decl.init_expr == null, true);
}

fn void private_if_attributes()
{
	String source_code = `
	module hello;
	enum MyEnum @private @if(true) { AAA, BBB }
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(enum_node.visibility, Visibility.PRIVATE);

	test::eq(enum_decl.attributes.len, 2);
	test::eq(parser_tests::@attr(enum_decl, 0).kind, AttributeKind.PRIVATE);
	test::eq(parser_tests::@attr(enum_decl, 1).kind, AttributeKind.IF);

	test::eq(pool.get(enum_decl.name)!!, "MyEnum");
	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VAR_DECL);
		String variant_description = pool.get(var_decl.name)!!;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");
	}
}

fn void values_if_attribute()
{
	String source_code = `
	module hello;
	enum MyEnum { AAA @if(true), BBB @if(true) }
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);

	test::eq(pool.get(enum_decl.name)!!, "MyEnum");
	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VAR_DECL);
		String variant_description = pool.get(var_decl.name)!!;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");

		test::eq(var_decl.attributes.len, 1);
		test::eq(parser_tests::@attr(var_decl, 0).kind, AttributeKind.IF);
	}
}

fn void complex()
{
	String source_code = `
	module hello;
	enum MyEnum (Printable, OutStream) : char (int a, String b @tag("enum_member_tag", 1)) @tag("tag_key", "tag_value") @if(true) {
		AAA @tag("tag_key", "AAA") @if(true) {0, "a"},
		BBB @tag("tag_key", "BBB") @if(true) {1, "b"} ,
	}
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	test::eq(parser_tests::count_kind(s, ENUM_DECL), 1);

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);

	test::eq(pool.get(enum_decl.name)!!, "MyEnum");

	test::eq(enum_decl.interfaces.len, 2);
	TypeExpr* interface_type = enum_decl.interfaces[0].as(TYPE_EXPR);
	test::eq(pool.get(interface_type.unresolved.name)!!, "Printable");
	interface_type = enum_decl.interfaces[1].as(TYPE_EXPR);
	test::eq(pool.get(interface_type.unresolved.name)!!, "OutStream");

	test::eq(enum_decl.assoc_params.len, 2);

	VarDecl* a_param = enum_decl.assoc_params[0].as(VAR_DECL);
	TypeExpr* a_type = a_param.type.as(TYPE_EXPR);
	test::eq(pool.get(a_type.unresolved.name)!!, "int");
	test::eq(pool.get(a_param.name)!!, "a");

	VarDecl* b_param = enum_decl.assoc_params[1].as(VAR_DECL);
	TypeExpr* b_type = b_param.type.as(TYPE_EXPR);
	test::eq(pool.get(b_type.unresolved.name)!!, "String");
	test::eq(pool.get(b_param.name)!!, "b");

	test::eq(enum_decl.attributes.len, 2);
	test::eq(parser_tests::@attr(enum_decl, 0).kind, AttributeKind.TAG);
	test::eq(parser_tests::@attr(enum_decl, 1).kind, AttributeKind.IF);

	test::eq(enum_decl.variants.len, 2);

	foreach (variant : enum_decl.variants)
	{
		VarDecl* var_decl          = variant.as(VAR_DECL);
		String variant_description = pool.get(var_decl.name)!!;
		assert(variant_description == "AAA" || variant_description == "BBB", "Failed to parse variant description");

		test::eq(var_decl.attributes.len, 2);
		test::eq(parser_tests::@attr(var_decl, 0).kind, AttributeKind.TAG);
		test::eq(parser_tests::@attr(var_decl, 1).kind, AttributeKind.IF);
	}
}

fn void err_missing_name()
{
	String source_code = `
	module hello;
	enum { AAA, BBB }
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(enum_decl.name, (StringID)-1);
	test::eq(enum_decl.variants.len, 2);
}

fn void err_invalid_variant_name()
{
	String source_code = `
	module hello;
	enum MyEnum { bad_name, GOOD }
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* enum_node     = s.nodes[1];
	EnumDecl* enum_decl = enum_node.as(ENUM_DECL);
	test::eq(enum_decl.variants.len, 2);

	test::eq(enum_decl.variants[0].kind, NodeKind.MISSING);

	VarDecl* good = enum_decl.variants[1].as(VAR_DECL);
	test::eq(pool.get(good.name)!!, "GOOD");
}

fn void err_missing_rbrace()
{
	String source_code = `
	module hello;
	enum MyEnum { AAA, BBB
	`;

	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	// Node kind is set to MISSING when RBRACE is not found,
	// but the EnumDecl data is still populated with what was parsed.
	Node* enum_node = s.nodes[1];
	test::eq(enum_node.kind, NodeKind.ENUM_DECL);

	EnumDecl* enum_decl = (EnumDecl*)&enum_node.enum_decl;
	test::eq(enum_decl.variants.len, 2);

	VarDecl* aaa = enum_decl.variants[0].as(VAR_DECL);
	test::eq(pool.get(aaa.name)!!, "AAA");
	VarDecl* bbb = enum_decl.variants[1].as(VAR_DECL);
	test::eq(pool.get(bbb.name)!!, "BBB");
}
