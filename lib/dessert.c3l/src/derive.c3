module derive;

macro derive(...) <Type> @const @builtin {
  var $out = "";
  $for int $i = 0; $i < $vacount; $i++:
    $out +++= $eval($stringify($vaarg[$i]))(Type);
  $endfor
  return $out;
}

macro serialize($Type) @const {
  return @sprintf("fn void? %s.serialize(&self, Serializer ser) => ser::impl_serialize(self, ser);\n", $Type::name);
}
macro deserialize($Type) @const {
  return @sprintf("fn void? %s.deserialize(&self, Deserializer des) => des::impl_deserialize(self, des);\n", $Type::name);
}
