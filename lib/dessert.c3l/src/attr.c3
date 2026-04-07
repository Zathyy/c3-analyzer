module dessert;

enum DessertEnum {
  NAME,
  ORDINAL,
  FIELD,
}

struct Dessert {
  bool skip;
  String rename;
  String[] aliases;
  String validator;
}

attrdef @Dessert(Dessert config) = @tag("dessert:ser", config), @tag("dessert:des", config);
attrdef @DessertSer(Dessert config) = @tag("dessert:ser", config);
attrdef @DessertDes(Dessert config) = @tag("dessert:des", config);

struct DessertEnumConfig {
  DessertEnum as;
  String field;
  DessertEnumConfig *ser;
  DessertEnumConfig *des;
}
attrdef @DessertEnum(DessertEnumConfig config) = @tag("dessert:ser:enum", config), @tag("dessert:des:enum", config);
attrdef @DessertEnumSer(DessertEnumConfig config) = @tag("dessert:ser:enum", config);
attrdef @DessertEnumDes(DessertEnumConfig config) = @tag("dessert:des:enum", config);
