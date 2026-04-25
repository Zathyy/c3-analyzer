module dessert::ser;

faultdef UNSUPPORTED_DATA_TYPE;

fn void? String.serialize(&self, Serializer ser) @dynamic {
  return ser.serialize_string(*self);
}
fn void? ZString.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_zstring) {
    return ser.serialize_zstring(*self);
  }
  return ser.serialize_string(self.str_view());
}

fn void? bool.serialize(&self, Serializer ser) @dynamic {
  return ser.serialize_bool(*self);
}

fn void? char.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_char) {
    return ser.serialize_char(*self);
  }
  return ser.serialize_string({*self});
}

/// Signed numbers

fn void? ichar.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_ichar) {
    return ser.serialize_ichar(*self);
  }
  return ser.serialize_long((long) *self);
}

fn void? short.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_short) {
    return ser.serialize_short(*self);
  }
  return ser.serialize_long((long) *self);
}

fn void? int.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_int) {
    return ser.serialize_int(*self);
  }
  return ser.serialize_long((long) *self);
}

fn void? long.serialize(&self, Serializer ser) @dynamic {
  return ser.serialize_long(*self);
}

fn void? int128.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_int128) {
    return ser.serialize_int128(*self);
  }
  return UNSUPPORTED_DATA_TYPE~;
}

/// Unsigned numbers

fn void? ushort.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_ushort) {
    return ser.serialize_ushort(*self);
  } else if (&ser.serialize_ulong) {
    return ser.serialize_ulong((ulong) *self);
  } else {
    return ser.serialize_long((long) *self);
  }
}

fn void? uint.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_uint) {
    return ser.serialize_uint(*self);
  } else if (&ser.serialize_ulong) {
    return ser.serialize_ulong((ulong) *self);
  } else {
    return ser.serialize_long((long) *self);
  }
}

fn void? ulong.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_ulong) {
    return ser.serialize_ulong(*self);
  }
  return ser.serialize_long((long) *self);
}

fn void? uint128.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_uint128) {
    return ser.serialize_uint128(*self);
  }
  return UNSUPPORTED_DATA_TYPE~;
}

/// Floating numbers

// fn void? float16.serialize(&self, Serializer ser) @dynamic @if($defined(float16)) {
//   if (&ser.serialize_float16) {
//     return ser.serialize_float16(*self);
//   }
//   return ser.serialize_double((double) *self);
// }

fn void? float.serialize(&self, Serializer ser) @dynamic {
  if (&ser.serialize_float) {
    return ser.serialize_float(*self);
  }
  return ser.serialize_double((double) *self);
}

fn void? double.serialize(&self, Serializer ser) @dynamic {
  return ser.serialize_double(*self);
}

// fn void? float128.serialize(&self, Serializer ser) @dynamic @if($defined(float128)) {
//   if (&ser.serialize_float128) {
//     return ser.serialize_float128(*self);
//   }
//   return UNSUPPORTED_DATA_TYPE~;
// }
