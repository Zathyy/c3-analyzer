module dessert::utils;

macro @is_maybe($value) {
  return ($defined($value.get) &&& $defined($value.get()) &&& 
          ($defined($value.get()!) ||| $defined($value == maybe::value{$typeof($value.value)}($value.value))));
}

macro @is_maybe_expr(#value) {
  return ($defined(#value.get) &&& $defined(#value.get()) &&& 
          ($defined(#value.get()!) ||| $defined(#value == maybe::value{$typeof(#value.value)}(#value.value))));
}

macro @is_maybe_type($Type) {
  $Type $value;
  return ($defined($value.get) &&& $defined($value.get()) &&& 
          ($defined($value.get()!) ||| $defined($value == maybe::value{$typeof($value.value)}($value.value))));
}

macro @get_maybe_inner_type($Type) {
  $if @is_maybe_type($Type):
    $Type $t;
    return @get_maybe_inner_type($typeof($t.value));
  $endif
  return $Type;
}

