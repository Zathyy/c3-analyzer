module c3_parser_tests;

import c3_parser::workspace;
import c3_parser::parser;
import c3_parser::cursor;
import c3_parser::ast;
import c3_parser::ast::views;
import c3_parser::common;
import std::io;
import lexer;

// Helper: return first top-level node of the given kind in a section.
fn Node first_node_of_kind(ModuleSection* s, NodeKind kind) @private
{
	Ast* ast = &s.source_file.ast;
	foreach (h : s.source_file.ast.top_level_nodes)
	{
		if (h < s.start_node_idx || h >= s.end_node_idx) continue;
		if (ast.get_kind((Node)h) == kind) return (Node)h;
	}
	return (Node){};
}

// ============================================================
// FnView
// ============================================================

fn void test_fn_view_name_accessor() @test //=> @pool()
{
	String path = write_fixture("fv_name", `module fv;
fn void hello() {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("fv", "hello")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	assert(fv.name(&ws.strings) == "hello", "FnView.name()");
}

fn void test_fn_view_return_type_name() @test //=> @pool()
{
	String path = write_fixture("fv_ret", `module fv;
fn int compute() { return 1; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("fv", "compute")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	Node ret = fv.return_type();
	assert(ret.is_valid(), "return_type must be valid");
	TypeView tv = { ast, ret };
	assert(tv.name(&ws.strings) == "int", "return type name");
}

fn void test_fn_view_void_return() @test //=> @pool()
{
	String path = write_fixture("fv_void", `module fv;
fn void noop() {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("fv", "noop")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	TypeView tv = { ast, fv.return_type() };
	assert(tv.name(&ws.strings) == "void", "void return type");
}

fn void test_fn_view_param_count_zero() @test //=> @pool()
{
	String path = write_fixture("fv_p0", `module fv;
fn void empty_params() {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("fv", "empty_params")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	assert(fv.params().count() == 0, "zero params");
}

fn void test_fn_view_param_count_two() @test //=> @pool()
{
	String path = write_fixture("fv_p2", `module fv;
fn void add(int x, int y) {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("fv", "add")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	assert(fv.params().count() == 2, "two params");
}

fn void test_fn_view_param_names() @test //=> @pool()
{
	String path = write_fixture("fv_pnames", `module fv;
fn int sub(int a, int b) { return a; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("fv", "sub")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	ParamView p0 = fv.params().get_param(0);
	ParamView p1 = fv.params().get_param(1);
	assert(p0.name(&ws.strings) == "a", "first param 'a'");
	assert(p1.name(&ws.strings) == "b", "second param 'b'");
}

fn void test_fn_view_body_valid() @test //=> @pool()
{
	String path = write_fixture("fv_body", `module fv;
fn void has_body() { int x = 0; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("fv", "has_body")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	Node body = fv.body();
	assert(body.is_valid(), "body is valid");
	assert(ast.get_kind(body) == NodeKind.COMPOUND_STMT, "body is COMPOUND_STMT");
}

fn void test_fn_view_no_body() @test //=> @pool()
{
	String path = write_fixture("fv_nobody", `module fv;
extern fn void c_fn();
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("fv", "c_fn")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	assert(!fv.body().is_valid(), "extern fn has no body");
}

// ============================================================
// ParamView
// ============================================================

fn void test_param_view_type_name() @test //=> @pool()
{
	String path = write_fixture("pv_type", `module pv;
fn void scale(float f) {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("pv", "scale")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	ParamView pv = fv.params().get_param(0);
	TypeView tv = { ast, pv.type_node() };
	assert(tv.name(&ws.strings) == "float", "param type is float");
}

fn void test_param_view_ptr_type() @test //=> @pool()
{
	String path = write_fixture("pv_ptr", `module pv;
fn void ptr_param(int* p) {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("pv", "ptr_param")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	ParamView pv = fv.params().get_param(0);
	TypeView tv = { ast, pv.type_node() };
	assert(tv.name(&ws.strings) == "int", "ptr base type is int");
	assert(tv.ptr_count() == 1, "one pointer level");
}

// ============================================================
// VarDeclView
// ============================================================

fn void test_var_decl_view_name() @test //=> @pool()
{
	String path = write_fixture("vd_name", `module vd;
const int LIMIT = 10;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("vd", "LIMIT")!!;
	Ast* ast = &c.section.source_file.ast;
	VarDeclView vv = { ast, c.node };
	assert(vv.name(&ws.strings) == "LIMIT", "VarDeclView.name");
}

fn void test_var_decl_view_is_const() @test //=> @pool()
{
	String path = write_fixture("vd_const", `module vd;
const int X = 99;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("vd", "X")!!;
	Ast* ast = &c.section.source_file.ast;
	VarDeclView vv = { ast, c.node };
	assert(vv.is_const(), "should be const");
	assert(!vv.is_extern(), "should not be extern");
	assert(!vv.is_thread_local(), "should not be thread_local");
}

fn void test_var_decl_view_is_global() @test //=> @pool()
{
	String path = write_fixture("vd_global", `module vd;
int counter;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("vd", "counter")!!;
	Ast* ast = &c.section.source_file.ast;
	VarDeclView vv = { ast, c.node };
	assert(vv.is_global(), "should be global");
	assert(!vv.is_const(), "should not be const");
	assert(!vv.is_local(), "should not be local");
}

fn void test_var_decl_view_is_thread_local() @test //=> @pool()
{
	String path = write_fixture("vd_tlocal", `module vd;
tlocal int tid;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("vd", "tid")!!;
	Ast* ast = &c.section.source_file.ast;
	VarDeclView vv = { ast, c.node };
	assert(vv.is_thread_local(), "should be thread_local");
}

fn void test_var_decl_view_type_node() @test //=> @pool()
{
	String path = write_fixture("vd_type", `module vd;
const long BIG = 9999;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("vd", "BIG")!!;
	Ast* ast = &c.section.source_file.ast;
	VarDeclView vv = { ast, c.node };
	TypeView tv = { ast, vv.type_node() };
	assert(tv.name(&ws.strings) == "long", "const type is long");
}

fn void test_var_decl_view_init_expr() @test //=> @pool()
{
	String path = write_fixture("vd_init", `module vd;
const int ANSWER = 42;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("vd", "ANSWER")!!;
	Ast* ast = &c.section.source_file.ast;
	VarDeclView vv = { ast, c.node };
	Node init = vv.init_expr();
	assert(init.is_valid(), "init_expr must be valid");
	assert(ast.get_kind(init) == NodeKind.INT_LITERAL, "init is INT_LITERAL");
}

// ============================================================
// StructView / FieldView
// ============================================================

fn void test_struct_view_name_accessor() @test //=> @pool()
{
	String path = write_fixture("sv_name", `module sv;
struct Rect { int x; int y; int w; int h; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("sv", "Rect")!!;
	Ast* ast = &c.section.source_file.ast;
	StructView sv = { ast, c.node };
	assert(sv.name(&ws.strings) == "Rect", "StructView.name");
}

fn void test_struct_view_field_count() @test //=> @pool()
{
	String path = write_fixture("sv_fcount", `module sv;
struct Vec3 { float x; float y; float z; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("sv", "Vec3")!!;
	Ast* ast = &c.section.source_file.ast;
	StructView sv = { ast, c.node };
	assert(sv.field_count() == 3, "Vec3 has 3 fields");
}

fn void test_field_view_name() @test //=> @pool()
{
	String path = write_fixture("fv_fname", `module sv;
struct Pair { int first; int second; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("sv", "Pair")!!;
	Ast* ast = &c.section.source_file.ast;
	StructView sv = { ast, c.node };
	FieldView f0 = { ast, sv.field(0) };
	FieldView f1 = { ast, sv.field(1) };
	assert(f0.name(&ws.strings) == "first", "field 0 name");
	assert(f1.name(&ws.strings) == "second", "field 1 name");
}

fn void test_field_view_type() @test //=> @pool()
{
	String path = write_fixture("fv_ftype", `module sv;
struct Coord { double lat; double lon; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("sv", "Coord")!!;
	Ast* ast = &c.section.source_file.ast;
	StructView sv = { ast, c.node };
	FieldView f = { ast, sv.field(0) };
	TypeView tv = { ast, f.type_node() };
	assert(tv.name(&ws.strings) == "double", "field type is double");
}

fn void test_struct_view_empty() @test //=> @pool()
{
	String path = write_fixture("sv_empty", `module sv;
struct Empty {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("sv", "Empty")!!;
	Ast* ast = &c.section.source_file.ast;
	StructView sv = { ast, c.node };
	assert(sv.field_count() == 0, "empty struct has 0 fields");
}

// ============================================================
// EnumView
// ============================================================

fn void test_enum_view_member_count() @test //=> @pool()
{
	String path = write_fixture("ev_count", `module ev;
enum Color { RED, GREEN, BLUE }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("ev")!!;
	ModuleSection* sec = mod.sections[0];
	Node n = first_node_of_kind(sec, NodeKind.ENUM_DECL);
	assert(n.is_valid(), "should have ENUM_DECL");
	EnumView ev = { &sec.source_file.ast, n };
	assert(ev.member_count() == 3, "Color has 3 members");
}

fn void test_enum_view_member_kind() @test //=> @pool()
{
	String path = write_fixture("ev_mtype", `module ev;
enum Dir { NORTH, SOUTH, EAST, WEST }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("ev")!!;
	ModuleSection* sec = mod.sections[0];
	Ast* ast = &sec.source_file.ast;
	Node n = first_node_of_kind(sec, NodeKind.ENUM_DECL);
	EnumView ev = { ast, n };
	assert(ev.member_count() == 4, "Dir has 4 members");
	Node m0 = ev.get_member(0);
	assert(m0.is_valid(), "first member is valid");
	assert(ast.get_kind(m0) == NodeKind.ENUM_MEMBER, "member is ENUM_MEMBER");
}

fn void test_enum_view_is_constdef() @test //=> @pool()
{
	String path = write_fixture("ev_constdef", `module ev;
constdef Flags { A, B, C }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("ev")!!;
	ModuleSection* sec = mod.sections[0];
	Node n = first_node_of_kind(sec, NodeKind.ENUM_DECL);
	EnumView ev = { &sec.source_file.ast, n };
	assert(ev.is_const_def(), "constdef sets is_const_def");
}

fn void test_enum_view_is_not_constdef() @test //=> @pool()
{
	String path = write_fixture("ev_nonconstdef", `module ev;
enum Normal { X, Y }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("ev")!!;
	ModuleSection* sec = mod.sections[0];
	Node n = first_node_of_kind(sec, NodeKind.ENUM_DECL);
	EnumView ev = { &sec.source_file.ast, n };
	assert(!ev.is_const_def(), "regular enum is not constdef");
}

// ============================================================
// TypedefView
// ============================================================

fn void test_typedef_view_name() @test //=> @pool()
{
	String path = write_fixture("td_name", `module td;
typedef MyInt = int;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("td")!!;
	ModuleSection* sec = mod.sections[0];
	Node n = first_node_of_kind(sec, NodeKind.TYPEDEF_DECL);
	assert(n.is_valid(), "should have TYPEDEF_DECL");
	TypedefView tv = { &sec.source_file.ast, n };
	assert(tv.name(&ws.strings) == "MyInt", "typedef name");
}

fn void test_typedef_view_base_type() @test //=> @pool()
{
	String path = write_fixture("td_base", `module td;
typedef Sz = ulong;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("td")!!;
	ModuleSection* sec = mod.sections[0];
	Ast* ast = &sec.source_file.ast;
	Node n = first_node_of_kind(sec, NodeKind.TYPEDEF_DECL);
	TypedefView tv = { ast, n };
	Node base = tv.base_type();
	assert(base.is_valid(), "base_type is valid");
	TypeView btv = { ast, base };
	assert(btv.name(&ws.strings) == "ulong", "base_type is ulong");
}

// ============================================================
// TypeView
// ============================================================

fn void test_type_view_ptr_count_one() @test //=> @pool()
{
	String path = write_fixture("tv_ptr1", `module tv;
fn void f(int* p) {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("tv", "f")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	ParamView pv = fv.params().get_param(0);
	TypeView tv = { ast, pv.type_node() };
	assert(tv.ptr_count() == 1, "one pointer level");
}

fn void test_type_view_ptr_count_two() @test //=> @pool()
{
	String path = write_fixture("tv_ptr2", `module tv;
fn void f(char** pp) {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("tv", "f")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	ParamView pv = fv.params().get_param(0);
	TypeView tv = { ast, pv.type_node() };
	assert(tv.ptr_count() == 2, "two pointer levels");
}

fn void test_type_view_no_generics() @test //=> @pool()
{
	String path = write_fixture("tv_nogen", `module tv;
fn void f(int x) {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("tv", "f")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	ParamView pv = fv.params().get_param(0);
	TypeView tv = { ast, pv.type_node() };
	assert(tv.gen_count() == 0, "plain int has no generic args");
}

// ============================================================
// PathView
// ============================================================

fn void test_path_view_single_segment() @test //=> @pool()
{
	String path = write_fixture("pv_single", `module pv;
import foo;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("pv")!!;
	ModuleSection* sec = mod.sections[0];
	Ast* ast = &sec.source_file.ast;
	Node imp = first_node_of_kind(sec, NodeKind.IMPORT_DECL);
	assert(imp.is_valid(), "IMPORT_DECL present");
	ImportView iv = { ast, imp };
	PathView pv = { ast, iv.path() };
	assert(pv.len() == 1, "single-segment path");
	assert(pv.get_full(&ws.strings) == "foo", "path text is 'foo'");
}

fn void test_path_view_three_segments() @test //=> @pool()
{
	String path = write_fixture("pv_three", `module pv;
import a::b::c;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("pv")!!;
	ModuleSection* sec = mod.sections[0];
	Ast* ast = &sec.source_file.ast;
	Node imp = first_node_of_kind(sec, NodeKind.IMPORT_DECL);
	ImportView iv = { ast, imp };
	PathView pv = { ast, iv.path() };
	assert(pv.len() == 3, "three-segment path");
	assert(pv.get_text(0, &ws.strings) == "a", "segment 0");
	assert(pv.get_text(1, &ws.strings) == "b", "segment 1");
	assert(pv.get_text(2, &ws.strings) == "c", "segment 2");
	assert(pv.get_full(&ws.strings) == "a::b::c", "full path");
}

// ============================================================
// ModuleView
// ============================================================

fn void test_module_view_path() @test //=> @pool()
{
	String path = write_fixture("mv_path", `module app::core;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("app::core")!!;
	ModuleSection* sec = mod.sections[0];
	Ast* ast = &sec.source_file.ast;
	Node mn = first_node_of_kind(sec, NodeKind.MODULE_DECL);
	assert(mn.is_valid(), "MODULE_DECL present");
	ModuleView mv = { ast, mn };
	PathView pv = { ast, mv.path() };
	assert(pv.get_full(&ws.strings) == "app::core", "module path");
}

fn void test_module_view_not_generic() @test //=> @pool()
{
	String path = write_fixture("mv_nogen", `module simple;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("simple")!!;
	ModuleSection* sec = mod.sections[0];
	Ast* ast = &sec.source_file.ast;
	Node mn = first_node_of_kind(sec, NodeKind.MODULE_DECL);
	ModuleView mv = { ast, mn };
	assert(!mv.is_generic(), "plain module is not generic");
}

// ============================================================
// ImportView
// ============================================================

fn void test_import_view_path() @test //=> @pool()
{
	String path = write_fixture("iv_path", `module iv;
import std::io;
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Module* mod = ws.modules.get("iv")!!;
	ModuleSection* sec = mod.sections[0];
	Ast* ast = &sec.source_file.ast;
	Node imp = first_node_of_kind(sec, NodeKind.IMPORT_DECL);
	ImportView iv = { ast, imp };
	PathView pv = { ast, iv.path() };
	assert(pv.get_full(&ws.strings) == "std::io", "import path std::io");
}

// ============================================================
// CompoundView
// ============================================================

fn void test_compound_view_len() @test //=> @pool()
{
	String path = write_fixture("cv_len", `module cv;
fn void three() { int a = 1; int b = 2; int c = 3; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("cv", "three")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 3, "compound has 3 stmts");
}

fn void test_compound_view_get_kind() @test //=> @pool()
{
	String path = write_fixture("cv_get", `module cv;
fn void two() { int x = 1; int y = 2; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("cv", "two")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	Node s0 = cv.get(0);
	Node s1 = cv.get(1);
	assert(s0.is_valid() && s1.is_valid(), "both stmts valid");
	assert(ast.get_kind(s0) == NodeKind.LOCAL_DECL, "stmt 0 is LOCAL_DECL");
	assert(ast.get_kind(s1) == NodeKind.LOCAL_DECL, "stmt 1 is LOCAL_DECL");
}

fn void test_compound_view_empty() @test //=> @pool()
{
	String path = write_fixture("cv_empty", `module cv;
fn void empty_body() {}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("cv", "empty_body")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 0, "empty compound has 0 stmts");
}

// ============================================================
// ReturnView
// ============================================================

fn void test_return_view_expr_valid() @test //=> @pool()
{
	String path = write_fixture("rv_expr", `module rv;
fn int get() { return 7; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("rv", "get")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	Node ret = cv.get(0);
	assert(ast.get_kind(ret) == NodeKind.RETURN_STMT, "is RETURN_STMT");
	ReturnView rv = { ast, ret };
	assert(rv.expr().is_valid(), "return expr is valid");
}

fn void test_return_view_expr_kind() @test //=> @pool()
{
	String path = write_fixture("rv_kind", `module rv;
fn int lit_ret() { return 99; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("rv", "lit_ret")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	assert(ast.get_kind(rv.expr()) == NodeKind.INT_LITERAL, "return expr is INT_LITERAL");
}

// ============================================================
// LiteralView
// ============================================================

fn void test_literal_view_int_value() @test //=> @pool()
{
	String path = write_fixture("lv_int", `module lv;
fn int answer() { return 42; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("lv", "answer")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	LiteralView lv = { ast, rv.expr() };
	assert(lv.value(&ws.strings) == "42", "literal value is '42'");
}

fn void test_literal_view_float_value() @test //=> @pool()
{
	String path = write_fixture("lv_float", `module lv;
fn float pi_approx() { return 3.14; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("lv", "pi_approx")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	Node expr = rv.expr();
	assert(ast.get_kind(expr) == NodeKind.FLOAT_LITERAL, "is FLOAT_LITERAL");
	LiteralView lv = { ast, expr };
	assert(lv.value(&ws.strings) == "3.14", "float literal value");
}

// ============================================================
// IdentView
// ============================================================

fn void test_ident_view_name() @test //=> @pool()
{
	String path = write_fixture("iv_ident", `module iv;
fn int passthrough(int val) { return val; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("iv", "passthrough")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	Node expr = rv.expr();
	assert(ast.get_kind(expr) == NodeKind.IDENT_EXPR, "is IDENT_EXPR");
	IdentView iv = { ast, expr };
	assert(iv.name(&ws.strings) == "val", "ident name is 'val'");
}

// ============================================================
// BinaryView
// ============================================================

fn void test_binary_view_add_op() @test //=> @pool()
{
	String path = write_fixture("bv_add", `module bv;
fn int sum(int a, int b) { return a + b; }
`);
	Workspace ws; 
	ws.init();
	defer ws.free();

	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("bv", "sum")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	Node expr = rv.expr();
	assert(ast.get_kind(expr) == NodeKind.BINARY_EXPR, "is BINARY_EXPR");
	BinaryView bv = { ast, expr };
	assert(bv.op() == TokenKind.PLUS, "op is PLUS");
	assert(bv.left().is_valid(), "left operand valid");
	assert(bv.right().is_valid(), "right operand valid");
}

fn void test_binary_view_mul_op() @test //=> @pool()
{
	String path = write_fixture("bv_mul", `module bv;
fn int product(int a, int b) { return a * b; }
`);
	Workspace ws; 
	ws.init();
	defer ws.free();

	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("bv", "product")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	BinaryView bv = { ast, rv.expr() };
	assert(bv.op() == TokenKind.ASTERISK, "op is ASTERISK (multiply)");
}

fn void test_binary_view_operand_kinds() @test //=> @pool()
{
	String path = write_fixture("bv_ops", `module bv;
fn int inc(int n) { return n + 1; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("bv", "inc")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	BinaryView bv = { ast, rv.expr() };
	assert(ast.get_kind(bv.left()) == NodeKind.IDENT_EXPR, "left is IDENT_EXPR");
	assert(ast.get_kind(bv.right()) == NodeKind.INT_LITERAL, "right is INT_LITERAL");
}

// ============================================================
// UnaryView
// ============================================================

fn void test_unary_view_negate() @test //=> @pool()
{
	String path = write_fixture("uv_neg", `module uv;
fn int neg(int x) { return -x; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("uv", "neg")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	Node expr = rv.expr();
	assert(ast.get_kind(expr) == NodeKind.UNARY_EXPR, "is UNARY_EXPR");
	UnaryView uv = { ast, expr };
	assert(uv.op() == TokenKind.MINUS, "unary op is MINUS");
	assert(uv.rhs().is_valid(), "rhs is valid");
	assert(ast.get_kind(uv.rhs()) == NodeKind.IDENT_EXPR, "rhs is IDENT_EXPR");
}

fn void test_unary_view_not() @test //=> @pool()
{
	String path = write_fixture("uv_not", `module uv;
fn bool flip(bool b) { return !b; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("uv", "flip")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	UnaryView uv = { ast, rv.expr() };
	assert(uv.op() == TokenKind.BANG, "unary op is BANG");
}

// ============================================================
// IfView
// ============================================================

fn void test_if_view_all_branches() @test //=> @pool()
{
	String path = write_fixture("ifv_full", `module ifv;
fn void branch(bool b) {
	if (b) { int x = 1; } else { int y = 2; }
}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("ifv", "branch")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	Node if_stmt = cv.get(0);
	assert(ast.get_kind(if_stmt) == NodeKind.IF_STMT, "is IF_STMT");
	IfView iv = { ast, if_stmt };
	assert(iv.condition().is_valid(), "condition valid");
	assert(iv.then_block().is_valid(), "then_block valid");
	assert(iv.else_block().is_valid(), "else_block valid");
}

fn void test_if_view_no_else() @test //=> @pool()
{
	String path = write_fixture("ifv_noelse", `module ifv;
fn void maybe(bool b) {
	if (b) { int z = 0; }
}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("ifv", "maybe")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	IfView iv = { ast, cv.get(0) };
	assert(!iv.else_block().is_valid(), "no else block");
}

fn void test_if_view_condition_kind() @test //=> @pool()
{
	String path = write_fixture("ifv_cond", `module ifv;
fn void test(bool flag) {
	if (flag) {}
}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("ifv", "test")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	IfView iv = { ast, cv.get(0) };
	io::printn(ast.get_kind(iv.condition()));
	assert(ast.get_kind(iv.condition()) == NodeKind.COND_EXPR, "condition is COND_EXPR");
}

// ============================================================
// ForView
// ============================================================

fn void test_for_view_all_parts() @test //=> @pool()
{
	String path = write_fixture("forv_all", `module forv;
fn void loop() {
	for (int i = 0; i < 10; i++) {}
}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("forv", "loop")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	Node for_stmt = cv.get(0);
	assert(ast.get_kind(for_stmt) == NodeKind.FOR_STMT, "is FOR_STMT");
	ForView fov = { ast, for_stmt };
	assert(fov.init().is_valid(), "for init valid");
	assert(fov.cond().is_valid(), "for cond valid");
	assert(fov.inc().is_valid(), "for inc valid");
	assert(fov.body().is_valid(), "for body valid");
}

fn void test_for_view_body_kind() @test //=> @pool()
{
	String path = write_fixture("forv_body", `module forv;
fn void loop2() {
	for (int j = 0; j < 5; j++) { int k = j; }
}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("forv", "loop2")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ForView fov = { ast, cv.get(0) };
	assert(ast.get_kind(fov.body()) == NodeKind.COMPOUND_STMT, "for body is COMPOUND_STMT");
}

// ============================================================
// TernaryView
// ============================================================

fn void test_ternary_view_parts() @test //=> @pool()
{
	String path = write_fixture("tv_tern", `module tv;
fn int pick(bool cond) { return cond ? 1 : 2; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("tv", "pick")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	Node expr = rv.expr();
	assert(ast.get_kind(expr) == NodeKind.TERNARY_EXPR, "is TERNARY_EXPR");
	TernaryView tv = { ast, expr };
	assert(tv.condition().is_valid(), "ternary condition valid");
	assert(tv.then_expr().is_valid(), "ternary then_expr valid");
	assert(tv.else_expr().is_valid(), "ternary else_expr valid");
}

fn void test_ternary_view_operand_kinds() @test //=> @pool()
{
	String path = write_fixture("tv_tern2", `module tv;
fn int choose(bool b) { return b ? 10 : 20; }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("tv", "choose")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ReturnView rv = { ast, cv.get(0) };
	TernaryView tv = { ast, rv.expr() };
	assert(ast.get_kind(tv.condition()) == NodeKind.IDENT_EXPR, "condition is IDENT_EXPR");
	assert(ast.get_kind(tv.then_expr()) == NodeKind.INT_LITERAL, "then_expr is INT_LITERAL");
	assert(ast.get_kind(tv.else_expr()) == NodeKind.INT_LITERAL, "else_expr is INT_LITERAL");
}

// ============================================================
// ExprStmtView
// ============================================================

fn void test_expr_stmt_view_expr() @test //=> @pool()
{
	String path = write_fixture("esv_expr", `module esv;
fn void call_it() { do_work(); }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("esv", "call_it")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	Node stmt = cv.get(0);
	assert(ast.get_kind(stmt) == NodeKind.EXPR_STMT, "is EXPR_STMT");
	ExprStmtView ev = { ast, stmt };
	assert(ev.expr().is_valid(), "inner expr is valid");
}

fn void test_expr_stmt_view_inner_kind() @test //=> @pool()
{
	String path = write_fixture("esv_kind", `module esv;
fn void caller2() { some_fn(); }
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("esv", "caller2")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	ExprStmtView ev = { ast, cv.get(0) };
	assert(ast.get_kind(ev.expr()) == NodeKind.CALL_EXPR, "inner expr is CALL_EXPR");
}

// ============================================================
// DeferView
// ============================================================

fn void test_defer_view_normal_kind() @test //=> @pool()
{
	String path = write_fixture("dv_normal", `module dv;
fn void with_defer() {
	defer { int x = 0; }
}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("dv", "with_defer")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	Node defer_stmt = cv.get(0);
	assert(ast.get_kind(defer_stmt) == NodeKind.DEFER_STMT, "is DEFER_STMT");
	DeferView dv = { ast, defer_stmt };
	assert(dv.kind() == DeferKind.NORMAL, "defer kind is NORMAL");
	assert(dv.stmt().is_valid(), "deferred stmt is valid");
}

fn void test_defer_view_stmt_is_compound() @test //=> @pool()
{
	String path = write_fixture("dv_compound", `module dv;
fn void block_defer() {
	defer { int y = 1; int z = 2; }
}
`);
	Workspace ws; ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;
	Cursor c = ws.lookup("dv", "block_defer")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	DeferView dv = { ast, cv.get(0) };
	assert(ast.get_kind(dv.stmt()) == NodeKind.COMPOUND_STMT, "deferred stmt is COMPOUND_STMT");
}
