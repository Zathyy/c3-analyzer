module deserialize_test;
import std;
import dessert;
import json;

// ── Test types ───────────────────────────────────────────────────────────────

struct DPoint {
  int x;
  int y;
}
fn void? DPoint.serialize(&self, Serializer serializer)     => ser::impl_serialize(self, serializer);
fn void? DPoint.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

struct DBox {
  String label;
  DPoint center;
}
fn void? DBox.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

struct DWithPointer {
  String name;
  DPoint* extra;
}
fn void? DWithPointer.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

struct DWithArray {
  String  tag;
  DPoint[] items;
}
fn void? DWithArray.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// skip=true on des: JSON field is consumed but not assigned to the struct field
struct DWithSkipDes {
  String kept;
  String dropped @DFieldDes({ .skip = true });
}
fn void? DWithSkipDes.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// rename: JSON key "alias" maps to field "original"
struct DWithRenameDes {
  String original @DFieldDes({ .rename = "alias" });
  int    count    @DFieldDes({ .rename = "num" });
}
fn void? DWithRenameDes.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// deny_unknown_fields: error on unexpected JSON keys
struct DDenyUnknown @DStruct({ .deny_unknown_fields = true }) {
  String name;
  int    value;
}
fn void? DDenyUnknown.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// Struct for duplicate key test
struct DDupCheck {
  String name;
  int    age;
}
fn void? DDupCheck.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// Default enum: serialize / deserialize by variant name
enum DDirection {
  NORTH,
  SOUTH,
  EAST,
  WEST,
}
fn void? DDirection.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

struct DWithDirection {
  String     label;
  DDirection dir;
}
fn void? DWithDirection.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// Ordinal enum: deserialize from integer position
enum DRank @DEnum({ .as = ORDINAL }) {
  BRONZE,
  SILVER,
  GOLD,
}
fn void? DRank.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

struct DWithRank {
  String label;
  DRank  rank;
}
fn void? DWithRank.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// Field enum: deserialize by matching an associated field value
enum DColor : (String hex) @DEnum({ .as = FIELD, .field = "hex" }) {
  RED   { "#FF0000" },
  GREEN { "#00FF00" },
  BLUE  { "#0000FF" },
}
fn void? DColor.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

struct DWithColor {
  String label;
  DColor color;
}
fn void? DWithColor.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// Invalid enum (no such variant) → INVALID_ENUM_VALUE
struct DWithDirInvalid {
  DDirection dir;
}
fn void? DWithDirInvalid.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// Maybe field
struct DWithMaybe {
  String    name;
  Maybe{int} opt;
}
fn void? DWithMaybe.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// Full struct for roundtrip testing (needs both ser + des)
struct DFull {
  String name;
  int    age;
  bool   active;
  double score;
}
fn void? DFull.serialize(&self, Serializer serializer)     => ser::impl_serialize(self, serializer);
fn void? DFull.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

struct DComplex {
  String   title;
  DPoint   origin;
  DPoint[] path;
  DPoint*  target;
}
fn void? DComplex.serialize(&self, Serializer serializer)     => ser::impl_serialize(self, serializer);
fn void? DComplex.deserialize(&self, Deserializer deserializer) => des::impl_deserialize(self, deserializer);

// ── Tests: JSON primitives ────────────────────────────────────────────────────

fn void test_des_bool_true() @test {
  bool v = des::deserialize{bool}(&&json::deserializer("true"))!!;
  assert(v == true);
}

fn void test_des_bool_false() @test {
  bool v = des::deserialize{bool}(&&json::deserializer("false"))!!;
  assert(v == false);
}

fn void test_des_long_positive() @test {
  long v = des::deserialize{long}(&&json::deserializer("42"))!!;
  assert(v == 42);
}

fn void test_des_long_negative() @test {
  long v = des::deserialize{long}(&&json::deserializer("-100"))!!;
  assert(v == -100);
}

fn void test_des_double() @test {
  double v = des::deserialize{double}(&&json::deserializer("2.718"))!!;
  double diff = v - 2.718;
  if (diff < 0) diff = -diff;
  assert(diff < 1e-9);
}

fn void test_des_string() @test {
  String v = des::deserialize{String}(&&json::deserializer(`"hello"`))!!;
  assert(v == "hello");
}

fn void test_des_empty_string() @test {
  String v = des::deserialize{String}(&&json::deserializer(`""`))!!;
  assert(v.len == 0);
}

// ── Tests: JSON escape sequences in strings ───────────────────────────────────

fn void test_des_escape_newline() @test {
  String v = des::deserialize{String}(&&json::deserializer(`"line1\nline2"`))!!;
  assert(v.len == 11); // "line1" + '\n' + "line2"
  assert(v[5] == '\n');
}

fn void test_des_escape_tab() @test {
  String v = des::deserialize{String}(&&json::deserializer(`"col1\tcol2"`))!!;
  assert(v[4] == '\t');
}

fn void test_des_escape_backslash() @test {
  String v = des::deserialize{String}(&&json::deserializer(`"a\\b"`))!!;
  assert(v == `a\b`);
}

fn void test_des_escape_quote() @test {
  String v = des::deserialize{String}(&&json::deserializer(`"say \"hi\""`) )!!;
  assert(v == `say "hi"`);
}

fn void test_des_escape_carriage_return() @test {
  String v = des::deserialize{String}(&&json::deserializer(`"a\rb"`))!!;
  assert(v[1] == '\r');
}

// ── Tests: struct deserialization ─────────────────────────────────────────────

fn void test_des_simple_struct() @test {
  const String JSON = `{"x": 7, "y": -3}`;
  DPoint p = des::deserialize{DPoint}(&&json::deserializer(JSON))!!;
  assert(p.x == 7);
  assert(p.y == -3);
}

fn void test_des_struct_whitespace() @test {
  // whitespace around tokens must be ignored
  const String JSON = `{  "x" :  42 ,  "y"  :  0  }`;
  DPoint p = des::deserialize{DPoint}(&&json::deserializer(JSON))!!;
  assert(p.x == 42);
  assert(p.y == 0);
}

fn void test_des_nested_struct() @test {
  const String JSON = `{"label": "mybox", "center": {"x": 5, "y": 8}}`;
  DBox b = des::deserialize{DBox}(&&json::deserializer(JSON))!!;
  assert(b.label == "mybox");
  assert(b.center.x == 5);
  assert(b.center.y == 8);
}

fn void test_des_null_pointer() @test {
  const String JSON = `{"name": "test", "extra": null}`;
  DWithPointer wp = des::deserialize{DWithPointer}(&&json::deserializer(JSON))!!;
  assert(wp.name == "test");
  assert(wp.extra == null);
}

fn void test_des_non_null_pointer() @test {
  const String JSON = `{"name": "test", "extra": {"x": 11, "y": 22}}`;
  DWithPointer wp = des::deserialize{DWithPointer}(&&json::deserializer(JSON))!!;
  assert(wp.name == "test");
  assert(wp.extra != null);
  assert(wp.extra.x == 11);
  assert(wp.extra.y == 22);
}

fn void test_des_array() @test {
  const String JSON = `{"tag": "pts", "items": [{"x":1,"y":2},{"x":3,"y":4}]}`;
  DWithArray wa = des::deserialize{DWithArray}(&&json::deserializer(JSON))!!;
  assert(wa.tag == "pts");
  assert(wa.items.len == 2);
  assert(wa.items[0].x == 1);
  assert(wa.items[0].y == 2);
  assert(wa.items[1].x == 3);
  assert(wa.items[1].y == 4);
}

fn void test_des_empty_array() @test {
  const String JSON = `{"tag": "empty", "items": []}`;
  DWithArray wa = des::deserialize{DWithArray}(&&json::deserializer(JSON))!!;
  assert(wa.items.len == 0);
}

fn void test_des_missing_field_stays_default() @test {
  // field "y" absent from JSON → stays at 0
  const String JSON = `{"x": 5}`;
  DPoint p = des::deserialize{DPoint}(&&json::deserializer(JSON))!!;
  assert(p.x == 5);
  assert(p.y == 0);
}

// ── Tests: attributes ─────────────────────────────────────────────────────────

fn void test_des_skip_field_with_key_present() @test {
  // "dropped" key is in the JSON but must not be assigned to the struct field
  const String JSON = `{"kept": "visible", "dropped": "invisible"}`;
  DWithSkipDes v = des::deserialize{DWithSkipDes}(&&json::deserializer(JSON))!!;
  assert(v.kept == "visible");
  assert(v.dropped == ""); // skip=true: value consumed but not stored
}

fn void test_des_skip_field_with_key_absent() @test {
  // "dropped" key is absent → field stays at default
  const String JSON = `{"kept": "only"}`;
  DWithSkipDes v = des::deserialize{DWithSkipDes}(&&json::deserializer(JSON))!!;
  assert(v.kept == "only");
  assert(v.dropped == "");
}

fn void test_des_rename() @test {
  // JSON uses the renamed keys "alias" and "num"
  const String JSON = `{"alias": "hello", "num": 7}`;
  DWithRenameDes v = des::deserialize{DWithRenameDes}(&&json::deserializer(JSON))!!;
  assert(v.original == "hello");
  assert(v.count == 7);
}

fn void test_des_extra_fields_ignored() @test {
  // extra JSON fields not in the struct are silently skipped
  const String JSON = `{"name": "alice", "value": 10, "unknown_field": "surprise", "another": 99}`;
  DDenyUnknown? v = des::deserialize{DDenyUnknown}(&&json::deserializer(JSON));
  // DDenyUnknown has deny_unknown_fields so this MUST fault
  if (catch err = v) {
    assert(err == des::UNKNOWN_FIELD);
  } else {
    assert(false);
  }
}

fn void test_des_extra_fields_ignored_without_deny() @test {
  // without deny_unknown_fields, extra keys are silently consumed
  const String JSON = `{"x": 1, "y": 2, "z": 999, "label": "extra"}`;
  DPoint p = des::deserialize{DPoint}(&&json::deserializer(JSON))!!;
  assert(p.x == 1);
  assert(p.y == 2);
}

fn void test_des_deny_unknown_fields() @test {
  const String JSON = `{"name": "bob", "value": 5, "nope": "bad"}`;
  DDenyUnknown? v = des::deserialize{DDenyUnknown}(&&json::deserializer(JSON));
  if (catch err = v) {
    assert(err == des::UNKNOWN_FIELD);
  } else {
    assert(false); // must have faulted
  }
}

fn void test_des_deny_unknown_fields_passes_when_clean() @test {
  // all fields known → no fault
  const String JSON = `{"name": "bob", "value": 5}`;
  DDenyUnknown v = des::deserialize{DDenyUnknown}(&&json::deserializer(JSON))!!;
  assert(v.name == "bob");
  assert(v.value == 5);
}

fn void test_des_duplicate_key() @test {
  // same key appears twice → DUPLICATED_KEY
  const String JSON = `{"name": "first", "age": 1, "name": "second"}`;
  DDupCheck? v = des::deserialize{DDupCheck}(&&json::deserializer(JSON));
  if (catch err = v) {
    assert(err == des::DUPLICATED_KEY);
  } else {
    assert(false); // must have faulted
  }
}

// ── Tests: enum deserialization ───────────────────────────────────────────────

fn void test_des_enum_name() @test {
  const String JSON = `{"label": "go", "dir": "EAST"}`;
  DWithDirection v = des::deserialize{DWithDirection}(&&json::deserializer(JSON))!!;
  assert(v.dir == DDirection.EAST);
}

fn void test_des_enum_name_all_variants() @test {
  String[4] jsons = {
    `{"label": "a", "dir": "NORTH"}`,
    `{"label": "b", "dir": "SOUTH"}`,
    `{"label": "c", "dir": "EAST"}`,
    `{"label": "d", "dir": "WEST"}`,
  };
  DDirection[4] expected = { DDirection.NORTH, DDirection.SOUTH, DDirection.EAST, DDirection.WEST };
  foreach (i, js : jsons) {
    DWithDirection v = des::deserialize{DWithDirection}(&&json::deserializer(js))!!;
    assert(v.dir == expected[i]);
  }
}

fn void test_des_enum_invalid_name() @test {
  // "NORTHEAST" is not a valid DDirection variant → INVALID_ENUM_VALUE
  const String JSON = `{"label": "bad", "dir": "NORTHEAST"}`;
  DWithDirection? v = des::deserialize{DWithDirection}(&&json::deserializer(JSON));
  if (catch err = v) {
    assert(err == des::INVALID_ENUM_VALUE);
  } else {
    assert(false);
  }
}

fn void test_des_enum_ordinal() @test {
  // BRONZE=0, SILVER=1, GOLD=2
  const String JSON0 = `{"label": "a", "rank": 0}`;
  const String JSON1 = `{"label": "b", "rank": 1}`;
  const String JSON2 = `{"label": "c", "rank": 2}`;
  DWithRank v0 = des::deserialize{DWithRank}(&&json::deserializer(JSON0))!!;
  DWithRank v1 = des::deserialize{DWithRank}(&&json::deserializer(JSON1))!!;
  DWithRank v2 = des::deserialize{DWithRank}(&&json::deserializer(JSON2))!!;
  assert(v0.rank == DRank.BRONZE);
  assert(v1.rank == DRank.SILVER);
  assert(v2.rank == DRank.GOLD);
}

fn void test_des_enum_field() @test {
  // DColor uses the "hex" associated field for lookup
  const String JSON = `{"label": "paint", "color": "#00FF00"}`;
  DWithColor v = des::deserialize{DWithColor}(&&json::deserializer(JSON))!!;
  assert(v.color == DColor.GREEN);
}

fn void test_des_enum_field_all_variants() @test {
  String[3] jsons = {
    `{"label": "r", "color": "#FF0000"}`,
    `{"label": "g", "color": "#00FF00"}`,
    `{"label": "b", "color": "#0000FF"}`,
  };
  DColor[3] expected = { DColor.RED, DColor.GREEN, DColor.BLUE };
  foreach (i, js : jsons) {
    DWithColor v = des::deserialize{DWithColor}(&&json::deserializer(js))!!;
    assert(v.color == expected[i]);
  }
}

// ── Tests: Maybe ──────────────────────────────────────────────────────────────

fn void test_des_maybe_null() @test {
  const String JSON = `{"name": "empty", "opt": null}`;
  DWithMaybe v = des::deserialize{DWithMaybe}(&&json::deserializer(JSON))!!;
  assert(v.name == "empty");
  // opt must be empty (get() must fault)
  if (catch v.opt.get()) { /* correct: empty Maybe */ } else { assert(false); }
}

fn void test_des_maybe_value() @test {
  const String JSON = `{"name": "full", "opt": 99}`;
  DWithMaybe v = des::deserialize{DWithMaybe}(&&json::deserializer(JSON))!!;
  assert(v.name == "full");
  assert(v.opt.get()!! == 99);
}

// ── Tests: JSON parse errors ──────────────────────────────────────────────────

fn void test_des_invalid_object() @test {
  DPoint? p = des::deserialize{DPoint}(&&json::deserializer("not-an-object"));
  assert(@catch(p));
}

fn void test_des_invalid_bool() @test {
  bool? b = des::deserialize{bool}(&&json::deserializer("maybe"));
  assert(@catch(b));
}

fn void test_des_invalid_number() @test {
  // leading zero followed by digit is invalid JSON number
  long? n = des::deserialize{long}(&&json::deserializer("01"));
  assert(@catch(n));
}

// ── Tests: large / edge-case numbers ─────────────────────────────────────────

fn void test_des_large_int() @test {
  // INT_MAX / INT_MIN — representable exactly as f64 (2^31 < 2^53)
  const String JSON = `{"x": 2147483647, "y": -2000000000}`;
  DPoint p = des::deserialize{DPoint}(&&json::deserializer(JSON))!!;
  assert(p.x == 2147483647);
  assert(p.y == -2000000000);
}

fn void test_des_zero_values() @test {
  const String JSON = `{"x": 0, "y": 0}`;
  DPoint p = des::deserialize{DPoint}(&&json::deserializer(JSON))!!;
  assert(p.x == 0);
  assert(p.y == 0);
}

// ── Tests: Object* (next_any) ─────────────────────────────────────────────────

fn void test_des_object_any_basic() @test {
  const String JSON = `{"count": 3, "ok": true, "msg": "hello", "empty": null}`;
  Object* obj = des::deserialize{Object*}(&&json::debug_deserializer(JSON))!!;
  assert(obj != null);
}

fn void test_des_object_any_nested() @test {
  const String JSON = `{"outer": {"inner": 42}}`;
  Object* obj = des::deserialize{Object*}(&&json::deserializer(JSON))!!;
  assert(obj != null);
}

// ── Tests: roundtrip ─────────────────────────────────────────────────────────

fn void test_des_roundtrip_simple() @test {
  DFull original = { .name = "Alice", .age = 30, .active = true, .score = 9.75 };
  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, original)!!;
  defer j.free();

  DFull copy = des::deserialize{DFull}(&&json::deserializer(j.to_string()!!))!!;
  assert(copy.name   == "Alice");
  assert(copy.age    == 30);
  assert(copy.active == true);
  double diff = copy.score - 9.75;
  if (diff < 0) diff = -diff;
  assert(diff < 1e-6);
}

fn void test_des_roundtrip_complex() @test {
  DPoint[2] path_arr = { { .x = 1, .y = 0 }, { .x = 2, .y = 3 } };
  DPoint tgt = { .x = 99, .y = -1 };
  DComplex original = {
    .title  = "route",
    .origin = { .x = 0, .y = 0 },
    .path   = path_arr[..],
    .target = &tgt,
  };

  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, original)!!;
  defer j.free();

  DComplex copy = des::deserialize{DComplex}(&&json::deserializer(j.to_string()!!))!!;
  assert(copy.title        == "route");
  assert(copy.origin.x     == 0);
  assert(copy.origin.y     == 0);
  assert(copy.path.len     == 2);
  assert(copy.path[0].x    == 1);
  assert(copy.path[1].x    == 2);
  assert(copy.target       != null);
  assert(copy.target.x     == 99);
  assert(copy.target.y     == -1);
}

fn void test_des_roundtrip_null_pointer() @test {
  DComplex original = {
    .title  = "no-target",
    .origin = { .x = 5, .y = 5 },
    .path   = {},
    .target = null,
  };

  JsonSerializer s = json::serializer();
  JsonValue j = ser::serialize(&s, original)!!;
  defer j.free();

  DComplex copy = des::deserialize{DComplex}(&&json::deserializer(j.to_string()!!))!!;
  assert(copy.title    == "no-target");
  assert(copy.target   == null);
  assert(copy.path.len == 0);
}
