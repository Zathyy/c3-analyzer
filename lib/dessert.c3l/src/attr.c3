module dessert;
import std::collections::map;

enum DessertEnum {
  DESCRIPTION,
  ORDINAL,
  FIELD,
}


typedef FieldAttrs = String[];

fn String? FieldAttrs.get(&self, String needle) {
  foreach(s : self) {
    if (s == needle) return "true";

    if (s.starts_with(needle)) {
      return s.tsplit("=", 2)[1];
    }
  }

  return NOT_FOUND~;
}

// struct DFieldTagConfig {
//   <* Specify another field to be used as the tag for this field type. *>
//   String by;
// }

struct DFieldConfig {
  bool skip;
  bool skip_if_empty;
  String rename;
  String[] aliases;
  String validator;
  FieldAttrs fmt;
  bool flatten;

  <*
    Specify another field to be used as the tag for this field type.
    *Only available for union fields*
  *>
  String tagged_by;
}

attrdef @DField(DFieldConfig config) = @tag("dessert:ser", config), @tag("dessert:des", config);
attrdef @DFieldSer(DFieldConfig config) = @tag("dessert:ser", config);
attrdef @DFieldDes(DFieldConfig config) = @tag("dessert:des", config);

struct DEnumConfig {
  DessertEnum as;
  String field;
}

attrdef @DEnum(DEnumConfig config) = @tag("dessert:ser:enum", config), @tag("dessert:des:enum", config);
attrdef @DEnumSer(DEnumConfig config) = @tag("dessert:ser:enum", config);
attrdef @DEnumDes(DEnumConfig config) = @tag("dessert:des:enum", config);

enum CaseConvention : (String example) {
  VERBATIM { "verbatim" },
  KEBAB_CASE { "kebab-case" },
  CAMEL_CASE { "camelCase" },
  PASCAL_CASE { "PascalCase" },
  SCREAMING_SNAKE_CASE { "SCREAMING_SNAKE_CASE" },
  SNAKE_CASE { "snake_case" },
  LOWER_CASE { "lower" },
  UPPER_CASE { "upper" },
}

struct DStructConfig {
  bool deny_unknown_fields;
  CaseConvention rename_all;
}
attrdef @DStruct(DStructConfig config) = @tag("dessert:ser:struct", config), @tag("dessert:des:struct", config);
attrdef @DStructSer(DStructConfig config) = @tag("dessert:ser:struct", config);
attrdef @DStructDes(DStructConfig config) = @tag("dessert:des:struct", config);

struct DUnionConfig {
  bool inlined;
}
attrdef @DUnion(DUnionConfig config) = @tag("dessert:ser:union", config), @tag("dessert:des:union", config);
attrdef @DUnionSer(DUnionConfig config) = @tag("dessert:ser:union", config);
attrdef @DUnionDes(DUnionConfig config) = @tag("dessert:des:union", config);

// Old, deprecated attributes
attrdef @Dessert(DFieldConfig config) @deprecated("Use @DField instead") = @tag("dessert:ser", config), @tag("dessert:des", config);
attrdef @DessertSer(DFieldConfig config) @deprecated("Use @DFieldSer instead") = @tag("dessert:ser", config);
attrdef @DessertDes(DFieldConfig config) @deprecated("Use @DFieldDes instead") = @tag("dessert:des", config);

attrdef @DessertStruct(DStructConfig config) @deprecated("Use @DStruct instead") = @tag("dessert:ser:struct", config), @tag("dessert:des:struct", config);
attrdef @DessertStructSer(DStructConfig config) @deprecated("Use @DStructSer instead") = @tag("dessert:ser:struct", config);
attrdef @DessertStructDes(DStructConfig config) @deprecated("Use @DStructDes instead") = @tag("dessert:des:struct", config);

attrdef @DessertEnum(DEnumConfig config) @deprecated("Use @DEnum instead") = @tag("dessert:ser:enum", config), @tag("dessert:des:enum", config);
attrdef @DessertEnumSer(DEnumConfig config) @deprecated("Use @DEnumSer instead") = @tag("dessert:ser:enum", config);
attrdef @DessertEnumDes(DEnumConfig config) @deprecated("Use @DEnummDes instead") = @tag("dessert:des:enum", config);
