module seali::utils;

fn bool String[].contains(&self, String el) {
  foreach (s: self) {
    if (s == el) return true;
  }
  return false;
}

const char[256] TO_UPPER @private = { ['a'..'z'] = 'a' - 'A' };

macro String String.@to_upper($self) {
  var $result = "";
  $foreach $c : $self:
    $result +++= $c - TO_UPPER[$c];
  $endforeach
  return $result;
}
