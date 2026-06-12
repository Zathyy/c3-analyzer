# Contributing

This repository follows active C3 language development. Please use a recent C3
compiler and keep submodules initialized.

## Clone The Repository

Clone with submodules so the libraries under `lib/` are present:

```sh
git clone --recurse-submodules git@github.com:joshring/c3_parser.git
cd c3_parser
```

If you already cloned the repository without submodules, repair the checkout:

```sh
git submodule update --init --recursive
```

## Install C3

Use the latest pre-release C3 compiler when developing this repository unless a
maintainer asks you to test a specific release. The official compiler repository
publishes stable release archives and links to latest pre-release binaries:

- C3 compiler: <https://github.com/c3lang/c3c>
- Latest pre-release: <https://github.com/c3lang/c3c/releases/tag/latest-prerelease>
- C3 manual: <https://c3-lang.org>

Download the archive for your platform, unpack it, and put the `c3c` executable
on your `PATH`. On macOS, unsigned downloaded binaries may need quarantine
approval:

```sh
xattr -d com.apple.quarantine /path/to/c3c
```

Verify the compiler is available:

```sh
c3c --version
c3c test
```

## Editor Support

The C3 editor plugin repository provides syntax plugins for common editors,
including VS Code, NeoVim, Vim, and Zed:

- C3 editor plugins: <https://github.com/c3lang/editor-plugins>

These plugins can help with syntax highlighting, filetype detection, and other
editor integration while working on parser changes.

## Test Before Sending Changes

Run the tests before pushing:

```sh
c3c test
```

For parser changes, add or update focused tests under `test/` so the grammar or
AST behavior is covered directly.

## AI usage in contributions

AI tools do not change contributor responsibilities.

**Pull Requests**

- You must fully understand and be able to explain all submitted code.
- Code must meet normal standards: style, clarity and tests.
- **Respect maintainer time:** Do not use PR reviews as an AI feedback loop.
- If review effort exceeds implementation effort, the PR may be rejected.
- Be transparent if a significant portion of the code is AI-generated.
- **Copyright risks:** The legal status of AI-generated code is uncertain and may become copyright encumbered in the future. Direct copy-pasting of AI-generated code cannot be accepted.

**Issues and Reports**

- Verify all claims, errors, and reproducible steps before submitting.
- Do not paste raw AI output. Write concise reports in your own words.

Use AI as a tool, not a substitute for understanding or effort.
