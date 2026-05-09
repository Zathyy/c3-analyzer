module seali::curse;
import std::collections::maybe;


attrdef @Seali(ArgConfig config) = @tag("seali:arg", config);


macro @starts_with($s, $needle) {
  $if !$defined($s[$needle.len - 1]):
    return false;
  $endif

  $foreach $i, $c : $needle:
    $if $defined($s[$i]) &&& $s[$i] != $c:
      return false;
    $endif
  $endforeach
  return true;
}

macro @trim_start($s) {
  $foreach $i, $c : $s:
    $if $s[$i] != ' ':
      return $s[$i..];
    $endif
  $endforeach
}
macro @trim_end($s) {
  $if $s == " ":
    return "";
  $endif

  $for var $i = $s.len - 1; $i > 0; $i-- :
    $if $s[$i] != ' ':
      return $s[..$i];
    $endif
  $endfor
}

macro @trim($s) {
  return @trim_end(@trim_start($s));
}

macro @get_val($s) {
  $for var $i = 0; $i < $s.len; $i++ :
    $if $s[$i] == '=':
      return @trim_start($s[$i+1..]);
    $endif
  $endfor
  return true;
}

macro ArgConfig arg(...) @builtin {
  char $shortn;
  bool $autoshort;

  String $longn;
  bool $autolong;

  String $help;

  String $default_value;

  bool $is_subcommand;

  bool $skip;

  $for var $i = 0; $i < $vaarg.len; $i++ :
    var $s = $stringify($vaarg[$i]);
    $switch:
      $case @starts_with($s, "short"):
        var $val = @get_val($s);
        $if $Typeof($val) == bool &&& $val == true:
          $autoshort = true;
        $else
          $if !@starts_with($val, "'"):
            $error "value of `short` must be a character literal";
          $endif
          $shortn = $val[1]; // get the character in the middle of the the `'`s
        $endif

      $case @starts_with($s, "long"):
        var $val = @get_val($s);
        $if $Typeof($val) == bool &&& $val == true:
          $autolong = true;
        $else
          $if !@starts_with($val, "\""):
            $error "value of `long` must be a string literal";
          $endif
          $longn = $val[1..^2];
        $endif

      $case @starts_with($s, "default_value"):
        var $val = @get_val($s);
        $if $Typeof($val) == bool &&& $val == true:
          $error "You need to provide a default_value";
        $else
          $if $val == "\"\"":
            $error "Empty string default values are not allowed. Use Maybe{String} instead.";
          $endif
          $if @starts_with($val, "\""):
            $default_value = $val[1..^2];
          $else
            $default_value = $val;
          $endif
        $endif
        
      $case @starts_with($s, "help"):
        var $val = @get_val($s);
        $if $Typeof($val) == bool &&& $val == true:
          $error "You need to write a help message";
        $else
          $if !@starts_with($val, "\""):
            $error "value of `help` must be a string literal";
          $endif
          $help = $val[1..^2];
        $endif

      $case @starts_with($s, "subcommand"):
        var $val = @get_val($s);
        $if $Typeof($val) == bool &&& $val == true:
          $is_subcommand = true;
        $else
          $error "`subcommand` doesn't take an argument";
        $endif

      $case @starts_with($s, "skip"):
        var $val = @get_val($s);
        $if $Typeof($val) == bool &&& $val == true:
          $skip = true;
        $else
          $error "`skip` doesn't take an argument";
        $endif

      $default:
        $error "Unknown attribute '" +++ $s +++ "'";
    $endswitch
  $endfor

  return {
    .shortn = $shortn,
    .autoshort = $autoshort,

    .longn = $longn,
    .autolong = $autolong,

    .help = $help,
    .default_value = $default_value,

    .is_subcommand = $is_subcommand,

    .skip = $skip,
  };
}
