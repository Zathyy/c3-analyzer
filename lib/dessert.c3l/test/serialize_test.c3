module serialize_test;
import std;
import dessert;
import json;
import csv;
import derive;

// ── Test types ───────────────────────────────────────────────────────────────

$expand(derive{SPoint}(dessert::serialize));
struct SPoint {
  int x;
  int y;
}

struct SBox {
  String label;
  SPoint center;
}
fn void? SBox.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

struct SWithPointer {
  String name;
  SPoint* extra;
}
fn void? SWithPointer.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

struct SWithArray {
  String tag;
  SPoint[] items;
}
fn void? SWithArray.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

struct SSkipField {
  String kept;
  String secret   @DField({ .skip = true });
  int    internal @DField({ .skip = true });
}
fn void? SSkipField.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

struct SRenamedField {
  String original @DField({ .rename = "alias" });
  int    count    @DField({ .rename = "num" });
}
fn void? SRenamedField.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

struct SSkipIfEmpty {
  String  always;
  String  maybe_str @DField({ .skip_if_empty = true });
  SPoint* maybe_ptr @DField({ .skip_if_empty = true });
  SPoint[] maybe_arr @DField({ .skip_if_empty = true });
}
fn void? SSkipIfEmpty.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

struct SConditional {
  String name;
  int    score;
}
fn bool SConditional.skip_serializing_score(&self) => self.score < 0;
fn void? SConditional.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

// Default: serialize enum variants by name
enum SDirection {
  NORTH,
  SOUTH,
  EAST,
  WEST,
}
fn void? SDirection.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

// Serialize enum variants by ordinal (0, 1, 2, ...)
enum SRank @DEnum({ .as = ORDINAL }) {
  BRONZE,
  SILVER,
  GOLD,
}
fn void? SRank.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

// Serialize enum via an associated field value
enum SColor : (String hex) @DEnum({ .as = FIELD, .field = "hex" }) {
  RED   { "#FF0000" },
  GREEN { "#00FF00" },
  BLUE  { "#0000FF" },
}
fn void? SColor.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

struct SWithMaybe {
  String    name;
  Maybe{int} opt;
}
fn void? SWithMaybe.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

struct SWithValidator {
  String name @DField({ .validator = "validate_name" });
}
fn bool SWithValidator.validate_name(&self, String name) => name.len > 0;
fn void? SWithValidator.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

struct SWeatherRow {
  String city;
  double temp;
  bool   sunny;
}
fn void? SWeatherRow.serialize(&self, Serializer serializer) => ser::impl_serialize(self, serializer);

// ── Tests: JSON primitives ────────────────────────────────────────────────────

fn void test_ser_bool_true() @test {
  JsonSerializer s = json::serializer();
  s.serialize_bool(true)!!;
  JsonValue j = s.result()!!;
  assert(j.kind == JsonValueKind.BOOL);
  assert(j.value.b == true);
}

fn void test_ser_bool_false() @test {
  JsonSerializer s = json::serializer();
  s.serialize_bool(false)!!;
  JsonValue j = s.result()!!;
  assert(j.kind == JsonValueKind.BOOL);
  assert(j.value.b == false);
}

fn void test_ser_null() @test {
  JsonSerializer s = json::serializer();
  s.serialize_null()!!;
  JsonValue j = s.result()!!;
  assert(j.kind == JsonValueKind.NULL);
}

fn void test_ser_long_positive() @test {
  JsonSerializer s = json::serializer();
  s.serialize_long(12345)!!;
  JsonValue j = s.result()!!;
  assert(j.kind == JsonValueKind.INT);
  assert(j.value.i == 12345);
}

fn void test_ser_long_negative() @test {
  JsonSerializer s = json::serializer();
  s.serialize_long(-999)!!;
  JsonValue j = s.result()!!;
  assert(j.kind == JsonValueKind.INT);
  assert(j.value.i == -999);
}

fn void test_ser_double() @test {
  JsonSerializer s = json::serializer();
  s.serialize_double(3.14)!!;
  JsonValue j = s.result()!!;
  assert(j.kind == JsonValueKind.FLOAT);
  double diff = j.value.f - 3.14;
  if (diff < 0) diff = -diff;
  assert(diff < 1e-9);
}

fn void test_ser_string() @test {
  JsonSerializer s = json::serializer();
  s.serialize_string("hello world")!!;
  JsonValue j = s.result()!!;
  assert(j.kind == JsonValueKind.STRING);
  assert(j.value.s == "hello world");
}

// to_string() must escape embedded quotes so the output is valid JSON
fn void test_ser_string_with_quotes() @test {
  JsonSerializer s = json::serializer();
  s.serialize_string(`say "hi"`)!!;
  JsonValue j = s.result()!!;
  String out = j.to_string()!!;
  // the outer quotes + escaped inner quotes must be in the output
  assert(out == `"say \"hi\""`);
}

// ── Tests: struct serialization ───────────────────────────────────────────────

fn void test_ser_simple_struct() @test {
  SPoint p = { .x = 3, .y = -7 };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, p)!!;
  defer j.free();

  assert(j.kind == JsonValueKind.DICT);
  assert(j.value.d.get("x")!!.value.i == 3);
  assert(j.value.d.get("y")!!.value.i == -7);
}

fn void test_ser_nested_struct() @test {
  SBox b = { .label = "outer", .center = { .x = 10, .y = 20 } };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, b)!!;
  defer j.free();

  assert(j.kind == JsonValueKind.DICT);
  assert(j.value.d.get("label")!!.value.s == "outer");
  JsonValue center = j.value.d.get("center")!!;
  assert(center.kind == JsonValueKind.DICT);
  assert(center.value.d.get("x")!!.value.i == 10);
  assert(center.value.d.get("y")!!.value.i == 20);
}

fn void test_ser_null_pointer() @test {
  SWithPointer wp = { .name = "no-extra", .extra = null };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, wp)!!;
  defer j.free();

  assert(j.value.d.get("extra")!!.kind == JsonValueKind.NULL);
}

fn void test_ser_non_null_pointer() @test {
  SPoint pt = { .x = 5, .y = 9 };
  SWithPointer wp = { .name = "with-extra", .extra = &pt };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, wp)!!;
  defer j.free();

  JsonValue extra = j.value.d.get("extra")!!;
  assert(extra.kind == JsonValueKind.DICT);
  assert(extra.value.d.get("x")!!.value.i == 5);
  assert(extra.value.d.get("y")!!.value.i == 9);
}

fn void test_ser_array() @test {
  SPoint[3] pts = { { .x = 1, .y = 2 }, { .x = 3, .y = 4 }, { .x = 5, .y = 6 } };
  SWithArray wa = { .tag = "list", .items = pts[..] };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, wa)!!;
  defer j.free();

  JsonValue items = j.value.d.get("items")!!;
  assert(items.kind == JsonValueKind.ARRAY);
  assert(items.value.l.len() == 3);
  assert(items.value.l[0].value.d.get("x")!!.value.i == 1);
  assert(items.value.l[1].value.d.get("x")!!.value.i == 3);
  assert(items.value.l[2].value.d.get("x")!!.value.i == 5);
}

fn void test_ser_empty_array() @test {
  SWithArray wa = { .tag = "empty", .items = {} };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, wa)!!;
  defer j.free();

  JsonValue items = j.value.d.get("items")!!;
  assert(items.kind == JsonValueKind.ARRAY);
  assert(items.value.l.len() == 0);
}

// ── Tests: attributes ─────────────────────────────────────────────────────────

fn void test_ser_skip_field() @test {
  SSkipField sf = { .kept = "visible", .secret = "hidden", .internal = 42 };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, sf)!!;
  defer j.free();

  assert(j.value.d.get("kept")!!.value.s == "visible");
  // skipped fields must not appear in the output
  if (catch j.value.d.get("secret"))   { /* absent: correct */ } else { assert(false); }
  if (catch j.value.d.get("internal")) { /* absent: correct */ } else { assert(false); }
}

fn void test_ser_rename() @test {
  SRenamedField rf = { .original = "hello", .count = 3 };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, rf)!!;
  defer j.free();

  // original names must not appear
  if (catch j.value.d.get("original")) { /* correct */ } else { assert(false); }
  if (catch j.value.d.get("count"))    { /* correct */ } else { assert(false); }
  // renamed keys must appear with the right values
  assert(j.value.d.get("alias")!!.value.s == "hello");
  assert(j.value.d.get("num")!!.value.i   == 3);
}

fn void test_ser_skip_if_empty_all_empty() @test {
  // empty string, null pointer, empty slice → all three optional fields absent
  SSkipIfEmpty se = { .always = "present", .maybe_str = "", .maybe_ptr = null };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, se)!!;
  defer j.free();

  assert(j.value.d.get("always")!!.value.s == "present");
  if (catch j.value.d.get("maybe_str")) { /* absent: correct */ } else { assert(false); }
  if (catch j.value.d.get("maybe_ptr")) { /* absent: correct */ } else { assert(false); }
  if (catch j.value.d.get("maybe_arr")) { /* absent: correct */ } else { assert(false); }
}

fn void test_ser_skip_if_empty_non_empty() @test {
  SPoint pt = { .x = 1, .y = 2 };
  SPoint[1] pts = { pt };
  SSkipIfEmpty se = {
    .always    = "x",
    .maybe_str = "filled",
    .maybe_ptr = &pt,
    .maybe_arr = pts[..],
  };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, se)!!;
  defer j.free();

  assert(j.value.d.get("maybe_str")!!.value.s == "filled");
  assert(j.value.d.get("maybe_ptr")!!.kind == JsonValueKind.DICT);
  assert(j.value.d.get("maybe_arr")!!.kind == JsonValueKind.ARRAY);
}

fn void test_ser_conditional_skip_true() @test {
  // score < 0: skip_serializing_score returns true → field absent
  SConditional c = { .name = "alice", .score = -1 };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, c)!!;
  defer j.free();

  assert(j.value.d.get("name")!!.value.s == "alice");
  if (catch j.value.d.get("score")) { /* absent: correct */ } else { assert(false); }
}

fn void test_ser_conditional_skip_false() @test {
  // score >= 0: skip_serializing_score returns false → field present
  SConditional c = { .name = "bob", .score = 99 };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, c)!!;
  defer j.free();

  assert(j.value.d.get("score")!!.value.i == 99);
}

// ── Tests: enum serialization ─────────────────────────────────────────────────

fn void test_ser_enum_name() @test {
  // default behavior: serialize as the variant name string
  SDirection d = SDirection.EAST;
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, d)!!;
  assert(j.kind == JsonValueKind.STRING);
  assert(j.value.s == "EAST");
}

fn void test_ser_enum_all_names() @test {
  SDirection[4] dirs = { SDirection.NORTH, SDirection.SOUTH, SDirection.EAST, SDirection.WEST };
  String[4] expected = { "NORTH", "SOUTH", "EAST", "WEST" };
  foreach (i, d : dirs) {
    JsonSerializer s = json::serializer();
    JsonValue j = ser::serialize(&s, d)!!;
    assert(j.kind == JsonValueKind.STRING);
    assert(j.value.s == expected[i]);
  }
}

fn void test_ser_enum_ordinal() @test {
  // BRONZE=0, SILVER=1, GOLD=2
  JsonSerializer s0 = json::serializer();
  JsonSerializer s1 = json::serializer();
  JsonSerializer s2 = json::serializer();
  JsonValue j0 = ser::serialize(&s0, SRank.BRONZE)!!;
  JsonValue j1 = ser::serialize(&s1, SRank.SILVER)!!;
  JsonValue j2 = ser::serialize(&s2, SRank.GOLD)!!;

  assert(j0.kind == JsonValueKind.INT && j0.value.i == 0);
  assert(j1.kind == JsonValueKind.INT && j1.value.i == 1);
  assert(j2.kind == JsonValueKind.INT && j2.value.i == 2);
}

fn void test_ser_enum_field() @test {
  // serialize via associated field "hex"
  JsonSerializer sr = json::serializer();
  JsonSerializer sg = json::serializer();
  JsonSerializer sb = json::serializer();
  JsonValue jr = ser::serialize(&sr, SColor.RED)!!;
  JsonValue jg = ser::serialize(&sg, SColor.GREEN)!!;
  JsonValue jb = ser::serialize(&sb, SColor.BLUE)!!;

  assert(jr.kind == JsonValueKind.STRING && jr.value.s == "#FF0000");
  assert(jg.kind == JsonValueKind.STRING && jg.value.s == "#00FF00");
  assert(jb.kind == JsonValueKind.STRING && jb.value.s == "#0000FF");
}

// ── Tests: Maybe ──────────────────────────────────────────────────────────────

fn void test_ser_maybe_empty() @test {
  SWithMaybe wm = { .name = "empty", .opt = {} };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, wm)!!;
  defer j.free();

  assert(j.value.d.get("opt")!!.kind == JsonValueKind.NULL);
}

fn void test_ser_maybe_value() @test {
  SWithMaybe wm = { .name = "full", .opt = maybe::value{int}(42) };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, wm)!!;
  defer j.free();

  JsonValue opt = j.value.d.get("opt")!!;
  assert(opt.kind == JsonValueKind.INT);
  assert(opt.value.i == 42);
}

// ── Tests: validator ──────────────────────────────────────────────────────────

fn void test_ser_validator_pass() @test {
  SWithValidator wv = { .name = "valid-name" };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, wv)!!;
  defer j.free();

  assert(j.value.d.get("name")!!.value.s == "valid-name");
}

fn void test_ser_validator_fail() @test {
  // empty name fails the validator → VALIDATOR_ERROR
  SWithValidator wv = { .name = "" };
  JsonSerializer s = json::serializer();
  JsonValue? j = ser::serialize(&s, wv);
  if (catch err = j) {
    assert(err == ser::VALIDATOR_ERROR);
  } else {
    assert(false); // must have faulted
  }
}

// ── Tests: CSV serialization ──────────────────────────────────────────────────

fn void test_ser_csv_columns() @test {
  SWeatherRow[2] rows = {
    { .city = "Paris",  .temp = 15.5, .sunny = true  },
    { .city = "Berlin", .temp =  8.0, .sunny = false },
  };
  CSVSerializer s = csv::serializer();
  CSVDocument doc = ser::serialize(&s, rows)!!;

  // three columns: city, temp, sunny
  assert(doc.len() == 3);
  // each column has exactly two rows
  assert(doc.get("city")!!.len()  == 2);
  assert(doc.get("temp")!!.len()  == 2);
  assert(doc.get("sunny")!!.len() == 2);
}

fn void test_ser_csv_values() @test {
  SWeatherRow[2] rows = {
    { .city = "Lyon",  .temp = 22.0, .sunny = true  },
    { .city = "Nice",  .temp = 27.5, .sunny = true  },
  };
  CSVSerializer s = csv::serializer();
  CSVDocument doc = ser::serialize(&s, rows)!!;

  CSVValueList cities = doc.get("city")!!;
  assert(cities[0].kind == CSVValueKind.STRING && cities[0].value.s == "Lyon");
  assert(cities[1].kind == CSVValueKind.STRING && cities[1].value.s == "Nice");

  CSVValueList temps = doc.get("temp")!!;
  assert(temps[0].kind == CSVValueKind.FLOAT);
  assert(temps[1].kind == CSVValueKind.FLOAT);

  CSVValueList sunny = doc.get("sunny")!!;
  assert(sunny[0].kind == CSVValueKind.BOOL && sunny[0].value.b == true);
  assert(sunny[1].kind == CSVValueKind.BOOL && sunny[1].value.b == true);
}

fn void test_ser_csv_to_string_has_header() @test {
  SWeatherRow[1] rows = { { .city = "Toulouse", .temp = 18.0, .sunny = false } };
  CSVSerializer s = csv::serializer();
  CSVDocument doc = ser::serialize(&s, rows)!!;
  String out = doc.to_string();

  // output must be non-empty and start with a quoted header
  assert(out.len > 0);
  assert(out.starts_with(`"`));
  // all header names present in output
  if (catch out.index_of("city"))  { assert(false); }
  if (catch out.index_of("temp"))  { assert(false); }
  if (catch out.index_of("sunny")) { assert(false); }
  if (catch out.index_of("Toulouse")) { assert(false); }
}
