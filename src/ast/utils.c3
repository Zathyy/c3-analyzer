module parser::ast::utils;

const char[256] TO_UPPER @private = { ['a'..'z'] = 'a' - 'A' };
macro char @to_upper(char $c) => $c - TO_UPPER[$c];

const char[256] TO_LOWER @private = { ['A'..'Z'] = 'a' - 'A' };
macro char @to_lower(char $c) => $c + TO_LOWER[$c];

macro String @str_to_upper(String $s) @const {
  var $final_s = "";
  $foreach $c : $s:
    $final_s +++= @to_upper($c);
  $endforeach

  return $final_s;
}

macro String @str_to_lower(String $s) @const {
  var $final_s = "";
  $foreach $c : $s:
    $final_s +++= @to_lower($c);
  $endforeach

  return $final_s;
}

