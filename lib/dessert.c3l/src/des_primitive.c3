module dessert::des;

faultdef UNSUPPORTED_DATA_TYPE;

fn void? String.deserialize(&self, Deserializer des) @dynamic {
  *self = des.next_string()!;
}

fn void? char.deserialize(&self, Deserializer des) @dynamic {
  *self = des.next_char()!;
}

fn void? bool.deserialize(&self, Deserializer des) @dynamic {
  *self = des.next_bool()!;
}

/// Signed numbers

fn void? ichar.deserialize(&self, Deserializer des) @dynamic {
  if (&des.next_ichar) {
    *self = des.next_ichar()!;
  } else {
    *self = (ichar) des.next_long()!;
  }
}

fn void? short.deserialize(&self, Deserializer des) @dynamic {
  if (&des.next_short) {
    *self = des.next_short()!;
  } else {
    *self = (short) des.next_long()!;
  }
}

fn void? int.deserialize(&self, Deserializer des) @dynamic {
  if (&des.next_int) {
    *self = des.next_int()!;
  } else {
    *self = (int) des.next_long()!;
  }
}
fn void? long.deserialize(&self, Deserializer des) @dynamic {
  *self = des.next_long()!;
}
fn void? int128.deserialize(&self, Deserializer des) @dynamic {
  if (&des.next_int128) {
   *self = des.next_int128()!;
    return;
  }
  return UNSUPPORTED_DATA_TYPE~;
}

/// Unsigned numbers

fn void? ushort.deserialize(&self, Deserializer des) @dynamic {
  if (&des.next_ushort) {
    *self = des.next_ushort()!;
  } else {
    *self = (ushort) des.next_ulong()!;
  }
}

fn void? uint.deserialize(&self, Deserializer des) @dynamic {
  if (&des.next_uint) {
    *self = des.next_uint()!;
  } else {
    *self = (uint) des.next_ulong()!;
  }
}
fn void? ulong.deserialize(&self, Deserializer des) @dynamic {
  *self = des.next_ulong()!;
}

fn void? uint128.deserialize(&self, Deserializer des) @dynamic {
  if (&des.next_uint128) {
    *self = des.next_uint128()!;
    return;
  }
  return UNSUPPORTED_DATA_TYPE~;
}


/// Floating numbers

fn void? float.deserialize(&self, Deserializer des) @dynamic {
  if (&des.next_float) {
    *self = des.next_float()!;
  } else {
    *self = (float) des.next_double()!;
  }
}

fn void? double.deserialize(&self, Deserializer des) @dynamic {
  *self = des.next_double()!;
}
