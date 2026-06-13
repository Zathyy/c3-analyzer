# C3 Analyzer

`c3-analyzer` is a C3 parser library and command-line parser target. The project
tracks active C3 language work, so contributors should develop with a recent C3
compiler and keep parser changes covered by the C3 test suite.

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

## Error Nodes

The parser currently distinguishes these recovery node meanings:

- `ERROR`: Cannot guess the intent from the current shape (names, types, expressions). Skips to a safe structural pillar.
- `MISSING`: Omitted syntax (punctuation, keywords).

## Contributing

Contributions should follow the setup workflow in [CONTRIBUTING.md](CONTRIBUTING.md).
In particular, clone with submodules, use a recent pre-release C3 compiler when
working on parser behavior, and see the editor plugin suggestions there.
