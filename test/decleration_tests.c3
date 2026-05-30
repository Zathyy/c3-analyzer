module decl_tests @test;

import parser_tests;

import parser::workspace;
import parser::parser;
import parser::ast;
import lexer;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void basic_module()
{
	String text = `module hello; fn void greet() {}`;
	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "basic_module", text)!!;
	test::eq(res.success, true);
	test::eq(ws.modules.len(), 1);

	Module* mod = ws.modules.get("hello")!!;
	test::ne(mod, null);
	io::printfn("%s", mod.name);
	test::eq(mod.name, "hello");
	test::eq(mod.sections.len(), 1);

	ModuleSection* s = mod.sections[0];
	io::printfn("%s", string::from_struct(tmem, s.source_file.ast));

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void function_with_params()
{
	String path = `
		module hello; 
		fn void greet(int foo, Bar baz) {}
		fn void foo(int foo, Bar baz) {}
		fn void bar(int foo, Bar baz) {}
	`;
	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "function_with_params", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	Node* node   = ws.lookup("hello", "greet")!!;
	FnDecl* func = node.as(FN_DECL);

	Node* node_2   = ws.lookup("hello", "foo")!!;
	FnDecl* func_2 = node.as(FN_DECL);

	Node* node_3   = ws.lookup("hello", "bar")!!;
	FnDecl* func_3 = node.as(FN_DECL);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 3);
}


fn void method_with_params()
{
	String path = `
		module hello; 
		fn void Foo.greet(&self, Bar baz) {}
	`;
	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "method_with_params", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	Node* node   = ws.lookup("hello", "greet")!!;
	FnDecl* func = node.as(FN_DECL);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 1);
}

fn void alias_declarations_parse()
{
	String text = `module hello;
		alias IntList = List{int};
		alias Stack<Ty> = List{Ty};
		alias mc = module my::collection;
		alias old_name = new_name;
		alias OLD_CONST = constants::NEW_CONST;
		alias @old = @new;
		alias int_map = map::new {String, int};
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	ParseResult res = parser::parse(&ws, "alias_decls", text)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	Ast* ast         = s.source_file.ast;
	test::eq(ast.top_level_nodes.len(), 8);

	Node* type_node = ast.top_level_nodes[1];
	test::eq(type_node.kind, NodeKind.ALIAS_DECL);
	AliasDecl* type_alias = type_node.as(NodeKind.ALIAS_DECL);
	test::eq(type_alias.alias_kind, AliasDeclKind.TYPE_ALIAS);
	test::eq(type_alias.name_kind, TokenKind.TYPE_IDENT);
	test::eq(ast.string_pool.get(type_alias.name)!!, "IntList");
	test::eq(type_alias.target.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_target = type_alias.target.as(NodeKind.TYPE_EXPR);
	test::eq(type_target.kind, TypeKind.TYPE_GENERIC);
	test::eq(type_target.generic.params.len, 1);
	TypeExpr* type_base = type_target.generic.base.as(NodeKind.TYPE_EXPR);
	test::eq(type_base.kind, TypeKind.TYPE_IDENTIFIER);
	test::eq(ast.string_pool.get(type_base.unresolved.name)!!, "List");

	AliasDecl* generic_alias = ast.top_level_nodes[2].as(NodeKind.ALIAS_DECL);
	test::eq(generic_alias.alias_kind, AliasDeclKind.TYPE_ALIAS);
	test::eq(generic_alias.generic_params.len, 1);
	test::eq(ast.string_pool.get(generic_alias.generic_params[0])!!, "Ty");
	test::eq(generic_alias.target.as(NodeKind.TYPE_EXPR).kind, TypeKind.TYPE_GENERIC);

	Node* module_node       = ast.top_level_nodes[3];
	AliasDecl* module_alias = module_node.as(NodeKind.ALIAS_DECL);
	test::eq(module_alias.alias_kind, AliasDeclKind.MODULE_ALIAS);
	test::eq(module_alias.name_kind, TokenKind.IDENT);
	test::eq(module_alias.target.kind, NodeKind.PATH_EXPR);
	PathExpr* module_path = module_alias.target.as(NodeKind.PATH_EXPR);
	test::eq(module_path.segments.len, 2);
	test::eq(ast.string_pool.get(module_path.segments[0])!!, "my");
	test::eq(ast.string_pool.get(module_path.segments[1])!!, "collection");

	Node* ident_node       = ast.top_level_nodes[4];
	AliasDecl* ident_alias = ident_node.as(NodeKind.ALIAS_DECL);
	test::eq(ident_alias.alias_kind, AliasDeclKind.IDENT_ALIAS);
	test::eq(ident_alias.name_kind, TokenKind.IDENT);

	AliasDecl* const_alias = ast.top_level_nodes[5].as(NodeKind.ALIAS_DECL);
	test::eq(const_alias.alias_kind, AliasDeclKind.IDENT_ALIAS);
	test::eq(const_alias.name_kind, TokenKind.CONST_IDENT);
	PathExpr* const_path = const_alias.target.as(NodeKind.PATH_EXPR);
	test::eq(const_path.segments.len, 2);
	test::eq(ast.string_pool.get(const_path.segments[0])!!, "constants");
	test::eq(ast.string_pool.get(const_path.segments[1])!!, "NEW_CONST");

	AliasDecl* attr_alias = ast.top_level_nodes[6].as(NodeKind.ALIAS_DECL);
	test::eq(attr_alias.alias_kind, AliasDeclKind.IDENT_ALIAS);
	test::eq(attr_alias.name_kind, TokenKind.AT_IDENT);

	AliasDecl* generic_target_alias = ast.top_level_nodes[7].as(NodeKind.ALIAS_DECL);
	test::eq(generic_target_alias.alias_kind, AliasDeclKind.IDENT_ALIAS);
	PathExpr* generic_target_path = generic_target_alias.target.as(NodeKind.PATH_EXPR);
	test::eq(generic_target_path.segments.len, 2);
	test::eq(ast.string_pool.get(generic_target_path.segments[0])!!, "map");
	test::eq(ast.string_pool.get(generic_target_path.segments[1])!!, "new");
}

fn void malformed_alias_declarations_are_missing()
{
	String text = `module hello;
		alias old_name = NEW_NAME;
		alias mc = module my::COLLECTION;
		alias Broken<Ty Ty2> = List{Ty};
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	ParseResult res = parser::parse(&ws, "bad_alias_decls", text)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	Ast* ast         = s.source_file.ast;
	test::eq(ast.top_level_nodes.len(), 4);
	test::eq(ast.top_level_nodes[1].kind, NodeKind.MISSING);
	test::eq(ast.top_level_nodes[2].kind, NodeKind.MISSING);
	test::eq(ast.top_level_nodes[3].kind, NodeKind.MISSING);
}

fn void global_var_const()
{
	String text = `
		module hello;
		
		const int[4]* FOO = null;
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	ParseResult res = parser::parse(&ws, "var_decl", text)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

    Node* target_node = s.nodes[1];
    VarDecl* decl = target_node.as(VAR_DECL);
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
    test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
    TypeExpr* type_data = decl.type.as(TYPE_EXPR);
}

fn void global_var_multi_decl()
{
	String text = `
		module hello;
		
		int foo, bar, z;
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	ParseResult res = parser::parse(&ws, "var_decl", text)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

    Node* target_node = s.nodes[1];
    VarDecl* decl = target_node.as(VAR_DECL);
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
    test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	test::eq(pool.get(decl.name)!!, "foo");
	test::eq(decl.init_expr, null);
	test::eq(pool.get(decl.type.as(TYPE_EXPR).unresolved.name)!!, "int");

	test::ne(decl.next, null);
	VarDecl* decl_2 = decl.next.as(VAR_DECL);
	test::eq(pool.get(decl_2.name)!!, "bar");
	test::eq(decl_2.init_expr, null);
	test::eq(pool.get(decl_2.type.as(TYPE_EXPR).unresolved.name)!!, "int");

	test::ne(decl_2.next, null);
	VarDecl* decl_3 = decl_2.next.as(VAR_DECL);
	test::eq(pool.get(decl_3.name)!!, "z");
	test::eq(decl_3.next, null);
	test::eq(decl_3.init_expr, null);
	test::eq(pool.get(decl_3.type.as(TYPE_EXPR).unresolved.name)!!, "int");

}

fn void global_var()
{
	String text = `
		module hello;
		
		int[4] foo;
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	ParseResult res = parser::parse(&ws, "var_decl", text)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

    Node* target_node = s.nodes[1];
    VarDecl* decl = target_node.as(VAR_DECL);
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
    test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
    TypeExpr* type_data = decl.type.as(TYPE_EXPR);
}

fn void global_var_tlocal()
{
	String text = `
		module hello;
		
		tlocal int foo = 1;
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	ParseResult res = parser::parse(&ws, "var_decl", text)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

    Node* target_node = s.nodes[1];
    VarDecl* decl = target_node.as(VAR_DECL);
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
    test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
    TypeExpr* type_data = decl.type.as(TYPE_EXPR);
}

fn void global_var_extern()
{
	String text = `
		module hello;
		
		extern int foo;
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	ParseResult res = parser::parse(&ws, "var_decl", text)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

    Node* target_node = s.nodes[1];
    VarDecl* decl = target_node.as(VAR_DECL);
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
    test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
    TypeExpr* type_data = decl.type.as(TYPE_EXPR);
}