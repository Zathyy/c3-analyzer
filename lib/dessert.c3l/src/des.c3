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

  fn String? next_string();
  fn int? next_int();

  // fn int? next_short() @optional;
  // fn long? next_long() @optional;
  // fn ulong? next_ulong();

  fn double? next_double();
  fn bool? next_bool();
  fn bool? next_null();
}

faultdef VALIDATOR_ERROR;
faultdef DUPLICATED_KEY, INVALID_ENUM_VALUE;

// Should be treated as a protocol, don't derive it directly
interface Deserializable {
  fn void? deserialize(Deserializer deserializer);
}

fn void? String.deserialize(&self, Deserializer ser) @dynamic {
  *self = ser.next_string()!;
}
fn void? int.deserialize(&self, Deserializer ser) @dynamic {
  *self = ser.next_int()!;
}
fn void? ulong.deserialize(&self, Deserializer ser) @dynamic {
  *self = (ulong) ser.next_int()!;
}
fn void? bool.deserialize(&self, Deserializer ser) @dynamic {
  *self = ser.next_bool()!;
}

macro @is_deserializable($Output) {
  $Output $value;
  return $defined($value.deserialize) ||| ($defined($value.len) &&& $defined($value[0])) ||| 
    ($defined($value.get) &&& $defined($value.get()) &&& 
     ($defined($value.get()!) ||| $defined($value == maybe::value{$typeof($value.value)}($value.value))));
}

macro deserialize(deserializer) <Output> {
  Output value;
  $switch:
    $case Output.kindof == POINTER:
      return &&deserialize{Output.inner}(deserializer);

    $case $defined(value.deserialize) &&& $defined(value.deserialize(deserializer)):
      value.deserialize(deserializer)!;
      return value;

    $case ($defined(value.get) &&& $defined(value.get()) &&& 
           ($defined(value.get()!) ||| $defined(value == maybe::value{$typeof(value.value)}(value.value)))):
      if (deserializer.next_null()!) {
        return (Maybe{$typeof(value.value)}){};
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

macro impl_deserialize(value, deserializer) {
  $if $typeof(deserializer) != Deserializer:
    $error "The deserializer must be of type Deserializer.";
  $endif

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
