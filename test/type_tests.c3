module type_tests @test;

import parser_tests;

import analyzer::workspace;
import analyzer::parser;
import analyzer::core::ast;
import analyzer::core::string_pool;

import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void type_ident()
{
	String source_code = `
		module hello; 
		fn void greet(int foo, Bar baz) {}
	`;
	Workspace ws;
	ws.init();
	defer ws.free();
	ProcessResult res = workspace::process(&ws, mem, { .uri = "test", .source_text = source_code})!!;
	defer res.free();
	test::eq(res.has_errors, false);
}

fn void global_array_pointer()
{
	String source_code = `
		module hello;
		
		const int[4]* FOO = null;
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

	Node* target_node = s.nodes[1];
	VarDecl* decl     = target_node.as(VAR_DECL);
	test::eq(pool.get(decl.name)!!, "FOO");
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TYPE_EXPR);

	switch (type_data.kind)
	{
		case TYPE_POINTER:
			test::ne(type_data.modify.base, null);
			TypeExpr* inner_type = type_data.modify.base.as(TYPE_EXPR);
			test::eq(inner_type.kind, TypeKind.TYPE_ARRAY);

			switch (inner_type.kind)
			{
				case TYPE_ARRAY:
					test::ne(inner_type.array.base, null);
					test::ne(inner_type.array.len_expr, null);

					test::eq(inner_type.array.base.as(TYPE_EXPR).kind, TypeKind.TYPE_IDENTIFIER);
					test::eq(inner_type.array.len_expr.kind, NodeKind.LITERAL_EXPR);
					break;
				default:
					assert(false, "Expected TYPE_ARRAY directly wrapped under pointer modifier");
			}
			break;

		default:
			assert(false, "Expected root declaration type to be parsed as a TYPE_POINTER");
	}
}

fn void optional()
{
	String source_code = `
		module hello;
		
		int? foo;
		int*? foo;
		int[4]? foo = bar();
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

	Node* target_node = s.nodes[1];
	VarDecl* decl     = target_node.as(VAR_DECL);
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TYPE_EXPR);
	test::eq(type_data.optional, true);

	Node* target_node_2 = s.nodes[2];
	VarDecl* decl_2     = target_node_2.as(VAR_DECL);
	test::eq(decl_2.kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl_2.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data_2 = decl_2.type.as(TYPE_EXPR);
	test::eq(type_data_2.optional, true);

	Node* target_node_3 = s.nodes[3];
	VarDecl* decl_3     = target_node_3.as(VAR_DECL);
	test::eq(decl_3.kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl_3.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data_3 = decl_3.type.as(TYPE_EXPR);
	test::eq(type_data_3.optional, true);
}


fn void global_inferred_array_pointer()
{
	String source_code = `
		module hello;
		
		const int[*]* FOO = null;
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

	Node* target_node = s.nodes[1];
	VarDecl* decl     = target_node.as(VAR_DECL);
	test::eq(pool.get(decl.name)!!, "FOO");
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TYPE_EXPR);

	switch (type_data.kind)
	{
		case TYPE_POINTER:
			test::ne(type_data.modify.base, null);
			TypeExpr* inner_type = type_data.modify.base.as(TYPE_EXPR);
			test::eq(inner_type.kind, TypeKind.TYPE_ARRAY);

			switch (inner_type.kind)
			{
				case TYPE_ARRAY:
					test::ne(inner_type.array.base, null);
					test::eq(inner_type.array.base.as(TYPE_EXPR).kind, TypeKind.TYPE_IDENTIFIER);
					test::eq(inner_type.array.len_expr, null); // null = inferred
					break;
				default:
					assert(false, "Expected TYPE_ARRAY directly wrapped under pointer modifier");
			}
			break;
		default:
			assert(false, "Expected root declaration type to be parsed as a TYPE_POINTER");
	}
}

fn void global_generic()
{
	String source_code = `
		module hello;
		
		const List{String} CHANNELS = null;
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

	VarDecl* decl = s.nodes[1].as(VAR_DECL);
	test::eq(pool.get(decl.name)!!, "CHANNELS");
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TYPE_EXPR);

	switch (type_data.kind)
	{
		case TYPE_GENERIC:
			test::ne(type_data.generic.base, null);
			test::eq(type_data.generic.base.as(TYPE_EXPR).kind, TypeKind.TYPE_IDENTIFIER);
			test::eq(type_data.generic.params.len, 1);

			Node* first_param_node = type_data.generic.params[0];
			test::ne(first_param_node, null);
			test::eq(first_param_node.kind, NodeKind.TYPE_EXPR);

			TypeExpr* param_type = first_param_node.as(TYPE_EXPR);
			switch (param_type.kind)
			{
				case TYPE_IDENTIFIER:
					test::eq(param_type.kind, TypeKind.TYPE_IDENTIFIER);
					break;
				default:
					assert(false, "Expected the first generic parameter argument to be a TYPE_IDENTIFIER");
			}
			break;

		default:
			assert(false, "Expected root declaration type to be parsed as a TYPE_GENERIC branch");
	}
}

fn void global_vec()
{
	String source_code = `
		module hello;
		
		const float[<*>] CHANNELS = { 1.0, 2.0 };
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

	VarDecl* decl = s.nodes[1].as(VAR_DECL);
	test::eq(pool.get(decl.name)!!, "CHANNELS");
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TYPE_EXPR);

	switch (type_data.kind)
	{
		case TYPE_VECTOR:
			test::ne(type_data.array.base, null);
			test::eq(type_data.array.base.as(TYPE_EXPR).kind, TypeKind.TYPE_IDENTIFIER);
			test::eq(type_data.array.len_expr, null);
			break;
		default:
			assert(false, "Expected root declaration type to be parsed as a TYPE_VECTOR branch");
	}
}
