module dessert::des;
import std::collections::list;
import std::collections::maybe;
import std::io;


interface Deserializer {
  fn void? struct_start();
  fn bool? has_next_field();
  fn String? next_field_name();
  fn void? struct_end();

  fn void? slice_start();
  fn bool? has_next_slice_item();
  fn void? slice_end();

  fn bool? next_bool();
  fn bool? next_null();

  fn char? next_char();
  fn ichar? next_ichar() @optional;

  fn short? next_short() @optional;
  fn int? next_int() @optional;
  fn long? next_long();
  fn int128? next_int128() @optional;

  fn uint? next_uint() @optional;
  fn ushort? next_ushort() @optional;
  fn ulong? next_ulong();
  fn uint128? next_uint128() @optional;

  fn String? next_string();
  fn ZString? next_zstring() @optional;

  fn float? next_float() @optional;
  fn double? next_double();
}

faultdef VALIDATOR_ERROR;
faultdef DUPLICATED_KEY, INVALID_ENUM_VALUE;

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
    $case Output.kindof == POINTER:
      if (deserializer.next_null()!) {
        return null;
      } else {
        Output v = mem::new(Output.inner);
        *v = deserialize{Output.inner}(deserializer)!;
        return v;
      }

    $case $defined(value.deserialize) &&& $defined(value.deserialize(deserializer)):
      value.deserialize(deserializer)!;
      return value;

    $case ($defined(value.get) &&& $defined(value.get()) &&& 
           ($defined(value.get()!) ||| $defined(value == maybe::value{$typeof(value.value)}(value.value)))):
      if (deserializer.next_null()!) {
        return {};
      } else {
        return maybe::value{$typeof(value.value)}(deserialize{$typeof(value.value)}(deserializer)!);
      }

    $case $defined(value.len) &&& $defined(value[0]):
      List{Output.inner} elements;
      deserializer.slice_start()!;
      while(deserializer.has_next_slice_item()!) {
        elements.push(deserialize{Output.inner}(deserializer)!);
      }
      deserializer.slice_end()!;
      return elements.to_array(mem);

    $default:
      $error "The value cannot be deserialize: " +++ $typeof(value).nameof;

  $endswitch
}

macro impl_deserialize(value, Deserializer deserializer) {
  $if $typeof(value).kindof != POINTER:
    $error "The first parameter must be a &self pointer.";
  $endif

  $switch:
    $case $typeof(value).inner.kindof == ENUM:
      var $type = $typeof(value).inner;
      var $config = $type.has_tagof("dessert:des:enum") ??? $type.tagof("dessert:des:enum") : (DessertEnumConfig) {};

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
          $foreach $member : $type.membersof:
            $if $member.nameof == $field_name:
              var field_value = deserialize{$member.type}(deserializer)!;
              *value = $type.lookup_field($eval($field_name), field_value)!;
            $endif
          $endforeach
      $endswitch

    $case $typeof(value).inner.kindof == STRUCT:
      List{String} names;
      names.init(mem);
      defer names.free();

      deserializer.struct_start()!;
      while(deserializer.has_next_field()!) {
        String next_key = deserializer.next_field_name()!;
        $foreach $member : $typeof(value).inner.membersof:
          var $dessert = $member.has_tagof("dessert:des") ??? $member.tagof("dessert:des") : (Dessert) {};
          $if $typeof($dessert) != Dessert:
            $error("Dessert tag value must be of type Dessert");
          $endif
          var $name = $dessert.rename.len > 0 ??? $dessert.rename : $member.nameof;
          if ($name == next_key) {
            if (names.contains(next_key)) {
              return DUPLICATED_KEY~;
            }
            var next_value = deserialize{$member.typeid}(deserializer)!;
            $if !$dessert.skip:
              value.$eval($member.nameof) = next_value;
            $endif

            names.push($member.nameof);
          }
        $endforeach
      }
      deserializer.struct_end()!;
  $endswitch
}


// <* @require $defined(*value) *>
// macro impl_deserialize(value, Deserializer deserializer) {
//   return _impl_deserialize{$typeof(value).inner}(value, deserializer);
// }
//
// fn void? _impl_deserialize(ValueType *value, Deserializer deserializer) <ValueType> {
//   $switch:
//     $case ValueType.kindof == ENUM:
//       var $config = ValueType.has_tagof("dessert:des:enum") ??? ValueType.tagof("dessert:des:enum") : (DessertEnumConfig) {};
//
//       $switch $config.as:
//         $case NAME:
//           String name = deserializer.next_string()!;
//           int found = -1;
//           foreach(i, v : ValueType.names) {
//             if (v == name) {
//               found = (int) i;
//               break;
//             }
//           }
//
//           if (found == -1) return INVALID_ENUM_VALUE~;
//           *value = ValueType.values[found];
//
//         $case ORDINAL:
//           var ordinal = deserialize{ValueType.inner}(deserializer)!;
//           *value = ValueType.from_ordinal(ordinal);
//
//         $case FIELD:
//           var $field_name = $config.field;
//           $if $field_name.len == 0:
//             $error "When the 'enum_as' attribute is set to 'FIELD', 'enum_field' must be provided with the name of an associated field of the enum.";
//           $endif
//           $foreach $member : ValueType.membersof:
//             $if $member.nameof == $field_name:
//               var field_value = deserialize{$member.type}(deserializer)!;
//               *value = ValueType.lookup_field($eval($field_name), field_value)!;
//             $endif
//           $endforeach
//       $endswitch
//
//     $case ValueType.kindof == STRUCT:
//       String[] names = mem::new_array(String, ValueType.membersof.len);
//       defer mem::free(names);
//
//       deserializer.struct_start()!;
//       while(deserializer.has_next_field()!) {
//         String next_key = deserializer.next_field_name()!;
//         $foreach $i, $member : ValueType.membersof:
//           var $dessert = $member.has_tagof("dessert:des") ??? $member.tagof("dessert:des") : (Dessert) {};
//           $if $typeof($dessert) != Dessert:
//             $error("Dessert tag value must be of type Dessert");
//           $endif
//           var $name = $dessert.rename.len > 0 ??? $dessert.rename : $member.nameof;
//           if ($name == next_key) {
//             if (names.contains(next_key)) {
//               return DUPLICATED_KEY~;
//             }
//             $typefrom($member.typeid) next_value = deserialize{$member.typeid}(deserializer)!;
//             $if !$dessert.skip:
//               value.$eval($member.nameof) = next_value;
//             $endif
//
//             names[$i] = $member.nameof;
//           }
//         $endforeach
//       }
//       deserializer.struct_end()!;
//   $endswitch
// }
//
// fn bool String[].contains(&self, String other) {
//   foreach(s : self) {
//     if (s == other) return true;
//   }
//
//   return false;
// }
