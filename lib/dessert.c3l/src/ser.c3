module dessert::ser;
import dessert::utils;

import std::io;
import std::core::types;
import std::collections::maybe;

interface Serializer {
  fn void? struct_start(String name);
  fn void? serialize_field_start(String name, FieldAttrs fmt);
  fn void? serialize_field_end(String name, FieldAttrs fmt);
  fn void? struct_end(String name);

  fn void? serialize_slice_start(ulong len);
  fn void? serialize_slice_item_start(usz idx) @optional;
  fn void? serialize_slice_item_end(usz idx) @optional;
  fn void? serialize_slice_end(ulong len);

  fn void? serialize_null();
  fn void? serialize_bool(bool b);
  fn void? serialize_long(long l);
  fn void? serialize_string(String s);
  fn void? serialize_double(double d);

  fn void? serialize_char(char c) @optional;
  fn void? serialize_ichar(ichar c) @optional;

  fn void? serialize_short(short s) @optional;
  fn void? serialize_int(int i) @optional;
  fn void? serialize_int128(int128 i) @optional;

  fn void? serialize_uint(uint i) @optional;
  fn void? serialize_ushort(ushort s) @optional;
  fn void? serialize_ulong(ulong l) @optional;
  fn void? serialize_uint128(uint128 i) @optional;

  fn void? serialize_zstring(ZString s) @optional;

  fn void? serialize_float(float f) @optional;
  // fn void? serialize_float16(float16 f) @optional @if($defined(float16));
  // fn void? serialize_float128(float128 f) @optional @if($defined(float128));
}

faultdef VALIDATOR_ERROR;

// Should be treated as a protocol, don't derive it directly
interface Serializable {
  fn void? serialize(Serializer serializer);
}

<* @require $defined(Serializer s = serializer) *>
macro serialize(serializer, value) {
  serialize_value(serializer, value, (DessertFieldConfig) {})!;
  return serializer.result();
}

<* @require $defined(s.serialize(serializer)) *>
macro impl_serialize(s, Serializer serializer) {
  $if $typeof(s)::kind != POINTER:
    $error "The first parameter must be a &self pointer.";
  $endif

  $switch:
    $case $typeof(s)::inner.kind == ENUM:
      impl_serialize_enum(s, serializer)!;

    $case $typeof(s)::inner.kind == STRUCT:
      var $type = $typeof(s)::inner;
      $foreach $member : $type.members:
        DessertFieldConfig $config = $member.has_tag("dessert:ser") ??? $member.get_tag("dessert:ser") : (DessertFieldConfig) {};
        $if !$config.skip:
          $if $config.validator.len > 0: 
            if (!s.$eval($config.validator)(s.$eval($member.name))) {
              return VALIDATOR_ERROR~;
            }
          $endif

          $switch:
            $case $config.skip_if_empty:
              if (!@is_empty(s.$eval($member.name))) {
                $if !$config.flatten:
                  serializer.serialize_field_start(
                    $config.rename.len > 0 ??? $config.rename : $member.name,
                    $config.fmt,
                  )!;
                $endif
                serialize_value(serializer, s.$eval($member.name), $config)!;
                $if !$config.flatten:
                  serializer.serialize_field_end(
                    $config.rename.len > 0 ??? $config.rename : $member.name,
                    $config.fmt,
                  )!;
                $endif
              }

            $case $defined(s.$eval("skip_serializing_" +++ $member.name)()) 
              &&& $typeof(s.$eval("skip_serializing_" +++ $member.name))::returns == bool:

              if (!s.$eval("skip_serializing_" +++ $member.name)()) {
                $if !$config.flatten:
                  serializer.serialize_field_start(
                    $config.rename.len > 0 ??? $config.rename : $member.name,
                    $config.fmt,
                  )!;
                $endif
                serialize_value(serializer, s.$eval($member.name), $config)!;
                $if !$config.flatten:
                  serializer.serialize_field_end(
                    $config.rename.len > 0 ??? $config.rename : $member.name,
                    $config.fmt,
                  )!;
                $endif
              }

            $default:
              $if !$config.flatten:
                serializer.serialize_field_start(
                  $config.rename.len > 0 ??? $config.rename : $member.name,
                  $config.fmt,
                )!;
              $endif
              serialize_value(serializer, s.$eval($member.name), $config)!;
              $if !$config.flatten:
                serializer.serialize_field_end(
                  $config.rename.len > 0 ??? $config.rename : $member.name,
                  $config.fmt,
                )!;
              $endif
          $endswitch
        $endif
      $endforeach
  $endswitch
}

macro @is_empty(#value) {
  $switch:
    $case $defined(#value.len) &&& $defined(#value[0]):
      return #value.len == 0;
    $case utils::@is_maybe_expr(#value):
      var inner = #value.get();
      if (catch inner) {
        return true;
      } else {
        return false;
      }
    $case $typeof(#value)::kind == POINTER:
      return #value == null;
  $endswitch
}

macro serialize_value(serializer, value, $config) {
  $switch:
    $case $defined(value.serialize) &&& $defined(value.serialize(serializer)):
      var $type = $reflect(value).type;
      $if $type.kind == POINTER:
        $type = $typeof(value)::inner;
        if (value == null) {
          serializer.serialize_null()!;
          return;
        }
      $endif
      $if $type.kind == STRUCT &&& !$config.flatten:
        serializer.struct_start($type.name)!;
      $endif
      value.serialize(serializer)!;
      $if $type.kind == STRUCT &&& !$config.flatten:
        serializer.struct_end($type.name)!;
      $endif

    $case utils::@is_maybe_expr(value):
      var inner = value.get();
      if (catch inner) {
        serializer.serialize_null()!;
      } else {
        $if $typeof(inner)::kind == STRUCT &&& !$config.flatten:
          serializer.struct_start($typeof(inner)::name)!;
        $endif
        inner.serialize(serializer)!;
        $if $typeof(inner)::kind == STRUCT &&& !$config.flatten:
          serializer.struct_end($typeof(inner)::name)!;
        $endif
      }

    $case $defined(value.len) &&& $defined(value[0]) &&& $defined(value.len()):
      serializer.serialize_slice_start(value.len())!;
      $typefrom($typeof(Serializer.serialize_slice_item_start)) cb_start;
      if (&((Serializer) serializer).serialize_slice_item_start) {
        cb_start = &((Serializer) serializer).serialize_slice_item_start;
      }
      $typefrom($typeof(Serializer.serialize_slice_item_end)) cb_end;
      if (&((Serializer) serializer).serialize_slice_item_end) {
        cb_end = &((Serializer) serializer).serialize_slice_item_end;
      }
      foreach (i, el: value) {
        if (cb_start) cb_start(serializer, (usz) i)!;
        serialize_value(serializer, el, $config)!;
        if (cb_end) cb_end(serializer, (usz) i)!;
      }
      serializer.serialize_slice_end(value.len())!;

    $case $defined(value.len) &&& $defined(value[0]):
      serializer.serialize_slice_start(value.len)!;
      $typefrom($typeof(Serializer.serialize_slice_item_start)) cb_start;
      if (&((Serializer) serializer).serialize_slice_item_start) {
        cb_start = &((Serializer) serializer).serialize_slice_item_start;
      }
      $typefrom($typeof(Serializer.serialize_slice_item_end)) cb_end;
      if (&((Serializer) serializer).serialize_slice_item_end) {
        cb_end = &((Serializer) serializer).serialize_slice_item_end;
      }
      foreach (i, el: value) {
        if (cb_start) cb_start(serializer, (usz) i)!;
        serialize_value(serializer, el, $config)!;
        if (cb_end) cb_end(serializer, (usz) i)!;
      }
      serializer.serialize_slice_end(value.len)!;

    $default:
      $error @sprintf("Value not serializable: '%s (%s)'", $typeof(value)::name, $typeof(value)::kind);
  $endswitch
}

<*
  @require $typeof(s)::inner.kind == ENUM
*>
macro impl_serialize_enum(s, serializer) @local {
  var $type = $typeof(s)::inner;
  var $config = $type.has_tag("dessert:ser:enum") ??? $type.get_tag("dessert:ser:enum") : (DessertEnumConfig) {};

  $switch $config.as:
    $case NAME:
      return serialize_value(serializer, s.description, (DessertFieldConfig) {});

    $case ORDINAL:
      return serialize_value(serializer, s.ordinal, (DessertFieldConfig) {});

    $case FIELD:
      var $field_name = $config.field;
      $if $field_name.len == 0:
        $error "While serializing an enum: When the 'as' attribute is set to 'FIELD', 'field' must be provided with the name of an associated field of the enum.";
      $endif
      return serialize_value(serializer, s.$eval($field_name), (DessertFieldConfig) {});
  $endswitch
}

macro @is_serializable(#value) {
  return $defined(#value.serialize) ||| ($defined(#value.len) &&& $defined(#value[0])) ||| 
    utils::@is_maybe_expr(#value);
}

