module derive;

macro derive(String $typename, ...) @const @builtin {
  var $out = "";
  $for int $i = 0; $i < $vaarg.len; $i++:
    $out +++= $eval($stringify($vaarg[$i]))($typename);
  $endfor
  return $out;
}

module derive::dessert;

macro serialize(String $typename) @const {
  return @sprintf("fn void? %s.serialize(&self, Serializer ser) => dessert::ser::impl_serialize(self, ser);\n", $typename);
}
macro deserialize(String $typename) @const {
  return @sprintf("fn void? %s.deserialize(&self, Deserializer des) => dessert::des::impl_deserialize(self, des);\n", $typename);
}

module derive;

macro dessert(String $typename) @const {
  return @sprintf("%s\n%s", dessert::serialize($typename), dessert::deserialize($typename));
}
