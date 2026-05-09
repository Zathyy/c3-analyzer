module seali::cmd;
import std::collections::list;

struct Command {
  String name;
  String version;
  String about;
  String long_about;
  List{Arg} args;
}

struct Arg {
  char short_name;
  String long_name;

  String help;
  String long_help;
  String default_value;
  String env;
}



