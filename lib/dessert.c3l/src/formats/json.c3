module json;
import std::collections::map;
import std::collections::list;
import std::io;
import dessert::des;

enum JsonValueKind {
  INT,
  FLOAT,
  BOOL,
  STRING,
  DICT,
  ARRAY,
  NULL,
}

struct JsonValue (Printable) {
  union value {
    long i;
    double f;
    bool b;
    String s;
    LinkedHashMap{String, JsonValue} d;
    List{JsonValue} l;
  }

  JsonValueKind kind;
}

fn void JsonValue.free(self) {
  switch(self.kind) {
    case NULL:
    case INT:
    case FLOAT:
    case BOOL:
    case STRING:
      break;
    case ARRAY:
      foreach (item : self.value.l) {
        item.free();
      }
      self.value.l.free();
    case DICT:
      self.value.d.@each_entry(; entry) {
        entry.value.free();
      };
      self.value.d.free();
  }

}

fn void? JsonValue.print(self) {
  switch(self.kind) {
    case NULL:
      io::print("null");
    case INT:
      io::printf("%s", self.value.i);
    case FLOAT:
      io::printf("%s", self.value.f);
    case BOOL:
      io::printf("%s", self.value.b);
    case STRING:
      io::printf("\"%s\"", self.value.s);
    case ARRAY:
      io::printf("[");
      ulong l_len = self.value.l.len();
      foreach (i, item : self.value.l) {
        item.print()!;
        if (i < l_len - 1) {
          io::print(", ");
        }
      }
     io::printf("]");
    case DICT:
      io::printf("{");
      ulong d_len = self.value.d.len();
      
      int i = 0;
      self.value.d.@each_entry(; entry) {
        io::printf("\"%s\": ", entry.key);
        entry.value.print()!;
        if (i < d_len - 1) {
          io::print(", ");
        }
        i++;
      };
      io::printf("}");

    default:
      return NOT_FOUND~;
  }
}

fn String? JsonValue.to_string(self) {
  switch(self.kind) {
    case NULL:
      return "null";
    case INT:
      return string::format(mem, "%s", self.value.i);
    case FLOAT:
      return string::format(mem, "%s", self.value.f);
    case BOOL:
      return string::format(mem, "%s", self.value.b);
    case STRING:
      return string::format(mem, "\"%s\"", self.value.s.replace(mem, "\"", "\\\""));
    case ARRAY:
      DString s;
      s.init(mem);
      s.append("[");
      ulong l_len = self.value.l.len();
      foreach (i, item : self.value.l) {
        s.append(item.to_string()!);
        if (i < l_len - 1) {
          s.append(", ");
        }
      }
      s.append("]");
      return s.str_view();
    case DICT:
      DString s;
      s.init(mem);
      s.append("{");
      ulong d_len = self.value.d.len();
      
      int i = 0;
      self.value.d.@each_entry(; entry) {
        s.append(string::format(mem, "\"%s\": ", entry.key.replace(mem, "\"", "\\\"")));
        s.append(entry.value.to_string()!);
        if (i < d_len - 1) {
          s.append(", ");
        }
        i++;
      };
      s.append("}");
      return s.str_view();

    default:
      return NOT_FOUND~;
  }
}

fn String to_pretty_string(JsonValue self, int indent = 2, int depth = 0) @private {
  DString pad;
  pad.init(mem);
  defer pad.free();
  pad.append_repeat(' ', (usz) (indent * depth));

  DString inner_pad;
  inner_pad.init(mem);
  inner_pad.append_repeat(' ', (usz) (indent * (depth + 1)));

  switch (self.kind) {
    case NULL:
      return "null";
    case INT:
      return string::format(mem, "%d", self.value.i);
    case FLOAT:
      return string::format(mem, "%g", self.value.f);
    case BOOL:
      return string::format(mem, "%s", self.value.b ? "true" : "false");
    case STRING:
      return string::format(mem, "\"%s\"", self.value.s.replace(mem, "\"", "\\\""));
    case ARRAY:
      DString s;
      s.init(mem);
      ulong l_len = self.value.l.len();
      if (l_len == 0) return "[]";
      s.append("[\n");
      foreach (i, item : self.value.l) {
        s.append(inner_pad);
        s.append(to_pretty_string(item, indent, depth + 1));
        if (i < l_len - 1) s.append(",");
        s.append("\n");
      }
      s.append(pad);
      s.append("]");
      return s.str_view();
    case DICT:
      DString s;
      s.init(mem);
      ulong d_len = self.value.d.len();
      if (d_len == 0) return "{}";
      s.append("{\n");
      int i = 0;
      self.value.d.@each_entry(; entry) {
        s.append(inner_pad);
        s.append(string::format(mem, "\"%s\": ", entry.key.replace(mem, "\"", "\\\"")));
        s.append(to_pretty_string(entry.value, indent: indent, depth: depth + 1));
        if (i < d_len - 1) s.append(",");
        s.append("\n");
        i++;
      };
      s.append(pad);
      s.append("}");
      return s.str_view();
  }
}

fn String JsonValue.to_pretty_string(self, int indent = 2) {
  return to_pretty_string(self, indent);
}


module dessert::format::json;
import dessert::ser;
import dessert::des;
import json;
import std::collections::maybe;
import std::collections::list;
import std::collections::map;
import std::collections::object;
import std::io;
import std::math;

faultdef INVALID_JSON_TYPE;

struct JsonSerializer (Serializer) {
  List{JsonValue} output;
}

fn JsonSerializer serializer() {
  List{JsonValue} output;
  output.init(mem);
  return { .output = output };
}

fn void? JsonSerializer.serialize_null(&self) @dynamic {
  self.output.push({ .kind = JsonValueKind.NULL, .value = { .i = 0 } });
}

fn void? JsonSerializer.serialize_bool(&self, bool b) @dynamic {
  self.output.push({ .kind = JsonValueKind.BOOL, .value = { .b = b } });
}

fn void? JsonSerializer.serialize_long(&self, long i) @dynamic {
  self.output.push({ .kind = JsonValueKind.INT, .value = { .i = i } });
}

fn void? JsonSerializer.serialize_double(&self, double f) @dynamic {
  self.output.push({ .kind = JsonValueKind.FLOAT, .value = { .f = f } });
}

fn void? JsonSerializer.serialize_string(&self, String s) @dynamic {
  self.output.push({ .kind = JsonValueKind.STRING, .value = { .s = s } });
}

fn void? JsonSerializer.struct_start(&self, String name) @dynamic {
  LinkedHashMap{String, JsonValue} d;
  d.init(mem);
  self.output.push({ .kind = JsonValueKind.DICT, .value = { .d = d } });
}

fn void? JsonSerializer.struct_end(&self, String name) @dynamic {}

fn void? JsonSerializer.serialize_slice_start(&self, ulong len) @dynamic {}
fn void? JsonSerializer.serialize_slice_end(&self, ulong len) @dynamic {
  List{JsonValue} l;
  l.init(mem);
  for (int i = 0; i < len; i++) {
    l.push_front(self.output.pop()!);
  }
  self.output.push({ .kind = JsonValueKind.ARRAY, .value = { .l = l } });
}

fn void? JsonSerializer.serialize_field_start(&self, String name, FieldAttrs fmt) @dynamic {
  self.output.push({.kind = STRING, .value = {.s = name}});
}

fn void? JsonSerializer.serialize_field_end(&self, String name, FieldAttrs fmt) @dynamic {
  JsonValue value = self.output.pop()!;
  JsonValue key = self.output.pop()!;
  JsonValue obj = self.output.pop()!;
  if (obj.kind != JsonValueKind.DICT) return INVALID_JSON_TYPE~;
  if (key.kind != JsonValueKind.STRING) return INVALID_JSON_TYPE~;

  obj.value.d.set(key.value.s, value);
  self.output.push(obj);
}

fn JsonValue? JsonSerializer.result(&self) => self.output.pop();



faultdef 
  INVALID_OBJECT, 
  INVALID_FIELD, 
  INVALID_ARRAY, 
  INVALID_STRING,
  INVALID_ESCAPE,
  INVALID_NUMBER,
  INVALID_BOOLEAN,
  INVALID_NULL;

struct JsonDeserializer(Deserializer) {
  // JsonValue input;
  StringIterator input;
  int col;
  int line;
  bool is_debug;
}

fn Char32? JsonDeserializer.next(&self) @inline {
  Char32 c = self.input.next()!;
  if (self.is_debug) {
    if (c == '\n') {
      self.line += 1;
      self.col = 0;
    } else {
      self.col += 1;
    }
  }
  return c;
}

fn void? JsonDeserializer.skip_whitespace(&self) {
  while (self.input.has_next() && 
         (ascii::is_blank((char) self.input.peek()!) || '\n' == self.input.peek()!)) 
  {
    (void)self.next()!;
  }
}

fn JsonDeserializer? deserializer(String input) {
  return { .input = { .utf8 = input } };
}

fn JsonDeserializer? debug_deserializer(String input) {
  return { .input = { .utf8 = input }, .is_debug = true };
}

fn void? JsonDeserializer.struct_start(&self, String name) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != '{') {
    return INVALID_OBJECT~;
  }
}

fn bool? JsonDeserializer.has_next_field(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  if (next != '}') {
    if (next == ',') self.next()!;
    return true;
  }
  return false;
}

fn String? JsonDeserializer.next_field_name(&self) @dynamic {
  String field_name = self.next_string()!;
  self.skip_whitespace()!;
  if (self.next()! != ':') {
    return INVALID_FIELD~;
  }

  return field_name;
}

fn void? JsonDeserializer.struct_end(&self, String name) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != '}') {
    return INVALID_OBJECT~;
  }
}

fn void? JsonDeserializer.slice_start(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != '[') {
    return INVALID_ARRAY~;
  }
}
fn bool? JsonDeserializer.has_next_slice_item(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  if (next != ']') {
    if (next == ',') self.next()!;
    return true;
  }
  return false;
}
fn void? JsonDeserializer.slice_end(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != ']') {
    return INVALID_ARRAY~;
  }
}

fn void JsonDeserializer.print_error(&self, String message) {
  io::eprintfn("At %d:%d: %s", self.line, self.col, message);
}

fn Object*? JsonDeserializer.next_any(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  switch {
    case next == '"':
      return object::new_string(tmem, self.next_string())!;

    case next == 't':
    case next == 'f':
      return object::new_bool(self.next_bool())!;

    case next == 'n':
      (void)self.next_null()!;
      return object::new_null();

    case next == '{':
      Object* o = object::new_obj(tmem);
      self.struct_start("")!;
      while(self.has_next_field()!) {
        String next_key = self.next_field_name()!;
        o.set(next_key, self.next_any())!;
      }
      self.struct_end("")!;
      return o;

    case next == '[':
      Object* o = object::new_obj(tmem);
      self.slice_start()!;
      while(self.has_next_slice_item()!) {
        o.push(self.next_any())!;
      }
      self.slice_end()!;
      return o;

    case ascii::is_digit((char) next):
      double value = self.next_double()!;
      if ((double) math::round(value) == value) {
        return object::new_int(tmem, (int128) value);
      }
      return object::new_float(tmem, value);
  }

  return INVALID_OBJECT~;
}

fn String? JsonDeserializer.next_string(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.next()!;
  if (next != '"') {
    if (self.is_debug) {
      self.print_error(string::tformat("Expected \", found %c", next));
    }
    return INVALID_STRING~;
  }
  DString val;
  val.init(mem);
  while (Char32 c = self.next()!, c != '"') {
    if (c == '\\') {
      Char32 escape = self.next()!;
      switch (escape) {
        case 'n':
          val.append('\n');
        case 'r':
          val.append('\r');
        case 't':
          val.append('\t');
        case '"':
          val.append('\"');
        case '\'':
          val.append('\'');
        case '\\':
          val.append('\\');
        default:
          return INVALID_ESCAPE~;
      }
    } else {
      val.append(c);
    }
  }

  // io::printfn("%c", self.input.peek()!);
  // io::printfn("%s", val);

  return val.str_view();
}

<* 
  Source (inspired by): https://github.com/c3lang/c3c/blob/d8636af7fa0edda737ac4c033f4fb3b7660ebede/lib/std/encoding/json.c3#L391
*>
fn double? JsonDeserializer.next_double(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 c = self.input.peek()!;
  @stack_mem(256; Allocator mem) {
    DString t = dstring::new_with_capacity(mem, 32);
    bool negate = c == '-';
    if (negate) {
      self.next()!;
      t.append(c);
      c = self.input.peek()!;
    }
    bool leading_zero = c == '0';
    while (ascii::is_digit((char) c)) {
      self.next()!;
      t.append(c);
      Char32? next = self.input.peek();
      if (catch next) {
        return t.str_view().to_double() ?? INVALID_NUMBER~;
      }
      c = next;
      if (leading_zero) {
        if (ascii::is_digit((char) c)) return INVALID_NUMBER~;
        leading_zero = false;
      }
    }
    if (c == '.') {
      self.next()!;
      t.append(c);
      Char32? next = self.input.peek();
      if (catch next) {
        return t.str_view().to_double() ?? INVALID_NUMBER~;
      }
      c = next;
      while (ascii::is_digit((char) c)) {
        self.next()!;
        t.append(c);
        Char32? next2 = self.input.peek();
        if (catch next2) {
          return t.str_view().to_double() ?? INVALID_NUMBER~;
        }
        c = next2;
      }
    }
    if ((c | 32) == 'e') {
      self.next()!;
      t.append(c);
      c = self.next()!;
      switch (c) {
        case '-':
        case '+':
          self.next()!;
          t.append(c);
          c = self.input.peek()!;
      }
      if (!ascii::is_digit((char) c)) return INVALID_NUMBER~;
      while (ascii::is_digit((char) c)) {
      self.next()!;
        t.append(c);
        Char32? next = self.input.peek();
        if (catch next) {
          return t.str_view().to_double() ?? INVALID_NUMBER~;
        }
        c = next;
      }
    }
    double? d = t.str_view().to_double() ?? INVALID_NUMBER~;
    return d;
  };
}

fn char? JsonDeserializer.next_char(&self) @dynamic {
  return (char) self.next_char()!;
}

fn long? JsonDeserializer.next_long(&self) @dynamic {
  return (long) self.next_double()!;
}

fn bool? JsonDeserializer.next_bool(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.next()!;
  switch (next) {
    case 't':
      $foreach $v : "rue": // skips 'rue'
        self.next()!;
      $endforeach
      return true;
    case 'f':
      $foreach $v : "alse": // skips 'alse'
        self.next()!;
      $endforeach
      return false;
    default:
      return INVALID_BOOLEAN~;
  }
}

fn bool? JsonDeserializer.next_null(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  switch (next) {
    case 'n':
      $foreach $v : "null":
        self.next()!;
      $endforeach
      return true;
    default:
      return false;
  }
}
