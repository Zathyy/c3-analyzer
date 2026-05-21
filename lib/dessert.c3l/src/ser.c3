module dessert::ser;
import dessert::utils;

import std::io;
import std::core::types;
import std::collections::maybe;

const char[256] TO_UPPER @private = { ['a'..'z'] = 'a' - 'A' };
macro char @to_upper(char $c) => $c - TO_UPPER[$c];

interface Serializer {
  fn void? struct_start(String name);
  fn void? serialize_field_start(String name, FieldAttrs fmt);
  fn void? serialize_field_end(String name, FieldAttrs fmt);
  fn void? struct_end(String name);

  fn void? serialize_slice_start(long len);
  fn void? serialize_slice_item_start(usz idx) @optional;
  fn void? serialize_slice_item_end(usz idx) @optional;
  fn void? serialize_slice_end(long len);

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
  serialize_value(serializer, value, (DFieldConfig) {})!;
  return serializer.result();
}

<* @require $defined(s.serialize(serializer)) *>
macro impl_serialize(s, Serializer serializer) {
  $if $Typeof(s)::kind != POINTER:
    $error "The first parameter must be a &self pointer.";
  $endif

  $switch:
    $case $Typeof(s)::inner.kind == ENUM:
      impl_serialize_enum(s, serializer)!;

    $case $Typeof(s)::inner.kind == CONSTDEF:
      return serialize_value(serializer, ($Typefrom($Typeof(s)::inner.inner)) s, (DFieldConfig) {});

    $case $Typeof(s)::inner.kind == STRUCT:
      var $type = $Typeof(s)::inner;
      DStructConfig $struct_config = $type.has_tag("dessert:ser:struct") ??? $type.get_tag("dessert:ser:struct") : {};
      $foreach $member : $type.members:
        DFieldConfig $config = $member.has_tag("dessert:ser") ??? $member.get_tag("dessert:ser") : {};
        $if !$config.skip:
          $if $config.validator.len > 0: 
            if (!s.$eval($config.validator)($member.get(*s))) {
              return VALIDATOR_ERROR~;
            }
          $endif

          $switch:
            $case $config.skip_if_empty:
              if (!@is_empty($member.get(*s))) {
                @serialize_field(serializer, $config, s, $member, $struct_config)!;
              }

            $case $defined(s.$eval("skip_serializing_" +++ $member.name)()) 
              &&& $Typeof(s.$eval("skip_serializing_" +++ $member.name))::returns == bool:

              if (!s.$eval("skip_serializing_" +++ $member.name)()) {
                @serialize_field(serializer, $config, s, $member, $struct_config)!;
              }

            $default:
              @serialize_field(serializer, $config, s, $member, $struct_config)!;
          $endswitch
        $endif
      $endforeach

    $default:
      $error @sprintf("Unsupported type for serialization %s (%s)", $Typeof(s)::inner, $Typeof(s)::inner.kind);
  $endswitch
}


macro @rename(DFieldConfig $config, String $name, DStructConfig $struct_config) @local @const {
  $if $config.rename.len > 0:
    return $config.rename;
  $else
    $switch $struct_config.rename_all:
      $case VERBATIM:
        return $name;

      $case CAMEL_CASE:
        String $new_name = "";
        $for int $i = 0; $i < $name.len; $i++:
          $if $name[$i] == '_':
            $new_name +++= @to_upper($name[$i+1]);
            $i++;
          $else
            $new_name +++= $name[$i];
          $endif
        $endfor
        return $new_name;

      $default:
        $error @sprintf("CaseConvention %s not supported for now.");
    $endswitch
  $endif
}

macro @serialize_field(serializer, DFieldConfig $config, s, $member, DStructConfig $struct_config) @local {
  bool $is_flatten = $config.flatten ||| $member.name.len == 0;

  $if !$is_flatten:
    serializer.serialize_field_start(
      @rename($config, $member.name, $struct_config),
      $config.fmt,
    )!;
  $endif

  $if $member.type.kind == UNION:
    @impl_serialize_union($member.type, s, serializer, $member, $config, $struct_config)!;

  $else
    $switch:
      $case $member.type.name == @sprintf("%s.%s", $Typeof(s)::inner.name, $member.name):
      $case $member.type.name == @sprintf("%s.$anon", $Typeof(s)::inner.name):
        $if !$is_flatten:
          serializer.struct_start($member.type.name)!;
        $endif

        @impl_serialize_struct($member.type, &$member.get(*s), serializer, $struct_config)!;

        $if !$is_flatten:
          serializer.struct_end($member.type.name)!;
        $endif

      $default:
        serialize_value(serializer, $member.get(*s), $config)!;
    $endswitch
  $endif

  $if !$is_flatten:
    serializer.serialize_field_end(
      @rename($config, $member.name, $struct_config),
      $config.fmt,
    )!;
  $endif
}

macro @impl_serialize_struct($Type, s, Serializer serializer, DStructConfig $struct_config_parent) @local {
  DStructConfig $struct_config = $Type::has_tag("dessert:ser:struct") ??? $Type::get_tag("dessert:ser:struct") : $struct_config_parent;
  $foreach $member : $Type::members:
    DFieldConfig $config = $member.has_tag("dessert:ser") ??? $member.get_tag("dessert:ser") : (DFieldConfig) {};
    $if !$config.skip:
      $if $config.validator.len > 0: 
        if (!s.$eval($config.validator)($member.get(s))) {
          return VALIDATOR_ERROR~;
        }
      $endif

      $switch:
        $case $config.skip_if_empty:
          if (!@is_empty($member.get(*s))) {
            @serialize_field(serializer, $config, s, $member, $struct_config)!;
          }

        $case $defined(s.$eval("skip_serializing_" +++ $member.name)()) 
          &&& $Typeof(s.$eval("skip_serializing_" +++ $member.name))::returns == bool:

          if (!s.$eval("skip_serializing_" +++ $member.name)()) {
            @serialize_field(serializer, $config, s, $member, $struct_config)!;
          }

        $default:
          @serialize_field(serializer, $config, s, $member, $struct_config)!;
      $endswitch
    $endif
  $endforeach
}

macro @impl_serialize_union($UType, s, Serializer serializer, $member, DFieldConfig $config, DStructConfig $struct_config) @local {
  DUnionConfig $union_config = @get_tag($UType, "dessert:ser:union", (DUnionConfig) {});
  $if $config.tagged_by.len == 0:
    $error @sprintf("Unions must be tagged by another field's value (member %s with type %s)", $member.name, $UType::name);
  $endif

  DFieldConfig $field_config = {...$config, .flatten = $union_config.inlined};

  var tag_value = s.$eval($config.tagged_by);
  var $the_switch = "switch ((sz) tag_value) {";

  $foreach $i, $m : $UType::members:
    $the_switch +++= @sprintf("case %s:\n", $i);
    $the_switch +++= @sprintf("@serialize_field(serializer, $field_config, &$member.get(*s), $UType::members[%s], $struct_config)!;\n", $i);

  $endforeach

  $the_switch +++= "}";

  bool $is_flatten = $union_config.inlined ||| $member.name.len == 0;
  $if !$is_flatten:
    serializer.struct_start($member.type.name)!;
  $endif

  $expand($the_switch);

  $if !$is_flatten:
    serializer.struct_end($member.type.name)!;
  $endif
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
    $case $Typeof(#value)::kind == POINTER:
      return #value == null;
  $endswitch
}

macro serialize_value(serializer, value, $config) {
  $switch:
    $case $defined(value.serialize) &&& $defined(value.serialize(serializer)):
      var $type = $reflect(value).type;
      $if $type.kind == POINTER:
        $type = $Typeof(value)::inner;
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
        $if $Typeof(inner)::kind == STRUCT &&& !$config.flatten:
          serializer.struct_start($Typeof(inner)::name)!;
        $endif
        inner.serialize(serializer)!;
        $if $Typeof(inner)::kind == STRUCT &&& !$config.flatten:
          serializer.struct_end($Typeof(inner)::name)!;
        $endif
      }

    $case $defined(value.len) &&& $defined(value[0]) &&& $defined(value.len()):
      serializer.serialize_slice_start(value.len())!;
      $Typefrom($Typeof(Serializer.serialize_slice_item_start)) cb_start;
      if (&((Serializer) serializer).serialize_slice_item_start) {
        cb_start = &((Serializer) serializer).serialize_slice_item_start;
      }
      $Typefrom($Typeof(Serializer.serialize_slice_item_end)) cb_end;
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
      $Typefrom($Typeof(Serializer.serialize_slice_item_start)) cb_start;
      if (&((Serializer) serializer).serialize_slice_item_start) {
        cb_start = &((Serializer) serializer).serialize_slice_item_start;
      }
      $Typefrom($Typeof(Serializer.serialize_slice_item_end)) cb_end;
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
      $error @sprintf("Value not serializable: '%s (%s)'", $Typeof(value)::name, $Typeof(value)::kind);
  $endswitch
}

<*
  @require $Typeof(s)::inner.kind == ENUM
*>
macro impl_serialize_enum(s, serializer) @local {
  var $type = $Typeof(s)::inner;
  var $config = $type.has_tag("dessert:ser:enum") ??? $type.get_tag("dessert:ser:enum") : (DEnumConfig) {};

  $switch $config.as:
    $case DESCRIPTION:
      return serialize_value(serializer, s.description, (DFieldConfig) {});

    $case ORDINAL:
      return serialize_value(serializer, s.ordinal, (DFieldConfig) {});

    $case FIELD:
      var $field_name = $config.field;
      $if $field_name.len == 0:
        $error "While serializing an enum: When the 'as' attribute is set to 'FIELD', 'field' must be provided with the name of an associated field of the enum.";
      $endif
      return serialize_value(serializer, s.$eval($field_name), (DFieldConfig) {});
  $endswitch
}

macro @is_serializable(#value) {
  return $defined(#value.serialize) ||| ($defined(#value.len) &&& $defined(#value[0])) ||| 
    utils::@is_maybe_expr(#value);
}

