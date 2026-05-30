# C3 Parser

`c3_parser` is a C3 parser library and command-line parser target. The project
tracks active C3 language work, so contributors should develop with a recent C3
compiler and keep parser changes covered by the C3 test suite.

## Quick Start

Clone the repository with its submodules:

```sh
git clone --recurse-submodules git@github.com:joshring/c3_parser.git
cd c3_parser
```

If you already cloned without submodules, initialize them before building:

```sh
git submodule update --init --recursive
```

Install a recent C3 compiler, then run the tests:

```sh
c3c test
```

The repository uses the submodules under `lib/` as C3 library dependencies, and
`project.json` points `dependency-search-paths` at that directory.

## Build Targets

The main project targets are defined in `project.json`:

- `c3_parser`: executable target with the `PARSER_CLI` feature.
- `c3_parser_lib`: static library target with the `PARSER_LIB` feature.

Common commands:

```sh
c3c build c3_parser
c3c build c3_parser_lib
c3c test
```

## Formatting

This repository uses `c3fmt` with the checked-in `.c3fmt` configuration. Format
the full repository before sending changes:

```sh
c3fmt --in-place .
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for compiler setup, formatter setup,
editor integration, and the repository pre-commit hook.

## Error Nodes

The parser currently distinguishes these recovery node meanings:

- `ERROR`: an incorrect node is present and parsing cannot confidently continue
  from that exact shape.
- `MISSING`: parsing proceeds as if a missing node exists, and the rest of the
  surrounding construct can still be valid.

## Contributing

Contributions should follow the setup and formatting workflow in
[CONTRIBUTING.md](CONTRIBUTING.md). In particular, clone with submodules, use a
recent pre-release C3 compiler when working on parser behavior, install `c3fmt`,
and enable the tracked Git hooks with:

```sh
git config core.hooksPath .githooks
```
