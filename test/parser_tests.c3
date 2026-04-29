module c3_parser_tests;

import c3_parser::workspace;
import c3_parser::parser;
import c3_parser::cursor;
import c3_parser::ast;
import c3_parser::common;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

// ------------------------------------------------------------
// Helpers
// ------------------------------------------------------------

<*
 Write a C3 source string to a named temp file under /tmp/ and
  return the path.  Panics on I/O failure so tests fail fast.
*>
fn String write_fixture(String name, String content) @private
{
	String path = string::tformat("%s/c3_test_%s.c3", path::temp_directory(tmem)!!, name);
	File f = file::open(path, "w")!!;
	f.write(content)!!;
	(void)f.close()!!;
	return path;
}

<*
 Count how many top-level nodes in a section have a given kind.
*>
fn uint count_kind(ModuleSection* s, NodeKind kind) @private
{
	uint n = 0;
	foreach (h : s.source_file.ast.top_level_nodes)
	{
		if (h < s.start_node_idx || h >= s.end_node_idx) continue;
		if (ast::get_kind(&s.source_file.ast, (Node)h) == kind) n++;
	}
	return n;
}

// ------------------------------------------------------------
// 1. Basic module declaration
// ------------------------------------------------------------
<*
 A file with an explicit module header produces exactly one module
  with the declared name and one section.
*>
fn void test_basic_module() @test => @pool()
{
	String path = write_fixture("basic", `module hello;
fn void greet() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	assert (ws.modules.len() == 1 , "Expected exactly one module");

	Module* mod = ws.modules.get("hello")!!;
	assert (mod != null , "Module 'hello' not found");
	assert (mod.name == "hello" , "Module name mismatch");
	assert (mod.sections.len() == 1 , "Expected one section");

	// MODULE_DECL + FN_DECL
	ModuleSection* s = mod.sections[0];
	io::printfn("%s", string::from_struct(tmem, s.source_file.ast));
	io::printfn("%s", s.start_node_idx);
	// assert(s.source_file.ast.top_level_nodes.len() == 2, "Expected 2 top-level nodes");
	assert (count_kind(s, NodeKind.MODULE_DECL) == 1 , "Expected MODULE_DECL");
	assert (count_kind(s, NodeKind.FN_DECL) == 1 , "Expected FN_DECL");
}

// ------------------------------------------------------------
// 2. Module name inferred from the file path
// ------------------------------------------------------------
<*
 When there is no module declaration the module name is derived
  from the basename (strip ".c3").
*>
fn void test_module_name_inferred_from_path() @test => @pool()
{
	// write_fixture always produces /tmp/c3_test_<name>.c3
	// so the inferred module name will be "c3_test_infer_me"
	String path = write_fixture("infer_me", `fn void standalone() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	assert (ws.modules.len() == 1 , "Expected one inferred module");

	Module* mod = ws.modules.get("c3_test_infer_me")!!;
	assert (mod != null , "Inferred module 'c3_test_infer_me' not found");
}

// ------------------------------------------------------------
// 3. Function declaration with parameters
// ------------------------------------------------------------
<*
 A function declaration is accessible via workspace.lookup and
  exposes its parameter count through FnView.
*>
fn void test_fn_decl_with_params() @test => @pool()
{
	String path = write_fixture("fn_params", `module fn_mod;
fn int add(int a, int b) {
  return a + b;
}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Cursor fn_cur = ws.lookup("fn_mod", "add")!!;
	assert (ast::get_kind(&fn_cur.section.source_file.ast, fn_cur.node) == NodeKind.FN_DECL , "Node is not FN_DECL");

	FnView v = { &fn_cur.section.source_file.ast, fn_cur.node };
	assert (v.param_count() == 2 , "Expected 2 parameters");
}

// ------------------------------------------------------------
// 4. Struct declaration
// ------------------------------------------------------------
<*
 A struct declaration is accessible by name and reports the
  correct field count.
*>
fn void test_struct_decl() @test => @pool()
{
	String path = write_fixture("struct", `module struct_mod;
struct Point {
  float x;
  float y;
}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Cursor sc = ws.lookup("struct_mod", "Point")!!;
	assert (ast::get_kind(&sc.section.source_file.ast, sc.node) == NodeKind.STRUCT_DECL , "Node is not STRUCT_DECL");

	StructView sv = { &sc.section.source_file.ast, sc.node };
	assert (sv.field_count() == 2 , "Expected 2 fields in Point");
}

// ------------------------------------------------------------
// 5. Import declarations are recorded as top-level nodes
// ------------------------------------------------------------
<*
 Every import statement produces an IMPORT_DECL top-level node.
*>
fn void test_import_decl() @test => @pool()
{
	String path = write_fixture("imports", `module imp_mod;
import std::io;
import std::math;
fn void use_them() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("imp_mod")!!;
	ModuleSection* s = mod.sections[0];

	// MODULE_DECL + 2×IMPORT_DECL + FN_DECL = 4
	assert (s.top_level_nodes().len() == 4 , "Expected 4 top-level nodes");
	assert (count_kind(s, NodeKind.IMPORT_DECL) == 2 , "Expected 2 IMPORT_DECLs");
}

// ------------------------------------------------------------
// 6. Const declaration
// ------------------------------------------------------------
<*
 A const declaration is accessible by name.
*>
fn void test_const_decl() @test => @pool()
{
	String path = write_fixture("const", `module const_mod;
const int MAX_SIZE = 100;
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Cursor cc = ws.lookup("const_mod", "MAX_SIZE")!!;
	// CONST_DECL is stored as a GLOBAL_DECL with a const flag
	NodeKind k = ast::get_kind(&cc.section.source_file.ast, cc.node);
	assert (k == NodeKind.GLOBAL_DECL || k == NodeKind.CONST_DECL , "Expected GLOBAL_DECL or CONST_DECL for const");
}

// ------------------------------------------------------------
// 7. workspace::lookup — found and not-found cases
// ------------------------------------------------------------
<*
lookup returns a valid Cursor for known symbols, and a fault for
missing symbols or missing modules.
*>
fn void test_workspace_lookup() @test => @pool()
{
	String path = write_fixture("lookup", `module lu_mod;
fn void target() {}
struct Target {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	// Existing function
	Cursor fn_cur = ws.lookup("lu_mod", "target")!!;
	assert(ast::get_kind(&fn_cur.section.source_file.ast, fn_cur.node) == NodeKind.FN_DECL,
	"'target' is not FN_DECL");

	// Existing struct
	Cursor st_cur = ws.lookup("lu_mod", "Target")!!;
	assert(ast::get_kind(&st_cur.section.source_file.ast, st_cur.node) == NodeKind.STRUCT_DECL,
	"'Target' is not STRUCT_DECL");

	// Non-existent symbol → fault
	if (try found_sym = ws.lookup("lu_mod", "no_such_symbol"))
	{
		assert(false, "Expected fault for missing symbol, got a cursor for node %d",
		(uint)found_sym.node);
	}

	// Non-existent module → fault
	if (try found_mod = ws.lookup("no_such_mod", "target"))
	{
		assert(false, "Expected fault for missing module, got a cursor for node %d",
		(uint)found_mod.node);
	}
}

// ------------------------------------------------------------
// 8. cursor::spelling
// ------------------------------------------------------------
<*
cursor::spelling returns the declared name for FN_DECL and
STRUCT_DECL nodes.
*>
fn void test_cursor_spelling() @test => @pool()
{
	String path = write_fixture("spell", `module spell_mod;
fn void spelled_func() {}
struct WellNamed {
int a;
}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Cursor fc = ws.lookup("spell_mod", "spelled_func")!!;
	assert(fc.spelling()!! == "spelled_func",
	"Spelling of function is wrong");

	Cursor sc = ws.lookup("spell_mod", "WellNamed")!!;
	assert(sc.spelling()!! == "WellNamed",
	"Spelling of struct is wrong");
}

// ------------------------------------------------------------
// 9. cursor::source_text
// ------------------------------------------------------------
<*
cursor::source_text returns a slice of the original source that
contains at least the declared name.
*>
fn void test_cursor_source_text() @test => @pool()
{
	String path = write_fixture("srctext", `module srctext_mod;
fn void my_unique_function() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Cursor fc = ws.lookup("srctext_mod", "my_unique_function")!!;
	String text = fc.source_text();
	assert(text.len > 0,                         "source_text returned empty string");
	assert(text.contains("my_unique_function"),  "source_text does not contain the function name");
}

// ------------------------------------------------------------
// 10. find_section_by_path
// ------------------------------------------------------------
<*
find_section_by_path locates the ModuleSection for a known path
and returns null for an unknown path.
*>
fn void test_find_section_by_path() @test => @pool()
{
	String path = write_fixture("pathfind", `module pf_mod;
fn void located() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	List{ModuleSection*} s = ws.find_section_by_path(path);
	assert(s.len() > 0, "Section not found for known path");
	assert(s[0].source_file.file_path == path, "Section has wrong file_path");

	List{ModuleSection*} missing = ws.find_section_by_path("/no/such/file.c3");
	assert(missing.len() == 0, "Expected null for unknown path");
}

// ------------------------------------------------------------
// 11. find_at_location
// ------------------------------------------------------------
<*
find_at_location returns a valid cursor when the location falls
inside a known declaration, and an invalid cursor otherwise.
*>
fn void test_find_at_location() @test => @pool()
{
	// "fn void findme() {}" begins at line 2, column 1
	String path = write_fixture("location", `module loc_mod;
fn void findme() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Location fn_loc = { .line = 2, .column = 1 };
	Cursor c = ws.find_at_location(path, fn_loc);
	assert(c.node.is_valid(), "Expected a valid cursor at (2,1)");

	// Way off the end of the file
	Location far = { .line = 999, .column = 1 };
	Cursor c2 = ws.find_at_location(path, far);
	assert(!c2.node.is_valid(), "Expected invalid cursor for out-of-bounds location");
}

// ------------------------------------------------------------
// 12. SourceFile back-references
// ------------------------------------------------------------
<*
After parsing, the ModuleSection's source_file pointer points back
to the SourceFile, and the SourceFile's sections list contains that
same section.
*>
fn void test_source_file_back_references() @test => @pool()
{
	String path = write_fixture("backref", `module br_mod;
fn void ref_func() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("br_mod")!!;
	ModuleSection* s = mod.sections[0];

	assert(s.source_file != null,                 "source_file back-reference is null");
	assert(s.source_file.file_path == path,        "source_file has wrong path");
	assert(s.source_file.sections.len() == 1,      "SourceFile should list exactly one section");
	assert(s.source_file.sections[0] == s,         "SourceFile does not list its own section");
}

// ------------------------------------------------------------
// 13. Incremental: two different files, same module name
// ------------------------------------------------------------
<*
When two source files both declare the same module, their content
is merged into one Module with two sections, and symbols from both
files are reachable via workspace::lookup.
*>
fn void test_multi_file_same_module() @test => @pool()
{
	String path1 = write_fixture("mf_a", `module shared_mod;
fn void foo() {}
`);
	String path2 = write_fixture("mf_b", `module shared_mod;
fn void bar() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path1)!!;
	parser::parse_file(&ws, path2)!!;

	assert(ws.modules.len() == 1,  "Expected exactly one merged module");

	Module* mod = ws.modules.get("shared_mod")!!;
	assert(mod.sections.len() == 2, "Expected two sections for two files");

	if (catch e = ws.lookup("shared_mod", "foo"))
	{
		assert(false, "'foo' not found after multi-file parse: %s", e);
	}

	if (catch e = ws.lookup("shared_mod", "bar"))
	{
		assert(false, "'bar' not found after multi-file parse: %s", e);
	}
}

// ------------------------------------------------------------
// 14. Incremental: parsing the same file path twice is idempotent
// ------------------------------------------------------------
<*
The workspace caches SourceFile by path.  Calling parse_file twice
on the same path reuses the same SourceFile and the same
ModuleSection (get_or_create_section detects the duplicate).
The module must still have exactly one section after the second call,
and symbol lookup must still work.

NOTE: With the current implementation the section IS reused, but
parsing continues to append nodes into it — so the top-level node
list grows.  This test documents that behaviour; a fully-implemented
incremental parser would keep node count stable.
*>
fn void test_reparse_same_file() @test => @pool()
{
	String path = write_fixture("reparse", `module rp_mod;
fn void only_once() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("rp_mod")!!;

	// Baseline after first parse
	assert(mod.sections.len() == 1, "Expected 1 section after first parse");
	uint nodes_after_first = (uint)mod.sections[0].top_level_nodes().len();
	assert(nodes_after_first >= 1, "Expected at least one top-level node");

	// Parse again — same path, same SourceFile, same section is returned
	parser::parse_file(&ws, path)!!;

	// The module must not gain a new section
	assert(mod.sections.len() == 1, "Section count grew - section was not reused");

	// Symbol lookup must still work
	if (catch e = ws.lookup("rp_mod", "only_once"))
	{
		assert(false, "Symbol 'only_once' not found after re-parse: %s", e);
	}
}

// ------------------------------------------------------------
// 15. Error recovery: valid declarations survive a syntax error
// ------------------------------------------------------------
<*
When the parser hits a declaration it cannot parse, synchronize()
skips ahead to the next top-level keyword.  Valid declarations
before and after the error must still be recorded.
*>
fn void test_error_recovery() @test => @pool()
{
	// "return;" is valid C3 but illegal at the top level — the parser will fail
	// on it, call synchronize(), then resume at the next top-level keyword.
	String path = write_fixture("recovery", `module rec_mod;
fn void good_before() {}
return;
fn void good_after() {}
`);

	Workspace ws;
	ws.init();
	// parse_file should NOT propagate a fatal error — recovery handles it
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("rec_mod")!!;
	assert(mod != null, "Module not created despite error recovery");

	// Both well-formed functions should be present
	if (catch e = ws.lookup("rec_mod", "good_before"))
	{
		assert(false, "'good_before' missing - was it dropped by error recovery?: %s", e);
	}

	if (catch e = ws.lookup("rec_mod", "good_after"))
	{
		assert(false, "'good_after' missing - error recovery did not resume: %s", e);
	}
}

// ------------------------------------------------------------
// 16. All module names are registered in the workspace
// ------------------------------------------------------------
<*
A file with two module headers produces exactly one entry in
ws.modules — the first one.  The second module name is not
visible to workspace::lookup until the parser properly switches
sections mid-file.
*>
fn void test_multi_module_in_workspace() @test => @pool()
{
	String path = write_fixture("mm_first", `module alpha;
fn void fn_alpha() {}
module beta;
fn void fn_beta() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	assert(ws.modules.len() == 2,
	"Expected exactly two module entries (all the modules need to be registered)");

	Module* alpha = ws.modules.get("alpha")!!;
	assert(alpha != null, "Module 'alpha' not found");

	io::printfn("%s", ws.strings.lookup);
	Module* beta = ws.modules.get("beta")!!;
	assert(beta != null, "Module 'beta' not found");
}

// ------------------------------------------------------------
// 17. Each section holds declarations to only its block
// ------------------------------------------------------------
<*
Because parse_module() does switch sections, each declaration should
only be in its corresponding module and not others.
*>
fn void test_multi_module_each_decls_in_its_section() @test => @pool()
{
	String path = write_fixture("mm_decls", `module alpha2;
fn void fn_a() {}
module beta2;
fn void fn_b() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Module* alpha = ws.modules.get("alpha2")!!;
	assert(alpha.sections.len() == 1, "Expected one section for the whole file");

	// Both functions are in alpha's section
	if (catch e = ws.lookup("alpha2", "fn_a"))
	{
		assert(false, "fn_a not found in alpha2: %s", e);
	}
	if (try v = ws.lookup("alpha2", "fn_b"))
	{
		assert(false, "fn_b found in alpha2 (should be in beta2, not alpha2): %s", v);
	}
	if (catch e = ws.lookup("beta2", "fn_b"))
	{
		assert(false, "fn_b not found in beta2: %s", e);
	}
}

// ------------------------------------------------------------
// 18. Every module header produces a MODULE_DECL top-level node
// ------------------------------------------------------------
<*
The second header creates a new workspace module, so only one
MODULE_DECL is found node inside each.
*>
fn void test_multi_module_decl_nodes_recorded() @test => @pool()
{
	String path = write_fixture("mm_nodes", `module mod_x;
fn void fx() {}
module mod_y;
fn void fy() {}
`);

	Workspace ws;
	ws.init();
	parser::parse_file(&ws, path)!!;

	Module* modx = ws.modules.get("mod_x")!!;
	ModuleSection* sx = modx.sections[0];

	assert(count_kind(sx, NodeKind.MODULE_DECL) == 1,
	"Expected one MODULE_DECL node in mod_x");

	assert(count_kind(sx, NodeKind.FN_DECL) == 1,
	"Expected one FN_DECL node");

	Module* mody = ws.modules.get("mod_y")!!;
	ModuleSection* sy = mody.sections[0];

	assert(count_kind(sy, NodeKind.MODULE_DECL) == 1,
	"Expected one MODULE_DECL node in mod_y");

	assert(count_kind(sy, NodeKind.FN_DECL) == 1,
	"Expected one FN_DECL node");
}

// // ------------------------------------------------------------
// // 19. Three module headers in one file
// // ------------------------------------------------------------
// <*
// A more extreme case: three headers.  Still only one workspace
// entry and one section; all three MODULE_DECL nodes are present.
// *>
// fn void test_multi_module_three_headers() @test => @pool()
// {
// String path = write_fixture("mm_three", `module first;
// fn void f1() {}
// module second;
// fn void f2() {}
// module third;
// fn void f3() {}
// `);
// 
// Workspace ws;
// ws.init();
// parser::parse_file(&ws, path)!!;
// 
// assert(ws.modules.len() == 1,
// "Expected exactly one workspace module for a three-header file");
// 
// Module* mod = ws.modules.get("first")!!;
// ModuleSection* s = mod.sections[0];
// 
// assert(count_kind(s, NodeKind.MODULE_DECL) == 3, "Expected 3 MODULE_DECL nodes");
// assert(count_kind(s, NodeKind.FN_DECL)     == 3, "Expected 3 FN_DECL nodes");
// 
// // All three functions reachable under "first"
// if (catch e = ws.lookup("first", "f1"))
// {
// assert(false, "f1 not found: %s", e);
// }
// if (catch e = ws.lookup("first", "f2"))
// {
// assert(false, "f2 not found (should be in first's section): %s", e);
// }
// if (catch e = ws.lookup("first", "f3"))
// {
// assert(false, "f3 not found (should be in first's section): %s", e);
// }
// }
// 
// // ------------------------------------------------------------
// // 20. peek_module_name scans the whole file, not just the start
// // ------------------------------------------------------------
// <*
// peek_module_name iterates every token in the file looking for the
// first MODULE keyword.  Therefore a file whose FIRST declaration is
// a plain function but has a "module foo;" later in the body still
// uses "foo" as the module name — the filename-inference path is not
// taken.  All declarations (before and after the header) end up in
// foo's section.
// *>
// fn void test_multi_module_peek_scans_whole_file() @test => @pool()
// {
// // The file has NO leading module header; only one in the middle.
// // peek_module_name will find "explicit_mod" and use that.
// String path = write_fixture("mm_peek", `fn void before_header() {}
// module explicit_mod;
// fn void after_header() {}
// `);
// 
// Workspace ws;
// ws.init();
// parser::parse_file(&ws, path)!!;
// 
// assert(ws.modules.len() == 1,
// "Expected one workspace module (found by peek, not inferred)");
// 
// // The module is registered under the file name
// Module* mod_mm_peek = ws.modules.get("mm_peek") ?? null;
// assert(mod_mm_peek != null, "Module 'mm_peek' not found");
// 
// // The module is registered under the scanned name
// Module* mod_explicit_mod = ws.modules.get("explicit_mod") ?? null;
// assert(mod_explicit_mod != null, "Module 'explicit_mod' not found");
// 
// // Both functions land in explicit_mod's section
// if (catch e = ws.lookup("mm_peek", "before_header"))
// {
// assert(false, "before_header not found: %s", e);
// }
// if (catch e = ws.lookup("explicit_mod", "after_header"))
// {
// assert(false, "after_header not found: %s", e);
// }
// }
// 
// // ------------------------------------------------------------
// // 21. Multi-module file + another file for the same first module
// // ------------------------------------------------------------
// <*
// When a multi-module file shares its first module name with a
// separate single-module file, the workspace merges them correctly:
// one Module with two sections (one per source file).
// *>
// fn void test_multi_module_merges_with_external_file() @test => @pool()
// {
// // File 1: two-module file whose first header is "shared_mm"
// String path1 = write_fixture("mm_shared_a", `module shared_mm;
// fn void from_file1() {}
// module other_mm;
// fn void also_from_file1() {}
// `);
// // File 2: single-module file also in "shared_mm"
// String path2 = write_fixture("mm_shared_b", `module shared_mm;
// fn void from_file2() {}
// `);
// 
// Workspace ws;
// ws.init();
// parser::parse_file(&ws, path1)!!;
// parser::parse_file(&ws, path2)!!;
// 
// Module* mod = ws.modules.get("shared_mm")!!;
// // Two source files → two sections
// assert(mod.sections.len() == 2,
// "Expected two sections (one per source file)");
// 
// // Symbols from both files reachable
// if (catch e = ws.lookup("shared_mm", "from_file1"))
// {
// assert(false, "from_file1 not found: %s", e);
// }
// if (catch e = ws.lookup("shared_mm", "from_file2"))
// {
// assert(false, "from_file2 not found: %s", e);
// }
// }
