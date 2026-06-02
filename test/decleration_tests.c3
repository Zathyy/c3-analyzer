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
		fn void foo(Type... name) {}
		fn void default_value(Type name = 15) {}
		fn void untyped_variadic(...) {}
		fn void with_attributes(Type name @noalias) {}
		fn void untyped(args...) {}
	`;
	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "function_with_params", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, FN_DECL), 6);
}

fn void method_with_params()
{
	String path = `
		module hello; 
		fn void Foo.greet(&self, Bar baz) {}
		fn void Foo.greet(self, Bar baz) {}
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
	test::eq(parser_tests::count_kind(s, FN_DECL), 2);
}

fn void macro_with_params()
{
	String path = `
		module hello; 
		macro void greet(int foo, Bar baz) {}
		macro foo(int foo, Bar baz) {}
		macro bar(int foo, Bar baz) => 2;
	`;
	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "macro_with_params", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	Node* node      = ws.lookup("hello", "greet")!!;
	MacroDecl* func = node.as(MACRO_DECL);

	Node* node_2      = ws.lookup("hello", "foo")!!;
	MacroDecl* func_2 = node_2.as(MACRO_DECL);

	Node* node_3      = ws.lookup("hello", "bar")!!;
	MacroDecl* func_3 = node_3.as(MACRO_DECL);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, MACRO_DECL), 3);
}

fn void macro_method_with_params()
{
	String path = `
		module hello; 
		macro void Foo.greet(&self, Bar baz) {}
		macro Foo.wow(&self, Bar bar) {}
	`;
	Workspace ws;
	ws.init();
	defer ws.free();
	ParseResult res = parser::parse(&ws, "method_with_params", path)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];

	Node* node     = ws.lookup("hello", "greet")!!;
	MacroDecl* mac = node.as(MACRO_DECL);

	test::eq(parser_tests::count_kind(s, MODULE_DECL), 1);
	test::eq(parser_tests::count_kind(s, MACRO_DECL), 2);
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
		alias ElementPredicate = fn bool(Type *type);
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	ParseResult res = parser::parse(&ws, "alias_decls", text)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	Ast* ast         = s.source_file.ast;
	test::eq(ast.top_level_nodes.len(), 9);

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

	AliasDecl* fn_ptr_alias = ast.top_level_nodes[8].as(NodeKind.ALIAS_DECL);
	test::eq(fn_ptr_alias.alias_kind, AliasDeclKind.TYPE_ALIAS);
	test::eq(ast.string_pool.get(fn_ptr_alias.name)!!, "ElementPredicate");
	TypeExpr* fn_ptr_type = fn_ptr_alias.target.as(NodeKind.TYPE_EXPR);
	test::eq(fn_ptr_type.kind, TypeKind.TYPE_FUNCTION);
	TypeExpr* fn_ret_type = fn_ptr_type.func.ret_type.as(NodeKind.TYPE_EXPR);
	test::eq(fn_ret_type.kind, TypeKind.TYPE_IDENTIFIER);
	test::eq(ast.string_pool.get(fn_ret_type.unresolved.name)!!, "bool");
	test::eq(fn_ptr_type.func.params.len, 1);
	VarDecl* fn_param = fn_ptr_type.func.params[0].as(NodeKind.VAR_DECL);
	test::eq(fn_param.kind, VarDeclKind.VAR_PARAM);
	test::eq(ast.string_pool.get(fn_param.name)!!, "type");
	TypeExpr* param_type = fn_param.type.as(NodeKind.TYPE_EXPR);
	test::eq(param_type.kind, TypeKind.TYPE_POINTER);
	TypeExpr* param_base_type = param_type.modify.base.as(NodeKind.TYPE_EXPR);
	test::eq(ast.string_pool.get(param_base_type.unresolved.name)!!, "Type");
}

fn void typedef_declarations_parse()
{
	String text = `module hello;
		typedef MyId = int;
		typedef MyId2 @constinit = int;
		typedef Bcd @constinit = inline int;
		typedef IntAlign2 = int @align(2);
		typedef Float4 = float[<4>] @simd;
		typedef EnumSet (Printable) = EnumSetType;
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	ParseResult res = parser::parse(&ws, "typedef_decls", text)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	Ast* ast         = s.source_file.ast;
	test::eq(ast.top_level_nodes.len(), 7);

	TypedefDecl* my_id = ast.top_level_nodes[1].as(NodeKind.TYPEDEF_DECL);
	test::eq(ast.string_pool.get(my_id.name)!!, "MyId");
	test::eq(my_id.is_inline, false);
	test::eq(my_id.attributes.len, 0);
	TypeExpr* my_id_base = my_id.base_type.as(NodeKind.TYPE_EXPR);
	test::eq(my_id_base.kind, TypeKind.TYPE_IDENTIFIER);
	test::eq(ast.string_pool.get(my_id_base.unresolved.name)!!, "int");

	TypedefDecl* my_id2 = ast.top_level_nodes[2].as(NodeKind.TYPEDEF_DECL);
	test::eq(ast.string_pool.get(my_id2.name)!!, "MyId2");
	test::eq(my_id2.attributes.len, 1);

	TypedefDecl* bcd = ast.top_level_nodes[3].as(NodeKind.TYPEDEF_DECL);
	test::eq(ast.string_pool.get(bcd.name)!!, "Bcd");
	test::eq(bcd.is_inline, true);
	test::eq(bcd.attributes.len, 1);

	TypedefDecl* int_align = ast.top_level_nodes[4].as(NodeKind.TYPEDEF_DECL);
	test::eq(ast.string_pool.get(int_align.name)!!, "IntAlign2");
	test::eq(int_align.attributes.len, 1);

	TypedefDecl* float4 = ast.top_level_nodes[5].as(NodeKind.TYPEDEF_DECL);
	test::eq(ast.string_pool.get(float4.name)!!, "Float4");
	test::eq(float4.attributes.len, 1);
	TypeExpr* float4_base = float4.base_type.as(NodeKind.TYPE_EXPR);
	test::eq(float4_base.kind, TypeKind.TYPE_VECTOR);
	test::eq(float4_base.array.len_expr.kind, NodeKind.LITERAL_EXPR);

	TypedefDecl* enum_set = ast.top_level_nodes[6].as(NodeKind.TYPEDEF_DECL);
	test::eq(ast.string_pool.get(enum_set.name)!!, "EnumSet");
	test::eq(enum_set.interfaces.len, 1);
	TypeExpr* interface_type = enum_set.interfaces[0].as(NodeKind.TYPE_EXPR);
	test::eq(ast.string_pool.get(interface_type.unresolved.name)!!, "Printable");
	TypeExpr* enum_set_base = enum_set.base_type.as(NodeKind.TYPE_EXPR);
	test::eq(ast.string_pool.get(enum_set_base.unresolved.name)!!, "EnumSetType");
}

fn void function_pointer_types_are_alias_only()
{
	String alias_text = `module hello;
		alias CallbackDefault = fn void(int value = 0);
	`;

	Workspace alias_ws;
	alias_ws.init();
	defer alias_ws.free();

	ParseResult alias_res = parser::parse(&alias_ws, "fn_ptr_alias_default", alias_text)!!;
	test::eq(alias_res.success, true);

	Module* alias_mod      = alias_ws.modules.get("hello")!!;
	ModuleSection* alias_s = alias_mod.sections[0];
	Ast* alias_ast         = alias_s.source_file.ast;
	AliasDecl* alias_decl  = alias_ast.top_level_nodes[1].as(NodeKind.ALIAS_DECL);
	TypeExpr* alias_target = alias_decl.target.as(NodeKind.TYPE_EXPR);
	test::eq(alias_target.kind, TypeKind.TYPE_FUNCTION);
	test::eq(alias_target.func.params.len, 1);
	VarDecl* alias_param = alias_target.func.params[0].as(NodeKind.VAR_DECL);
	test::eq(alias_param.init_expr.kind, NodeKind.LITERAL_EXPR);
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
	VarDecl* decl     = target_node.as(VAR_DECL);
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
	VarDecl* decl     = target_node.as(VAR_DECL);
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
	VarDecl* decl     = target_node.as(VAR_DECL);
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
	VarDecl* decl     = target_node.as(VAR_DECL);
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
	VarDecl* decl     = target_node.as(VAR_DECL);
	test::eq(decl.kind, VarDeclKind.VAR_GLOBAL);
	test::eq(decl.type.kind, NodeKind.TYPE_EXPR);
	TypeExpr* type_data = decl.type.as(TYPE_EXPR);
}

fn void expand()
{
	String text = `
		module hello;
		
		$expand("fn void foo();");
	`;

	Workspace ws;
	ws.init();
	defer ws.free();

	ParseResult res = parser::parse(&ws, "expand", text)!!;
	test::eq(res.success, true);

	Module* mod      = ws.modules.get("hello")!!;
	ModuleSection* s = mod.sections[0];
	StringPool* pool = &s.source_file.ast.string_pool;

	Node* target_node    = s.nodes[1];
	CtExpandDecl* decl   = target_node.as(CT_EXPAND_DECL);
	LiteralExpr* literal = decl.expr.as(LITERAL_EXPR);
	test::eq(pool.get(literal.string)!!, "fn void foo();");
}
