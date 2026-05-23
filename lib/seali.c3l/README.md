# seali

A lightweight CLI library for C3 that makes writing command-line interfaces simple and declarative using macros and attributes.

## Features

- **Declarative CLI definition** - Define your CLI using structs and attributes
- **Automatic help generation** - Built-in `-h`/`--help` with formatted output
- **Short and long flags** - Support for both `-f` and `--flag` style arguments
- **Default values** - Optional arguments with fallback values
- **Optional arguments** - Use `Maybe{T}` for arguments that may not be provided
- **Subcommands** - Nest command structs for multi-command CLIs
- **Positional arguments** - Fields without a flag name are matched positionally

## Installation

### Using [c3l](https://github.com/konimarti/c3l):

```sh
c3l fetch https://github.com/Ecoral360/seali.c3l
```

### Manually

1. Make sure you have the [C3 compiler installed](https://github.com/c3lang/c3)
2. Run `c3c init <YOUR_PROJECT>`
3. Clone this repository into `<YOUR_PROJECT>/lib/seali.c3l`
4. Add `"dependencies": ["seali"]` to your `project.json`

## Quick Start

```c3
module myapp;

import std::io;
import seali;

struct Cli @Command({.name = "greet", .about = "Simple program to greet a person"})
{
  String name  @Seali(arg(short, long, help = "Your name"));
  uint   count @Seali(arg(short, long, default_value = 1, help = "Number of times to greet"));
}

fn int main(String[] args) {
  Cli cli = seali::parse(Cli, args)!!;

  for (uint i = 0; i < cli.count; i++) {
    io::printfn("Hello, %s!", cli.name);
  }

  return 0;
}
```

```bash
./build/myapp --name World
# Output: Hello, World!
```

## Attribute Reference

### Command-Level Attribute: `@Command(CommandConfig)`

`@Command` takes a `CommandConfig` struct literal. All fields are optional except `.name`.

| Field | Description | Example |
|-------|-------------|---------|
| `.name` | Command name shown in help and matched for subcommands | `{.name = "myapp"}` |
| `.about` | Short description shown in help | `{.about = "My CLI app"}` |
| `.long_about` | Long description shown with `--help` | `{.long_about = "A longer description..."}` |
| `.version` | Version string | `{.version = "1.0.0"}` |
| `.help_on_empty` | Show help when invoked with no arguments | `{.help_on_empty = true}` |
| `.rename_all` | Convention for auto-generated long flag names | `{.rename_all = KEBAB_CASE}` |

`CaseConvention` values: `KEBAB_CASE` (default), `VERBATIM`.

### Field-Level Attribute: `@Seali(arg(...))`

All field configuration goes through the `@Seali(arg(...))` attribute. The `arg` macro accepts the following named options:

| Option | Description | Example |
|--------|-------------|---------|
| `short` | Auto-generate short flag from the first character of the field name | `arg(short)` |
| `short = 'X'` | Custom short flag | `arg(short = 'n')` |
| `long` | Auto-generate long flag from the field name | `arg(long)` |
| `long = "name"` | Custom long flag | `arg(long = "output")` |
| `default_value = val` | Makes the field optional with a fallback | `arg(default_value = 4)` |
| `help = "text"` | Description shown in `--help` output | `arg(help = "Input file")` |
| `subcommand` | Marks a `Maybe{SubCmd}` field as a subcommand | `arg(subcommand)` |
| `skip` | Exclude this field from CLI parsing entirely | `arg(skip)` |

Options can be combined:

```c3
String output @Seali(arg(short, long = "out", help = "Output file", default_value = "a.out"));
```

### Argument Kinds

| Kind | How to declare | Required? |
|------|---------------|-----------|
| Required flag | `arg(long)` with no `default_value` | Yes |
| Optional flag | `arg(long, default_value = val)` | No (uses default) |
| Optional (no default) | Field type is `Maybe{T}` | No (absent = `none`) |
| Positional | No `short`/`long` and no `default_value` | Yes |
| Subcommand | `Maybe{SubCmd}` + `arg(subcommand)` | No |

## Examples

### Flags with defaults

```c3
struct Cli @Command({.name = "myapp", .about = "My awesome CLI application"})
{
  String input_file @Seali(arg(short, long, help = "Input file path"));
  bool   verbose    @Seali(arg(short = 'V', long, default_value = false, help = "Enable verbose output"));
  String output     @Seali(arg(short, long = "out", help = "Output file", default_value = "out.txt"));
  uint   threads    @Seali(arg(short, default_value = 4, help = "Number of threads"));
}

fn int main(String[] args) {
  Cli cli = seali::parse(Cli, args)!!;

  if (cli.verbose) {
    io::printfn("Processing %s with %d threads", cli.input_file, cli.threads);
  }

  return 0;
}
```

```bash
./build/myapp --help
```

```
My awesome CLI application

Usage myapp [OPTIONS] --input-file <INPUT_FILE>

Options:
 -V, --verbose                   Enable verbose output [default: false]
 -o, --out <OUT>                 Output file [default: out.txt]
 -t, --threads <THREADS>         Number of threads [default: 4]
```

### Subcommands

Use a `Maybe{SubCmd}` field with `arg(subcommand)` to define subcommands. Each subcommand is its own struct marked with `@Command`.

```c3
struct Cli @Command({.name = "myapp", .about = "My package manager"})
{
  Maybe{Install} install @Seali(arg(subcommand));
  Maybe{Fetch}   fetch   @Seali(arg(subcommand));
}

struct Install @Command({.name = "install", .about = "Install a library"})
{
  String name @Seali(arg(help = "The library to install"));
}

struct Fetch @Command({.name = "fetch", .about = "Fetch a tar file"})
{
  String url @Seali(arg(help = "The URL to fetch"));
}

fn int main(String[] args) {
  Cli cli = seali::parse(Cli, args)!!;

  if (try install = cli.install.get()) {
    io::printfn("Installing: %s", install.name);
  }
  if (try fetch = cli.fetch.get()) {
    io::printfn("Fetching: %s", fetch.url);
  }

  return 0;
}
```

```bash
./build/myapp install mylib
# Output: Installing: mylib
```

## API

### `seali::parse($Cmd, String[] args)`

Parses command-line arguments into the given command struct. Automatically handles `-h`/`--help`, applies defaults, validates required fields, and exits with an error on unknown options. Returns an optional — use `!!` to panic on error or `!` to propagate.

```c3
Cli cli = seali::parse(Cli, args)!!;
```

**Supported field types:** `String`, `int`, `uint`, `bool`, `Maybe{T}`, and any struct tagged with `@Command` (for subcommands).

## Project Structure

```
seali.c3l/
├── src/
│   ├── curse.c3     # @Seali / arg attribute and config builder
│   ├── macros.c3    # Core parse macro and help generation
│   ├── utils.c3     # Utility functions
│   └── main.c3      # Example usage (commented out)
├── project.json
└── README.md
```

## Requirements

- C3 compiler (c3c)
- C3 standard library

## License

MIT License
