module c3_parser_tests;

import c3_parser::workspace;
import c3_parser::parser;
import c3_parser::cursor;
import c3_parser::ast;
import c3_parser::ast::views;
import c3_parser::common;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

// ------------------------------------------------------------
// 1. Basic module declaration
// ------------------------------------------------------------
<*
 A file with an explicit module header produces exactly one module
  with the declared name and one section.
*>
fn void test_basic_module() @test // => @pool()
{
	String path = write_fixture("basic", `module hello;
fn void greet() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	defer ws.free();
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
fn void test_module_name_inferred_from_path() @test // => @pool()
{
	// write_fixture always produces /tmp/c3_test_<name>.c3
	// so the inferred module name will be "c3_test_infer_me"
	String path = write_fixture("infer_me", `fn void standalone() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	defer ws.free();
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
fn void test_fn_decl_with_params() @test // => @pool()
{
	String path = write_fixture("fn_params", `module fn_mod;
fn int add(int a, int b) {
  return a + b;
}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor fn_cur = ws.lookup_in_module("fn_mod", "add")!!;
	assert (fn_cur.section.source_file.ast.get_kind(fn_cur.node) == NodeKind.FN_DECL , "Node is not FN_DECL");

	FnView v = { &fn_cur.section.source_file.ast, fn_cur.node };
	ParamsListView plv = v.params();
	log::error("num params: %s", plv.count());
	assert (plv.count() == 2 , "Expected 2 parameters");
}

// ------------------------------------------------------------
// 4. Struct declaration
// ------------------------------------------------------------
<*
 A struct declaration is accessible by name and reports the
  correct field count.
*>
fn void test_struct_decl() @test // => @pool()
{
	String path = write_fixture("struct", `module struct_mod;
struct Point {
  float x;
  float y;
}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor sc = ws.lookup_in_module("struct_mod", "Point")!!;
	assert (sc.section.source_file.ast.get_kind(sc.node) == NodeKind.STRUCT_DECL , "Node is not STRUCT_DECL");

	StructView sv = { &sc.section.source_file.ast, sc.node };
	assert (sv.field_count() == 2 , "Expected 2 fields in Point");
}

// ------------------------------------------------------------
// 5. Import declarations are recorded as top-level nodes
// ------------------------------------------------------------
<*
 Every import statement produces an IMPORT_DECL top-level node.
*>
fn void test_import_decl() @test // => @pool()
{
	String path = write_fixture("imports", `module imp_mod;
import std::io;
import std::math;
fn void use_them() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
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
fn void test_const_decl() @test // => @pool()
{
	String path = write_fixture("const", `module const_mod;
const int MAX_SIZE = 100;
`);

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor cc = ws.lookup_in_module("const_mod", "MAX_SIZE")!!;
	// CONST_DECL is stored as a GLOBAL_DECL with a const flag
	NodeKind k = cc.section.source_file.ast.get_kind(cc.node);

	VarDeclView view = { &cc.section.source_file.ast, cc.node };
	assert(k == NodeKind.VAR_DECL , "Expected VAR_DECL");
	assert(view.is_const(), "Expected const for VAR_DECL");
}

// ------------------------------------------------------------
// 7. workspace::lookup — found and not-found cases
// ------------------------------------------------------------
<*
lookup returns a valid Cursor for known symbols, and a fault for
missing symbols or missing modules.
*>
fn void test_workspace_lookup() @test // => @pool()
{
	String path = write_fixture("lookup", `module lu_mod;
fn void target() {}
struct Target { int a; }
`);

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	// Existing function
	Cursor fn_cur = ws.lookup_in_module("lu_mod", "target")!!;
	assert(fn_cur.section.source_file.ast.get_kind(fn_cur.node) == NodeKind.FN_DECL,
	"'target' is not FN_DECL");

	// Existing struct
	Cursor st_cur = ws.lookup_in_module("lu_mod", "Target")!!;
	assert(st_cur.section.source_file.ast.get_kind(st_cur.node) == NodeKind.STRUCT_DECL,
	"'Target' is not STRUCT_DECL");

	// Non-existent symbol → fault
	if (try found_sym = ws.lookup_in_module("lu_mod", "no_such_symbol"))
	{
		assert(false, "Expected fault for missing symbol, got a cursor for node %d",
		(uint)found_sym.node);
	}

	// Non-existent module → fault
	if (try found_mod = ws.lookup_in_module("no_such_mod", "target"))
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
fn void test_cursor_spelling() @test // => @pool()
{
	String path = write_fixture("spell", `module spell_mod;
fn void spelled_func() {}
struct WellNamed {
int a;
}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor fc = ws.lookup_in_module("spell_mod", "spelled_func")!!;
	assert(fc.spelling()!! == "spelled_func",
	"Spelling of function is wrong");

	Cursor sc = ws.lookup_in_module("spell_mod", "WellNamed")!!;
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
fn void test_cursor_source_text() @test // => @pool()
{
	String path = write_fixture("srctext", `module srctext_mod;
fn void my_unique_function() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor fc = ws.lookup_in_module("srctext_mod", "my_unique_function")!!;
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
fn void test_find_section_by_path() @test // => @pool()
{
	String path = write_fixture("pathfind", `module pf_mod;
fn void located() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
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
fn void test_find_at_location() @test // => @pool()
{
	// "fn void findme() {}" begins at line 2, column 1
	String path = write_fixture("location", `module loc_mod;
fn void findme() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
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
fn void test_source_file_back_references() @test // => @pool()
{
	String path = write_fixture("backref", `module br_mod;
fn void ref_func() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
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
fn void test_multi_file_same_module() @test // => @pool()
{
	String path1 = write_fixture("mf_a", `module shared_mod;
fn void foo() {}
`);
	String path2 = write_fixture("mf_b", `module shared_mod;
fn void bar() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path1)!!;
	parser::parse_file(&ws, path2)!!;

	assert(ws.modules.len() == 1,  "Expected exactly one merged module");

	Module* mod = ws.modules.get("shared_mod")!!;
	assert(mod.sections.len() == 2, "Expected two sections for two files");

	if (catch e = ws.lookup_in_module("shared_mod", "foo"))
	{
		assert(false, "'foo' not found after multi-file parse: %s", e);
	}

	if (catch e = ws.lookup_in_module("shared_mod", "bar"))
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
fn void test_reparse_same_file() @test // => @pool()
{
	String path = write_fixture("reparse", `module rp_mod;
fn void only_once() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
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
	if (catch e = ws.lookup_in_module("rp_mod", "only_once"))
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
fn void test_error_recovery() @test // => @pool()
{
	// "return;" is valid C3 but illegal at the top level — the parser will fail
	// on it, call synchronize(), then resume at the next top-level keyword.
	String path = write_fixture("recovery", `module rec_mod;
fn void good_before() {}
return;
fn void good_after() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	// parse_file should NOT propagate a fatal error — recovery handles it
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("rec_mod")!!;
	assert(mod != null, "Module not created despite error recovery");

	// Both well-formed functions should be present
	if (catch e = ws.lookup_in_module("rec_mod", "good_before"))
	{
		assert(false, "'good_before' missing - was it dropped by error recovery?: %s", e);
	}

	if (catch e = ws.lookup_in_module("rec_mod", "good_after"))
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
fn void test_multi_module_in_workspace() @test // => @pool()
{
	String path = write_fixture("mm_first", `module alpha;
fn void fn_alpha() {}
module beta;
fn void fn_beta() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
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
fn void test_multi_module_each_decls_in_its_section() @test // => @pool()
{
	String path = write_fixture("mm_decls", `module alpha2;
fn void fn_a() {}
module beta2;
fn void fn_b() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* alpha = ws.modules.get("alpha2")!!;
	assert(alpha.sections.len() == 1, "Expected one section for the whole file");

	// Both functions are in alpha's section
	if (catch e = ws.lookup_in_module("alpha2", "fn_a"))
	{
		assert(false, "fn_a not found in alpha2: %s", e);
	}
	if (try v = ws.lookup_in_module("alpha2", "fn_b"))
	{
		assert(false, "fn_b found in alpha2 (should be in beta2, not alpha2): %s", v);
	}
	if (catch e = ws.lookup_in_module("beta2", "fn_b"))
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
fn void test_multi_module_decl_nodes_recorded() @test // => @pool()
{
	String path = write_fixture("mm_nodes", `module mod_x;
fn void fx() {}
module mod_y;
fn void fy() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
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

// ------------------------------------------------------------
// 19. Three module headers in one file
// ------------------------------------------------------------
<*
A more extreme case: three headers.  Three workspace
entries and three sections; all three have only one MODULE_DECL node.
*>
fn void test_multi_module_three_headers() @test // => @pool()
{
	String path = write_fixture("mm_three", `module first;
fn void f1() {}
module second;
fn void f2() {}
module third;
fn void f3() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	assert(ws.modules.len() == 3,
	"Expected exactly three workspace modules for a three-header file");

	Module* modfirst = ws.modules.get("first")!!;
	ModuleSection* sfirst = modfirst.sections[0];

	assert(count_kind(sfirst, NodeKind.MODULE_DECL) == 1, "Expected 1 MODULE_DECL node");
	assert(count_kind(sfirst, NodeKind.FN_DECL)     == 1, "Expected 1 FN_DECL node");

	if (catch e = ws.lookup_in_module("first", "f1"))
	{
		assert(false, "f1 not found: %s", e);
	}
	if (try ws.lookup_in_module("first", "f2"))
	{
		assert(false, "f2 found (should not be in first's section)");
	}
	if (try ws.lookup_in_module("first", "f3"))
	{
		assert(false, "f3 found (should not be in first's section)");
	}

	Module* modsecond = ws.modules.get("second")!!;
	ModuleSection* ssecond = modsecond.sections[0];
	assert(count_kind(ssecond, NodeKind.MODULE_DECL) == 1, "Expected 1 MODULE_DECL node");
	assert(count_kind(ssecond, NodeKind.FN_DECL)     == 1, "Expected 1 FN_DECL node");

	if (catch e = ws.lookup_in_module("second", "f2"))
	{
		assert(false, "f2 not found: %s", e);
	}
	if (try ws.lookup_in_module("second", "f1"))
	{
		assert(false, "f1 found (should not be in second's section)");
	}
	if (try ws.lookup_in_module("second", "f3"))
	{
		assert(false, "f3 found (should not be in second's section)");
	}

	Module* modthird = ws.modules.get("third")!!;
	ModuleSection* sthird = modthird.sections[0];
	assert(count_kind(sthird, NodeKind.MODULE_DECL) == 1, "Expected 1 MODULE_DECL node");
	assert(count_kind(sthird, NodeKind.FN_DECL)     == 1, "Expected 1 FN_DECL node");

	if (catch e = ws.lookup_in_module("third", "f3"))
	{
		assert(false, "f3 not found: %s", e);
	}
	if (try ws.lookup_in_module("third", "f1"))
	{
		assert(false, "f1 found (should not be in third's section)");
	}
	if (try ws.lookup_in_module("third", "f2"))
	{
		assert(false, "f2 found (should not be in third's section)");
	}
}

// ------------------------------------------------------------
// 20. peek_module_name scans the whole file, not just the start
// ------------------------------------------------------------
fn void test_multi_module_peek_scans_first_token() @test // => @pool()
{
	// The file has NO leading module header; only one in the middle.
	// peek_module_name will find "explicit_mod" and use that.
	String path = write_fixture("mm_peek", `fn void before_header() {}
module explicit_mod;
fn void after_header() {}
`);

	String inferred_module_name = path.tsplit("/")[^1].strip_suffix(".c3");

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	assert(ws.modules.len() == 2,
	"Expected two workspace modules (inferred and encountered)");

	// The module is registered under the file name
	Module* mod_mm_peek = ws.modules.get(inferred_module_name) ?? null;
	assert(mod_mm_peek != null, "Module 'mm_peek' not found");

	// The module is registered under the scanned name
	Module* mod_explicit_mod = ws.modules.get("explicit_mod") ?? null;
	assert(mod_explicit_mod != null, "Module 'explicit_mod' not found");

	// Both functions land in explicit_mod's section
	if (catch e = ws.lookup_in_module(inferred_module_name, "before_header"))
	{
		assert(false, "before_header not found: %s", e);
	}
	if (try ws.lookup_in_module(inferred_module_name, "after_header"))
	{
		assert(false, "after_header found in explicit_mod");
	}

	if (catch e = ws.lookup_in_module("explicit_mod", "after_header"))
	{
		assert(false, "after_header not found: %s", e);
	}
	if (try ws.lookup_in_module("explicit_mod", "before_header"))
	{
		assert(false, "before_header found in explicit_mod");
	}
}

// ------------------------------------------------------------
// 21. Multi-module file + another file for the same first module
// ------------------------------------------------------------
<*
When a multi-module file shares its first module name with a
separate single-module file, the workspace merges them correctly:
one Module with two sections (one per source file).
*>
fn void test_multi_module_merges_with_external_file() @test // => @pool()
{
	// File 1: two-module file whose first header is "shared_mm"
	String path1 = write_fixture("mm_shared_a", `module shared_mm;
fn void from_file1() {}
module other_mm;
fn void also_from_file1() {}
`);
	// File 2: single-module file also in "shared_mm"
	String path2 = write_fixture("mm_shared_b", `module shared_mm;
fn void from_file2() {}
`);

	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path1)!!;
	parser::parse_file(&ws, path2)!!;

	Module* mod = ws.modules.get("shared_mm")!!;
	// Two source files → two sections
	assert(mod.sections.len() == 2,
	"Expected two sections (one per source file)");

	// Symbols from both files reachable
	if (catch e = ws.lookup_in_module("shared_mm", "from_file1"))
	{
		assert(false, "from_file1 not found: %s", e);
	}
	if (catch e = ws.lookup_in_module("shared_mm", "from_file2"))
	{
		assert(false, "from_file2 not found: %s", e);
	}
}

// ============================================================
// GROUP A: Declaration node types
// ============================================================

// 22. Basic enum declaration
fn void test_enum_decl() @test // => @pool()
{
	String path = write_fixture("enum_basic", `module enum_mod;
enum Color { RED, GREEN, BLUE }
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("enum_mod")!!;
	ModuleSection* s = mod.sections[0];
	assert(count_kind(s, NodeKind.ENUM_DECL) == 1, "Expected one ENUM_DECL");
}

// 23. constdef with explicit member values (no base type — base type + brace conflicts with
//     the parser's generic-argument heuristic, so we test values without it)
fn void test_constdef_with_explicit_values() @test // => @pool()
{
	String path = write_fixture("enum_vals", `module enum_vals_mod;
constdef Status { OK = 0, FAIL = 1, PENDING = 2 }
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("enum_vals_mod")!!;
	ModuleSection* s = mod.sections[0];
	assert(count_kind(s, NodeKind.ENUM_DECL) == 1, "Expected one ENUM_DECL with explicit values");
}

// 24. Multiple enums in one file
fn void test_multiple_enums() @test // => @pool()
{
	String path = write_fixture("enum_multi", `module multi_enum_mod;
enum Direction { NORTH, SOUTH, EAST, WEST }
enum Priority { LOW, MEDIUM, HIGH }
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("multi_enum_mod")!!;
	ModuleSection* s = mod.sections[0];
	assert(count_kind(s, NodeKind.ENUM_DECL) == 2, "Expected two ENUM_DECLs");
}

// 25. Basic interface declaration
fn void test_interface_decl() @test // => @pool()
{
	String path = write_fixture("iface_basic", `module iface_mod;
interface Drawable {
	fn void draw();
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("iface_mod")!!;
	ModuleSection* s = mod.sections[0];
	assert(count_kind(s, NodeKind.INTERFACE_DECL) == 1, "Expected one INTERFACE_DECL");
}

// 26. Interface extending another interface
fn void test_interface_inheritance() @test // => @pool()
{
	String path = write_fixture("iface_inherit", `module iface_inherit_mod;
interface Base {
	fn void base_method();
}
interface Extended : Base {
	fn void extra_method();
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("iface_inherit_mod")!!;
	ModuleSection* s = mod.sections[0];
	assert(count_kind(s, NodeKind.INTERFACE_DECL) == 2, "Expected two INTERFACE_DECLs");
}

// 27. Type alias declarations
fn void test_type_alias_decl() @test // => @pool()
{
	String path = write_fixture("alias_type", `module alias_mod;
alias MyInt = int;
alias MyFloat = float;
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("alias_mod")!!;
	ModuleSection* s = mod.sections[0];
	assert(count_kind(s, NodeKind.TYPE_ALIAS_DECL) == 2, "Expected two TYPE_ALIAS_DECLs");
}

// 28. Typedef declaration
fn void test_typedef_decl() @test // => @pool()
{
	String path = write_fixture("typedef_basic", `module typedef_mod;
typedef MyAlias = int;
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("typedef_mod")!!;
	ModuleSection* s = mod.sections[0];
	assert(count_kind(s, NodeKind.TYPEDEF_DECL) == 1, "Expected one TYPEDEF_DECL");
}

// 29. Macro declaration
fn void test_macro_decl() @test // => @pool()
{
	String path = write_fixture("macro_basic", `module macro_mod;
macro my_macro() {}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("macro_mod")!!;
	ModuleSection* s = mod.sections[0];
	assert(count_kind(s, NodeKind.MACRO_DECL) == 1, "Expected one MACRO_DECL");
}

// 30. Global variable declaration
fn void test_global_var_decl() @test // => @pool()
{
	String path = write_fixture("global_var", `module global_mod;
int counter = 0;
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup("global_mod", "counter")!!;
	VarDeclView view = { &c.section.source_file.ast, c.node };
	assert(c.section.source_file.ast.get_kind(c.node) == NodeKind.VAR_DECL,
	"Expected VAR_DECL for global variable");
	assert(view.is_global(), "Expected VAR_DECL to be global");
}

// 31. Global variable spelling via workspace lookup
fn void test_global_decl_spelling() @test // => @pool()
{
	String path = write_fixture("global_spell", `module gspell_mod;
float pi_value = 3.14159;
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup("gspell_mod", "pi_value")!!;
	VarDeclView view = { &c.section.source_file.ast, c.node };
	assert(c.section.source_file.ast.get_kind(c.node) == NodeKind.VAR_DECL,
	"Expected VAR_DECL");
	assert(view.is_global(), "Expected VAR_DECL to be global");
}

// 32. Thread-local variable declaration
fn void test_tlocal_var_decl() @test // => @pool()
{
	String path = write_fixture("tlocal", `module tlocal_mod;
tlocal int tl_counter;
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup("tlocal_mod", "tl_counter")!!;
	VarDeclView view = { &c.section.source_file.ast, c.node };
	assert(c.section.source_file.ast.get_kind(c.node) == NodeKind.VAR_DECL,
	"tlocal var should produce VAR_DECL");
	assert(view.is_thread_local(), "expected tlocal variable to have tlocal flag");
}

// 33. Mixed declaration kinds in one module
fn void test_mixed_declarations() @test // => @pool()
{
	String path = write_fixture("mixed_decls", `module mixed_mod;
struct Point { float x; float y; }
enum Dir { NORTH, SOUTH }
fn void draw() {}
int counter = 0;
alias Scalar = float;
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("mixed_mod")!!;
	ModuleSection* s = mod.sections[0];
	assert(count_kind(s, NodeKind.STRUCT_DECL)     == 1, "Expected 1 STRUCT_DECL");
	assert(count_kind(s, NodeKind.ENUM_DECL)       == 1, "Expected 1 ENUM_DECL");
	assert(count_kind(s, NodeKind.FN_DECL)         == 1, "Expected 1 FN_DECL");
	assert(count_kind(s, NodeKind.VAR_DECL)     == 1, "Expected 1 VAR_DECL");
	assert(count_kind(s, NodeKind.TYPE_ALIAS_DECL) == 1, "Expected 1 TYPE_ALIAS_DECL");
}

// ============================================================
// GROUP B: Function variations
// ============================================================

// 34. Function with arrow body
fn void test_fn_arrow_body() @test // => @pool()
{
	String path = write_fixture("fn_arrow", `module arrow_mod;
fn int double_it(int x) => x * 2;
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("arrow_mod", "double_it")!!;
	assert(c.section.source_file.ast.get_kind(c.node) == NodeKind.FN_DECL,
		"Expected FN_DECL for arrow-body function");
	FnView fv = { &c.section.source_file.ast, c.node };
	ParamsListView plv = fv.params();
	assert(plv.count() == 1, "Expected 1 param");
	assert(fv.body().is_valid(), "Arrow body should produce a valid body node");
}

// 35. Function with method syntax (Struct.method)
fn void test_fn_method_syntax() @test // => @pool()
{
	String path = write_fixture("fn_method", `module method_mod;
struct Vec2 { float x; float y; }
fn float Vec2.length(&self) { return 0.0; }
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	// Method is stored under its simple name, not "Vec2.length"
	Cursor c = ws.lookup_in_module("method_mod", "length")!!;
	assert(c.section.source_file.ast.get_kind(c.node) == NodeKind.FN_DECL,
		"Expected FN_DECL for method");
	FnView fv = { &c.section.source_file.ast, c.node };
	// associated() holds the StringHandle of the receiver type — non-zero for methods
	assert(fv.associated().is_valid(), "Method should have a non-zero associated type");
}

// 36. Function return type node is present
fn void test_fn_return_type() @test // => @pool()
{
	String path = write_fixture("fn_rettype", `module rettype_mod;
fn int get_value() { return 42; }
fn void do_nothing() {}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	{
		Cursor c = ws.lookup_in_module("rettype_mod", "get_value")!!;
		FnView fv = { &c.section.source_file.ast, c.node };
		assert(fv.return_type().is_valid(), "get_value should have a return type node");
	}
	{
		Cursor c = ws.lookup_in_module("rettype_mod", "do_nothing")!!;
		FnView fv = { &c.section.source_file.ast, c.node };
		assert(fv.return_type().is_valid(), "'void' should still produce a type node");
	}
}

// 37. Function body is a COMPOUND_STMT
fn void test_fn_body_node() @test // => @pool()
{
	String path = write_fixture("fn_body", `module body_mod;
fn void with_body() { int x = 1; }
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("body_mod", "with_body")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	assert(fv.body().is_valid(), "Expected valid body node");
	assert(ast.get_kind(fv.body()) == NodeKind.COMPOUND_STMT,
		"Function body must be COMPOUND_STMT");
}

// 38. Reference parameter (&self) is flagged correctly
fn void test_fn_ref_param() @test // => @pool()
{
	String path = write_fixture("fn_ref_param", `module refparam_mod;
struct Thing { int value; }
fn int Thing.get(&self) { return 0; }
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("refparam_mod", "get")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	ParamsListView plv = fv.params();
	assert(plv.count() == 1, "Expected 1 param (&self)");
	ParamView pv = plv.get_param(0);
	assert(pv.is_ref(), "Expected &self param to be flagged as reference");
}

// 39. param_count for 0, 1, and 5 params
fn void test_fn_param_counts() @test // => @pool()
{
	String path = write_fixture("fn_pcounts", `module pcount_mod;
fn void zero_params() {}
fn void one_param(int a) {}
fn void five_params(int a, int b, int c, int d, int e) {}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	{
		Cursor c = ws.lookup_in_module("pcount_mod", "zero_params")!!;
		FnView fv = { &c.section.source_file.ast, c.node };
		ParamsListView plv = fv.params();
		assert(plv.count() == 0, "Expected 0 params for zero_params");
	}
	{
		Cursor c = ws.lookup_in_module("pcount_mod", "one_param")!!;
		FnView fv = { &c.section.source_file.ast, c.node };
		ParamsListView plv = fv.params();
		assert(plv.count() == 1, "Expected 1 param for one_param");
	}
	{
		Cursor c = ws.lookup_in_module("pcount_mod", "five_params")!!;
		FnView fv = { &c.section.source_file.ast, c.node };
		ParamsListView plv = fv.params();
		assert(plv.count() == 5, "Expected 5 params for five_params");
	}
}

// 40. FnView.name() round-trips through the string pool
fn void test_fn_view_name() @test // => @pool()
{
	String path = write_fixture("fn_name", `module fn_name_mod;
fn void uniquely_named_function() {}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("fn_name_mod", "uniquely_named_function")!!;
	FnView fv = { &c.section.source_file.ast, c.node };
	String name = fv.name(c.section.source_file.strings);
	assert(name == "uniquely_named_function", "FnView.name() mismatch: '%s'", name);
}

// ============================================================
// GROUP C: Struct variations
// ============================================================

// 41. Struct with zero fields should be an error
fn void test_struct_empty() @test // => @pool()
{
	String path = write_fixture("struct_empty", `module empty_struct_mod;
struct Empty {}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor sc = ws.lookup_in_module("empty_struct_mod", "Empty")!!;
	assert(sc.section.source_file.ast.get_kind(sc.node) == NodeKind.STRUCT_DECL,
		"Expected STRUCT_DECL");
	StructView sv = { &sc.section.source_file.ast, sc.node };
	assert(sv.field_count() == 0, "Expected 0 fields in Empty");
}

// 42. Struct with four fields
fn void test_struct_many_fields() @test // => @pool()
{
	String path = write_fixture("struct_many", `module many_mod;
struct Color {
	float r;
	float g;
	float b;
	float a;
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor sc = ws.lookup_in_module("many_mod", "Color")!!;
	StructView sv = { &sc.section.source_file.ast, sc.node };
	assert(sv.field_count() == 4, "Expected 4 fields in Color");
}

// 43. StructView.name() round-trips through string pool
fn void test_struct_view_name() @test // => @pool()
{
	String path = write_fixture("struct_name", `module struct_name_mod;
struct NamedStruct { int x; int y; }
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor sc = ws.lookup_in_module("struct_name_mod", "NamedStruct")!!;
	StructView sv = { &sc.section.source_file.ast, sc.node };
	String name = sv.name(sc.section.source_file.strings);
	assert(name == "NamedStruct", "StructView.name() mismatch: '%s'", name);
	assert(sv.field_count() == 2, "Expected 2 fields");
}

// 44. Struct that implements an interface
fn void test_struct_with_interface() @test // => @pool()
{
	String path = write_fixture("struct_iface", `module struct_iface_mod;
interface Shape {
	fn float area();
}
struct Circle (Shape) {
	float radius;
}
fn float Circle.area(&self) { return 0.0; }
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("struct_iface_mod")!!;
	ModuleSection* s = mod.sections[0];
	assert(count_kind(s, NodeKind.INTERFACE_DECL) == 1, "Expected one INTERFACE_DECL");
	assert(count_kind(s, NodeKind.STRUCT_DECL)    == 1, "Expected one STRUCT_DECL");

	Cursor sc = ws.lookup_in_module("struct_iface_mod", "Circle")!!;
	StructView sv = { &sc.section.source_file.ast, sc.node };
	assert(sv.field_count() == 1, "Expected 1 field in Circle");
}

// ============================================================
// GROUP D: Statement node kinds inside function bodies
// ============================================================

// 45. for loop produces FOR_STMT
fn void test_stmt_for_loop() @test // => @pool()
{
	String path = write_fixture("stmt_for", `module for_mod;
fn void count_up() {
	for (int i = 0; i < 10; i++) {}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("for_mod", "count_up")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 1, "Expected 1 stmt in body");
	assert(ast.get_kind(cv.get(0)) == NodeKind.FOR_STMT, "Expected FOR_STMT");
}

// 46. BREAK_STMT is accessible via ForView.body
fn void test_stmt_break() @test // => @pool()
{
	String path = write_fixture("stmt_break", `module break_mod;
fn void stop_early() {
	for (;;) {
		break;
	}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("break_mod", "stop_early")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView outer_cv = { ast, fv.body() };
	Node for_node = outer_cv.get(0);
	assert(ast.get_kind(for_node) == NodeKind.FOR_STMT, "Expected FOR_STMT");
	ForView forv = { ast, for_node };
	CompoundView inner = { ast, forv.body() };
	assert(inner.len() == 1, "Expected 1 stmt in for body");
	assert(ast.get_kind(inner.get(0)) == NodeKind.BREAK_STMT, "Expected BREAK_STMT");
}

// 47. while loop produces WHILE_STMT
fn void test_stmt_while_loop() @test // => @pool()
{
	String path = write_fixture("stmt_while", `module while_mod;
fn void spin() {
	while (true) {}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("while_mod", "spin")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 1, "Expected 1 stmt");
	assert(ast.get_kind(cv.get(0)) == NodeKind.WHILE_STMT, "Expected WHILE_STMT");
}

// 48. do-while produces DO_WHILE_STMT
fn void test_stmt_do_while() @test // => @pool()
{
	String path = write_fixture("stmt_dowhile", `module dowhile_mod;
fn void run_once() {
	do {} while (false);
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("dowhile_mod", "run_once")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 1, "Expected 1 stmt");
	assert(ast.get_kind(cv.get(0)) == NodeKind.DO_WHILE_STMT, "Expected DO_WHILE_STMT");
}

// 49. foreach produces FOREACH_STMT
fn void test_stmt_foreach() @test // => @pool()
{
	String path = write_fixture("stmt_foreach", `module foreach_mod;
fn void iterate() {
	foreach (x : items) {}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("foreach_mod", "iterate")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 1, "Expected 1 stmt");
	assert(ast.get_kind(cv.get(0)) == NodeKind.FOREACH_STMT, "Expected FOREACH_STMT");
}

// 50. foreach_r produces FOREACH_R_STMT
fn void test_stmt_foreach_r() @test // => @pool()
{
	String path = write_fixture("stmt_foreach_r", `module foreach_r_mod;
fn void iter_rev() {
	foreach_r (x : items) {}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("foreach_r_mod", "iter_rev")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 1, "Expected 1 stmt");
	assert(ast.get_kind(cv.get(0)) == NodeKind.FOREACH_R_STMT, "Expected FOREACH_R_STMT");
}

// 51. if/else: both then and else blocks are valid
fn void test_stmt_if_else() @test // => @pool()
{
	String path = write_fixture("stmt_if", `module if_mod;
fn void branch(bool flag) {
	if (flag) {} else {}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("if_mod", "branch")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv_if = { ast, fv.body() };
	Node stmt = cv_if.get(0);
	assert(ast.get_kind(stmt) == NodeKind.IF_STMT, "Expected IF_STMT");
	IfView iv = { ast, stmt };
	assert(iv.condition().is_valid(),  "Expected valid condition");
	assert(iv.then_block().is_valid(), "Expected valid then_block");
	assert(iv.else_block().is_valid(), "Expected valid else_block for if-else");
}

// 52. if without else: else_block is invalid
fn void test_stmt_if_no_else() @test // => @pool()
{
	String path = write_fixture("stmt_if_no_else", `module if_no_else_mod;
fn void maybe(bool flag) {
	if (flag) {}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("if_no_else_mod", "maybe")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv_noelse = { ast, fv.body() };
	Node stmt = cv_noelse.get(0);
	assert(ast.get_kind(stmt) == NodeKind.IF_STMT, "Expected IF_STMT");
	IfView iv = { ast, stmt };
	assert(iv.condition().is_valid(),   "Expected valid condition");
	assert(iv.then_block().is_valid(),  "Expected valid then_block");
	assert(!iv.else_block().is_valid(), "Expected no else_block");
}

// 53. switch/case produces SWITCH_STMT
fn void test_stmt_switch() @test // => @pool()
{
	String path = write_fixture("stmt_switch", `module switch_mod;
fn void dispatch(int x) {
	switch (x) {
		case 0: break;
		default: break;
	}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("switch_mod", "dispatch")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 1, "Expected 1 stmt");
	assert(ast.get_kind(cv.get(0)) == NodeKind.SWITCH_STMT, "Expected SWITCH_STMT");
}

// 54. defer produces DEFER_STMT
fn void test_stmt_defer() @test // => @pool()
{
	String path = write_fixture("stmt_defer", `module defer_mod;
fn void cleanup() {
	defer {}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("defer_mod", "cleanup")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 1, "Expected 1 stmt");
	assert(ast.get_kind(cv.get(0)) == NodeKind.DEFER_STMT, "Expected DEFER_STMT");
}

// 55. return produces RETURN_STMT
fn void test_stmt_return() @test // => @pool()
{
	String path = write_fixture("stmt_return", `module return_mod;
fn int compute() {
	return 42;
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("return_mod", "compute")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 1, "Expected 1 stmt");
	assert(ast.get_kind(cv.get(0)) == NodeKind.RETURN_STMT, "Expected RETURN_STMT");
}

// 56. CONTINUE_STMT is accessible via IfView.then_block inside a for body
fn void test_stmt_continue() @test // => @pool()
{
	String path = write_fixture("stmt_continue", `module cont_mod;
fn void skip(bool flag) {
	for (;;) {
		if (flag) continue;
	}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("cont_mod", "skip")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView outer_cont = { ast, fv.body() };
	Node for_node = outer_cont.get(0);
	ForView forv = { ast, for_node };
	CompoundView inner_cont = { ast, forv.body() };
	Node if_node = inner_cont.get(0);
	assert(ast.get_kind(if_node) == NodeKind.IF_STMT, "Expected IF_STMT inside for");
	IfView iv = { ast, if_node };
	assert(ast.get_kind(iv.then_block()) == NodeKind.CONTINUE_STMT,
		"Expected CONTINUE_STMT as then-branch");
}

// 57. assert produces ASSERT_STMT
fn void test_stmt_assert() @test // => @pool()
{
	String path = write_fixture("stmt_assert", `module assert_mod;
fn void check(int x) {
	assert(x > 0);
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("assert_mod", "check")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 1, "Expected 1 stmt");
	assert(ast.get_kind(cv.get(0)) == NodeKind.ASSERT_STMT, "Expected ASSERT_STMT");
}

// 58. Local variable declarations produce LOCAL_DECL nodes
fn void test_stmt_local_var() @test // => @pool()
{
	String path = write_fixture("stmt_localvar", `module localvar_mod;
fn void declare_vars() {
	int x = 5;
	float y = 3;
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("localvar_mod", "declare_vars")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView cv = { ast, fv.body() };
	assert(cv.len() == 2, "Expected 2 local decls");
	assert(ast.get_kind(cv.get(0)) == NodeKind.LOCAL_DECL, "First stmt should be LOCAL_DECL");
	assert(ast.get_kind(cv.get(1)) == NodeKind.LOCAL_DECL, "Second stmt should be LOCAL_DECL");
}

// 59. Nested compound statements
fn void test_stmt_nested_blocks() @test // => @pool()
{
	String path = write_fixture("stmt_nested", `module nested_mod;
fn void nested() {
	{
		{}
	}
}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("nested_mod", "nested")!!;
	Ast* ast = &c.section.source_file.ast;
	FnView fv = { ast, c.node };
	CompoundView outer = { ast, fv.body() };
	assert(outer.len() == 1, "Expected 1 stmt in outer block");
	Node mid = outer.get(0);
	assert(ast.get_kind(mid) == NodeKind.COMPOUND_STMT, "Expected nested COMPOUND_STMT");
	CompoundView mid_cv = { ast, mid };
	assert(mid_cv.len() == 1, "Expected 1 stmt in middle block");
	assert(ast.get_kind(mid_cv.get(0)) == NodeKind.COMPOUND_STMT,
		"Expected innermost COMPOUND_STMT");
}

// ============================================================
// GROUP E: Edge cases and boundary conditions
// ============================================================

// 60. Module with deeply nested path (foo::bar::baz)
fn void test_module_nested_path() @test // => @pool()
{
	String path = write_fixture("nested_path", `module foo::bar::baz;
fn void deep_fn() {}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("foo::bar::baz")!!;
	assert(mod != null,             "Module 'foo::bar::baz' not found");
	assert(mod.sections.len() == 1, "Expected one section");

	if (catch e = ws.lookup_in_module("foo::bar::baz", "deep_fn"))
	{
		assert(false, "deep_fn not found in nested module: %s", e);
	}
}

// 61. Two successive top-level errors do not drop surrounding valid declarations
fn void test_multiple_errors_recovery() @test // => @pool()
{
	String path = write_fixture("multi_err", `module multi_err_mod;
fn void good_a() {}
return;
return;
fn void good_b() {}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	if (catch e = ws.lookup_in_module("multi_err_mod", "good_a"))
	{
		assert(false, "good_a missing after two errors: %s", e);
	}
	if (catch e = ws.lookup_in_module("multi_err_mod", "good_b"))
	{
		assert(false, "good_b missing after two errors: %s", e);
	}
}

// 62. Two const declarations are both discoverable
fn void test_const_decl_two() @test // => @pool()
{
	String path = write_fixture("const_two", `module const2_mod;
const int LIMIT = 256;
const int OFFSET = 8;
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c1 = ws.lookup_in_module("const2_mod", "LIMIT")!!;
	NodeKind k1 = c1.section.source_file.ast.get_kind(c1.node);
	assert(k1 == NodeKind.VAR_DECL,
		"LIMIT: expected VAR_DECL");

	Cursor c2 = ws.lookup_in_module("const2_mod", "OFFSET")!!;
	NodeKind k2 = c2.section.source_file.ast.get_kind(c2.node);
	assert(k2 == NodeKind.VAR_DECL,
		"OFFSET: expected VAR_DECL");
}

// 63. source_text of struct spans its declared name
fn void test_struct_source_text() @test // => @pool()
{
	String path = write_fixture("struct_srctext", `module struct_src_mod;
struct SpecialStruct { int x; }
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor sc = ws.lookup_in_module("struct_src_mod", "SpecialStruct")!!;
	String text = sc.source_text();
	assert(text.len > 0,                  "source_text should be non-empty");
	assert(text.contains("SpecialStruct"), "source_text should contain the struct name");
}

// 64. find_at_location hits a struct declaration at its start column
fn void test_find_at_struct() @test // => @pool()
{
	String path = write_fixture("location_struct", `module loc_struct_mod;
struct Located { int a; }
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Location loc = { .line = 2, .column = 1 };
	Cursor c = ws.find_at_location(path, loc);
	assert(c.node.is_valid(), "Expected a valid cursor at struct location (2,1)");
}

// 65. Three global variables in one module are all individually reachable
fn void test_three_globals() @test // => @pool()
{
	String path = write_fixture("three_globals", `module three_glob_mod;
int alpha = 1;
int beta = 2;
int gamma = 3;
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	if (catch e = ws.lookup_in_module("three_glob_mod", "alpha"))
	{
		assert(false, "alpha not found: %s", e);
	}
	if (catch e = ws.lookup_in_module("three_glob_mod", "beta"))
	{
		assert(false, "beta not found: %s", e);
	}
	if (catch e = ws.lookup_in_module("three_glob_mod", "gamma"))
	{
		assert(false, "gamma not found: %s", e);
	}
}

// 66. Extern function declaration has no body
fn void test_fn_no_body() @test // => @pool()
{
	String path = write_fixture("fn_no_body", `module no_body_mod;
fn void external_fn() @extern("external_fn");
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Cursor c = ws.lookup_in_module("no_body_mod", "external_fn")!!;
	Ast* ast = &c.section.source_file.ast;
	assert(ast.get_kind(c.node) == NodeKind.FN_DECL,
		"Expected FN_DECL for extern fn");
	FnView fv = { ast, c.node };
	assert(!fv.body().is_valid(), "Extern fn should have no body");
}

// 67. find_section_by_path locates each file in a multi-file module
fn void test_find_section_multi_file() @test // => @pool()
{
	String path1 = write_fixture("secfind_a", `module secfind_mod;
fn void from_a() {}
`);
	String path2 = write_fixture("secfind_b", `module secfind_mod;
fn void from_b() {}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path1)!!;
	parser::parse_file(&ws, path2)!!;

	List{ModuleSection*} sec1 = ws.find_section_by_path(path1);
	assert(sec1.len() > 0, "Should find section for path1");
	assert(sec1[0].source_file.file_path == path1, "Section path mismatch for path1");

	List{ModuleSection*} sec2 = ws.find_section_by_path(path2);
	assert(sec2.len() > 0, "Should find section for path2");
	assert(sec2[0].source_file.file_path == path2, "Section path mismatch for path2");
}

// 68. Sub-module handling
fn void test_nested_sub_modules() @test // => @pool()
{
	String path = write_fixture("sub_modules", `module foo;
fn void my_foo() {}

module foo::bar;
fn void my_bar() {}
`);
	Workspace ws;
	ws.init(); defer ws.free();
	parser::parse_file(&ws, path)!!;

	Module* mod = ws.modules.get("foo")!!;
	assert(mod != null,             "Module 'foo::bar::baz' not found");
	assert(mod.sections.len() == 1, "Expected one section");

	if (catch e = ws.lookup_in_module("foo", "my_foo"))
	{
		assert(false, "deep_fn not found in nested module: %s", e);
	}

	if (catch e = ws.lookup_in_module("foo::bar", "my_bar"))
	{
		assert(false, "deep_fn not found in nested module: %s", e);
	}
}
