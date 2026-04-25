module dessert::des;
import std::collections::list;
import std::collections::maybe;
import std::collections::object;
import std::io;


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
faultdef DUPLICATED_KEY, INVALID_ENUM_VALUE, UNKNOWN_FIELD;

// Should be treated as a protocol, don't derive it directly
interface Deserializable {
  fn void? deserialize(Deserializer deserializer);
}

macro @is_deserializable($Output) {
  $Output $value;
  return $defined($value.deserialize) ||| ($defined($value.len) &&& $defined($value[0])) ||| 
    ($defined($value.get) &&& $defined($value.get()) &&& 
     ($defined($value.get()!) ||| $defined($value == maybe::value{$typeof($value.value)}($value.value))));
}

macro deserialize(Deserializer deserializer) <Output> {
  Output value;
  $switch:
    $case Output::kind == POINTER:
      if (deserializer.next_null()!) {
        return null;
      } else {
        Output v = mem::new(Output::inner);
        *v = deserialize{Output::inner}(deserializer)!;
        return v;
      }

    $case $defined(value.deserialize) &&& $defined(value.deserialize(deserializer)):
      value.deserialize(deserializer)!;
      return value;

    $case ($defined(value.get) &&& $defined(value.get()) &&& 
           ($defined(value.get()!) ||| $defined(value == maybe::value{$typeof(value.value)}(value.value)))):
      if (deserializer.next_null()!) {
        return (Maybe{$typeof(value.value)}) {};
      } else {
        return maybe::value{$typeof(value.value)}(deserialize{$typeof(value.value)}(deserializer)!);
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
      $error "The value cannot be deserialize: " +++ $typeof(value)::name;

  $endswitch
}

macro impl_deserialize(value, Deserializer deserializer) {
  $if $typeof(value)::kind != POINTER:
    $error "The first parameter must be a &self pointer.";
  $endif

  $switch:
    $case $typeof(value)::inner.kind == ENUM:
      var $type = $typeof(value)::inner;
      var $config = $type.has_tag("dessert:des:enum") ??? $type.get_tag("dessert:des:enum") : (DessertEnumConfig) {};

      $switch $config.as:
        $case NAME:
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
              *value = $type.lookup_field($eval($field_name), field_value)!;
            $endif
          $endforeach
      $endswitch

    $case $typeof(value)::inner.kind == STRUCT:
      var $type = $typeof(value)::inner;
      var $config = $type.has_tag("dessert:des:struct") ??? $type.get_tag("dessert:des:struct") : (DessertStructConfig) {};
      List{String} names;
      names.tinit();

      deserializer.struct_start($type.name)!;
      while(deserializer.has_next_field()!) {
        String? next_key = deserializer.next_field_name();
        if (catch next_key) {
          io::eprintfn("Error deserializing after deserializing: %s", names);
          next_key!;
          return;
        }
        $foreach $member : $typeof(value)::inner.members:
          DessertFieldConfig $dessert = $member.has_tag("dessert:des") ??? $member.get_tag("dessert:des") : (DessertFieldConfig) {};
          var $name = $dessert.rename.len > 0 ??? $dessert.rename : $member.name;
          if ($name == next_key) {
            if (names.contains(next_key)) {
              return DUPLICATED_KEY~;
            }
            $typefrom($member.type)? next_value = deserialize{$member.type}(deserializer);
            if (catch next_value) {
              io::eprintfn("Error deserializing key: %s", next_key);
              next_value!;
              return;
            }
            $if !$dessert.skip:
              value.$eval($member.name) = next_value;
            $endif

            names.push($member.name);
            continue;
          }
        $endforeach
        $if $config.deny_unknown_fields:
          io::eprintfn("While deserializing '" +++ $typeof(value)::inner.name +++ "' (which denies unknown fields), encountered unknown field '%s'.", next_key);
          return UNKNOWN_FIELD~;
        $else
          // Skip the value if not found
          (void) deserialize{Object*}(deserializer)!;
        $endif
      }
      deserializer.struct_end($type.name)!;
  $endswitch
}
