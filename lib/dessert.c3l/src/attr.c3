module dessert;
import std::collections::map;

enum DessertEnum {
  NAME,
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

struct DessertFieldConfig {
  bool skip;
  bool skip_if_empty;
  String rename;
  String[] aliases;
  String validator;
  FieldAttrs fmt;
  bool flatten;
}

attrdef @DField(DessertFieldConfig config) = @tag("dessert:ser", config), @tag("dessert:des", config);
attrdef @DFieldSer(DessertFieldConfig config) = @tag("dessert:ser", config);
attrdef @DFieldDes(DessertFieldConfig config) = @tag("dessert:des", config);

struct DessertEnumConfig {
  DessertEnum as;
  String field;
}

attrdef @DEnum(DessertEnumConfig config) = @tag("dessert:ser:enum", config), @tag("dessert:des:enum", config);
attrdef @DEnumSer(DessertEnumConfig config) = @tag("dessert:ser:enum", config);
attrdef @DEnumDes(DessertEnumConfig config) = @tag("dessert:des:enum", config);

struct DessertStructConfig {
  bool deny_unknown_fields;
}
attrdef @DStruct(DessertStructConfig config) = @tag("dessert:ser:struct", config), @tag("dessert:des:struct", config);
attrdef @DStructSer(DessertStructConfig config) = @tag("dessert:ser:struct", config);
attrdef @DStructDes(DessertStructConfig config) = @tag("dessert:des:struct", config);


// Old, deprecated attributes
attrdef @Dessert(DessertFieldConfig config) @deprecated("Use @DField instead") = @tag("dessert:ser", config), @tag("dessert:des", config);
attrdef @DessertSer(DessertFieldConfig config) @deprecated("Use @DFieldSer instead") = @tag("dessert:ser", config);
attrdef @DessertDes(DessertFieldConfig config) @deprecated("Use @DFieldDes instead") = @tag("dessert:des", config);

attrdef @DessertStruct(DessertStructConfig config) @deprecated("Use @DStruct instead") = @tag("dessert:ser:struct", config), @tag("dessert:des:struct", config);
attrdef @DessertStructSer(DessertStructConfig config) @deprecated("Use @DStructSer instead") = @tag("dessert:ser:struct", config);
attrdef @DessertStructDes(DessertStructConfig config) @deprecated("Use @DStructDes instead") = @tag("dessert:des:struct", config);

attrdef @DessertEnum(DessertEnumConfig config) @deprecated("Use @DEnum instead") = @tag("dessert:ser:enum", config), @tag("dessert:des:enum", config);
attrdef @DessertEnumSer(DessertEnumConfig config) @deprecated("Use @DEnumSer instead") = @tag("dessert:ser:enum", config);
attrdef @DessertEnumDes(DessertEnumConfig config) @deprecated("Use @DEnummDes instead") = @tag("dessert:des:enum", config);
