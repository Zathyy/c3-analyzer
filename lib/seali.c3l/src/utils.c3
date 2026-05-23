module seali::utils;

const char[256] TO_UPPER @private = { ['a'..'z'] = 'a' - 'A' };

macro String String.@to_upper($self) {
  var $result = "";
  $foreach $c : $self:
    $result +++= $c - TO_UPPER[$c];
  $endforeach
  return $result;
}

macro @expand_val(String $val) @const {
  $expand(@sprintf("return %s;", $val));
}
