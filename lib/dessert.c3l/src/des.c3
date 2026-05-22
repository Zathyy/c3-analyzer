module dessert::des;
import std::collections::list;
import std::collections::maybe;
import std::collections::object;
import std::io;
import dessert::utils;


interface Deserializer {
  fn void? struct_start(String name);
  fn bool? has_next_field();
  fn String? next_field_name();
  fn void? struct_end(String name);

  fn void? slice_start();
  fn bool? has_next_slice_item();
  fn void? slice_end();

  <*
    Returns :
    `true` if the next element is a null value and consume it. 
    `false` if the next element is not a null value and ***must not*** consume it.
  *>
  fn bool? next_null();

  fn bool? next_bool();
  fn long? next_long();
  fn String? next_string();
  fn double? next_double();

  fn Object*? next_any() @optional;

  fn char? next_char() @optional;
  fn ichar? next_ichar() @optional;

  fn short? next_short() @optional;
  fn int? next_int() @optional;
  fn int128? next_int128() @optional;

  fn ushort? next_ushort() @optional;
  fn uint? next_uint() @optional;
  fn ulong? next_ulong() @optional;
  fn uint128? next_uint128() @optional;

  fn ZString? next_zstring() @optional;

  fn float? next_float() @optional;
}

faultdef VALIDATOR_ERROR;
faultdef DUPLICATED_KEY, INVALID_ENUM_VALUE, UNKNOWN_FIELD, INLINED_UNION_BEFORE_TAG;

// Should be treated as a protocol, don't derive it directly
interface Deserializable {
  fn void? deserialize(Deserializer deserializer);
}

macro @is_deserializable($Output) {
  $Output $value;
  return $defined($value.deserialize) ||| ($defined($value.len) &&& $defined($value[0])) ||| 
    ($defined($value.get) &&& $defined($value.get()) &&& 
     ($defined($value.get()!) ||| $defined($value == maybe::value{$Typeof($value.value)}($value.value))));
}

macro deserialize(Deserializer deserializer) <Output> {
  Output value;
  $switch:
    $case Output::kind == POINTER:
      if (deserializer.next_null()!) {
        return null;
      } else {
        Output v = alloc::new(tmem, Output::inner);
        *v = deserialize{Output::inner}(deserializer)!;
        return v;
      }

    $case Output::kind == CONSTDEF:
      value = (Output) deserialize{Output::inner}(deserializer)!;
      return value;

    $case $defined(value.deserialize) &&& $defined(value.deserialize(deserializer)):
      value.deserialize(deserializer)!;
      return value;

    $case ($defined(value.get) &&& $defined(value.get()) &&& 
           ($defined(value.get()!) ||| $defined(value == maybe::value{$Typeof(value.value)}(value.value)))):
      if (deserializer.next_null()!) {
        return (Maybe{$Typeof(value.value)}) {};
      } else {
        return maybe::value{$Typeof(value.value)}(deserialize{$Typeof(value.value)}(deserializer)!);
      }

    $case $defined(value.len) &&& $defined(value[0]):
      List{Output::inner} elements;
      deserializer.slice_start()!;
      while(deserializer.has_next_slice_item()!) {
        elements.push(deserialize{Output::inner}(deserializer)!);
      }
      deserializer.slice_end()!;
      return elements.to_array(tmem);

    $default:
      $error "The value cannot be deserialize: " +++ $Typeof(value)::name;

  $endswitch
}

macro void? impl_deserialize(value, Deserializer deserializer) {
  $if $Typeof(value)::kind != POINTER:
    $error "The first parameter must be a &self pointer.";
  $endif

  $switch:
    $case $Typeof(value)::inner.kind == ENUM:
      var $type = $Typeof(value)::inner;
      var $config = $type.has_tag("dessert:des:enum") ??? $type.get_tag("dessert:des:enum") : (DEnumConfig) {};

      $switch $config.as:
        $case DESCRIPTION:
          String name = deserializer.next_string()!;
          int found = -1;
          foreach(i, v : $type.names) {
            if (v == name) {
              found = (int) i;
              break;
            }
          }

          if (found == -1) return INVALID_ENUM_VALUE~;
          *value = $type.values[found];

        $case ORDINAL:
          var ordinal = deserialize{$type.inner}(deserializer)!;
          *value = $type.from_ordinal(ordinal);

        $case FIELD:
          var $field_name = $config.field;
          $if $field_name.len == 0:
            $error "When the 'enum_as' attribute is set to 'FIELD', 'enum_field' must be provided with the name of an associated field of the enum.";
          $endif
          $foreach $member : $type.members:
            $if $member.name == $field_name:
              var field_value = deserialize{$member.type}(deserializer)!;
              *value = $type.lookup_field($field_name, field_value)!;
            $endif
          $endforeach
      $endswitch

    $case $Typeof(value)::inner.kind == UNION:
    $case $Typeof(value)::inner.kind == STRUCT:
      var $type = $Typeof(value)::inner;
      var $config = $type.has_tag("dessert:des:struct") ??? $type.get_tag("dessert:des:struct") : (DStructConfig) {};
      List{String} names;
      names.tinit();
      defer names.free();

      deserializer.struct_start($type.name)!;
      while(deserializer.has_next_field()!) {
        String? next_key = deserializer.next_field_name();
        if (catch next_key) {
          io::eprintfn("Error deserializing after deserializing: %s", names);
          next_key!;
          return;
        }
        if (names.contains(next_key)) {
          return DUPLICATED_KEY~;
        }

        $foreach $member : $Typeof(value)::inner.members:
          if (@des_field(deserializer, value, $member, next_key, names)!) {
            names.push($member.name);
            continue;
          }
        $endforeach

        $if $config.deny_unknown_fields:
          io::eprintfn("While deserializing '" +++ $Typeof(value)::inner.name +++ "' (which denies unknown fields), encountered unknown field '%s'.", next_key);
          return UNKNOWN_FIELD~;
        $else
          // Skip the value if not found
          (void) deserialize{Object*}(deserializer)!;
        $endif
      }
      deserializer.struct_end($type.name)!;
  $endswitch
}


macro bool? @des_field(deserializer, value, $member, next_key, List{String} names) @local {
  DFieldConfig $config = $member.has_tag("dessert:des") ??? $member.get_tag("dessert:des") : (DFieldConfig) {};
  var $name = $config.rename.len > 0 ??? $config.rename : $member.name;
  $if $member.type.name == @sprintf("%s.$anon", $Typeof(value)::inner.name):
    $foreach $m : $member.type.members:
      if (@des_field(deserializer, &$member.get(*value), $m, next_key, {})!) return true;
    $endforeach
  $endif

  if ($name == next_key) {
    $if !$config.skip:
      $switch:
        $case $member.type.name == @sprintf("%s.%s", $Typeof(value)::inner.name, $member.name):
        $case $member.type.name == @sprintf("%s.$anon", $Typeof(value)::inner.name):
          impl_deserialize(&$member.get(*value), deserializer)!;

        $case $member.type.kind == UNION &&& !@is_inlined_union($member.type):
          impl_deserialize(&$member.get(*value), deserializer)!;

        $case $member.type.kind == UNION &&& @is_inlined_union($member.type):
          $if $config.tagged_by.len == 0:
            $error @sprintf("Inlined unions MUST have a 'tagged_by' value for deserialization (%s)", $member.name);
          $endif
          
          if (!names.contains($config.tagged_by)) {
            io::eprintfn("While deserializing '" +++ $Typeof(value)::inner.name +++ "', encountered inlined union field '%s' before tag key '%s'.", next_key, $config.tagged_by);
            return INLINED_UNION_BEFORE_TAG~;
          }

          var tag_value = value.$eval($config.tagged_by);
          var next_value = $member.get(*value);

          var $the_switch = "switch ((sz) tag_value) {";
          var $UType = $member.type;
          $foreach $i, $m : $UType::members:
            $the_switch +++= @sprintf("case %s:\n", $i);
            $the_switch +++= @sprintf("@des_field(deserializer, &next_value, $UType::members[%s], $UType::members[%s].name, {})!;\n", $i, $i);
          $endforeach

          $the_switch +++= "}";
          $expand($the_switch);

          $member.set(*value, next_value);

        $default:
          $Typefrom($member.type)? next_value = deserialize{$member.type}(deserializer);
          if (catch next_value) {
            io::eprintfn("Error deserializing key: %s", next_key);
            next_value!;
            return false;
          }

          $member.set(*value, next_value);

      $endswitch
    $endif
    return true;
  }

  return false;
}

macro bool @is_inlined_union($UType) => @get_tag($UType, "dessert:des:union", (DUnionConfig) {}).inlined;
