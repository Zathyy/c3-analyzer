import seali;

import std::io;
import std::collections::maybe;

struct Cli @Command("myapp") 
  @About("My awesome CLI application")
{
  String input_file @Seali(@arg(long, help = "Input file path", default_value = "a"));
  bool verbose @Seali(@arg(short = 'V', long, default_value = false, help = "Enable verbose output"));
  String output @Seali(@arg(short, long = "out", help = "Output file", default_value = "b"));
  uint threads @Seali(@arg(short, default_value = 4, help = "Number of threads"));

  Maybe{Install} install @Seali(@arg(subcommand));
  Maybe{Fetch} fetch @Seali(@arg(subcommand));
}

struct Install @Command("install") 
  @About("Install libraries")
{
  String name @Seali(@arg(help = "The lib to install"));
}

struct Fetch @Command("fetch") 
  @About("Fetch a tar file")
{
  String url @Seali(@arg(help = "The url to fetch"));
}

fn int main(String[] args) {
  Cli cli = seali::parse(Cli, args)!!;

  io::printfn("%s\n", string::from_struct(mem, cli));
  if (try cli.install.get()) {
    io::printfn("%s\n", string::from_struct(mem, cli.install.value));
  }
  if (try cli.fetch.get()) {
    io::printfn("%s\n", string::from_struct(mem, cli.fetch.value));
  }

	return 0;
}
