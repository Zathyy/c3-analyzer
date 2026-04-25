module csv;
import std::collections::map;
import std::collections::list;
import std::io;
import dessert::des;

enum CSVValueKind {
  INT,
  FLOAT,
  BOOL,
  STRING,
  NULL,
}

alias CSVValueList = List{CSVValue};
alias CSVDocument = LinkedHashMap{String, List{CSVValue}};

fn String CSVDocument.to_string(&self) {
  DString s;
  s.init(mem);

  ulong num_cols = self.len();
  ulong num_rows = 0;

  // Header row
  int col_i = 0;
  self.@each_entry(; entry) {
    s.append(string::format(mem, "\"%s\"", entry.key.replace(mem, "\"", "\\\"")));
    if (col_i < num_cols - 1) s.append(",");
    if (num_rows == 0) num_rows = entry.value.len();
    col_i++;
  };
  s.append("\n");

  // Data rows
  for (ulong row = 0; row < num_rows; row++) {
    col_i = 0;
    self.@each_entry(; entry) {
      if (row < entry.value.len()) {
        s.append(entry.value[row].to_string()!!);
      }
      if (col_i < num_cols - 1) s.append(",");
      col_i++;
    };
    s.append("\n");
  }

  return s.str_view();
}

struct CSVValue (Printable) {
  union value {
    long i;
    double f;
    bool b;
    String s;
  }

  CSVValueKind kind;
}

fn String? CSVValue.to_string(self) {
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
    default:
      return NOT_FOUND~;
  }
}


module dessert::format::csv;

import dessert::ser;
import dessert::des;
import csv;
import std::collections::maybe;
import std::collections::list;
import std::collections::map;
import std::collections::object;
import std::io;
import std::math;

faultdef INVALID_CSV_TYPE;

struct CSVSerializer (Serializer) {
  CSVDocument headers;
  List{CSVValue} output;
}

fn CSVSerializer serializer() {
  List{CSVValue} output;
  output.init(tmem);

  LinkedHashMap{String, CSVValueList} headers;
  headers.init(tmem);

  return { .output = output, .headers = headers };
}

fn void? CSVSerializer.serialize_null(&self) @dynamic {
  self.output.push({ .kind = CSVValueKind.NULL, .value = { .i = 0 } });
}

fn void? CSVSerializer.serialize_bool(&self, bool b) @dynamic {
  self.output.push({ .kind = CSVValueKind.BOOL, .value = { .b = b } });
}

fn void? CSVSerializer.serialize_long(&self, long i) @dynamic {
  self.output.push({ .kind = CSVValueKind.INT, .value = { .i = i } });
}

fn void? CSVSerializer.serialize_ulong(&self, ulong i) @dynamic {
  self.output.push({ .kind = CSVValueKind.INT, .value = { .i = (long) i } });
}

fn void? CSVSerializer.serialize_double(&self, double f) @dynamic {
  self.output.push({ .kind = CSVValueKind.FLOAT, .value = { .f = f } });
}

fn void? CSVSerializer.serialize_string(&self, String s) @dynamic {
  self.output.push({ .kind = CSVValueKind.STRING, .value = { .s = s } });
}

fn void? CSVSerializer.struct_start(&self, String name) @dynamic {}
fn void? CSVSerializer.struct_end(&self, String name) @dynamic {}
fn void? CSVSerializer.serialize_slice_start(&self, ulong len) @dynamic {}
fn void? CSVSerializer.serialize_slice_end(&self, ulong len) @dynamic {}

fn void? CSVSerializer.serialize_field_start(&self, String name, FieldAttrs fmt) @dynamic {
  if (catch self.headers.get(name)) {
    List{CSVValue} csv_values;
    csv_values.init(mem);
    self.headers.set(name, csv_values);
  }
}

fn void? CSVSerializer.serialize_field_end(&self, String name, FieldAttrs fmt) @dynamic {
  CSVValue value = self.output.pop()!;

  List{CSVValue} values = self.headers.get(name)!;
  values.push(value);
  self.headers.set(name, values);
}

fn CSVDocument? CSVSerializer.result(&self) => self.headers;
