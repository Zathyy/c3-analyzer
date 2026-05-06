module derive;

macro derive(...) <Type> @const @builtin {
  var $out = "";
  $for int $i = 0; $i < $vaarg.len; $i++:
    $out +++= $eval($stringify($vaarg[$i]))(Type);
  $endfor
  return $out;
}

module derive::dessert;

macro serialize($Type) @const {
  return @sprintf("fn void? %s.serialize(&self, Serializer ser) => dessert::ser::impl_serialize(self, ser);\n", $Type::name);
}
macro deserialize($Type) @const {
  return @sprintf("fn void? %s.deserialize(&self, Deserializer des) => dessert::des::impl_deserialize(self, des);\n", $Type::name);
}

module derive;

macro dessert($Type) @const {
  return @sprintf("%s\n%s", dessert::serialize($Type), dessert::deserialize($Type));
}
