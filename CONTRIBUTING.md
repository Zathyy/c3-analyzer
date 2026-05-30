# Contributing

This repository follows active C3 language development. Please use a recent C3
compiler, keep submodules initialized, and run `c3fmt` before committing parser
changes.

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

## Install c3fmt

This repository uses `c3fmt` and the checked-in `.c3fmt` configuration. The
formatter supports in-place formatting, stdin/stdout formatting, explicit config
paths, and check mode.

- c3fmt repository: <https://github.com/lmichaudel/c3fmt>

Build from source:

```sh
git clone https://github.com/lmichaudel/c3fmt.git
cd c3fmt
c3c build
install -m 0755 build/c3fmt ~/.local/bin/c3fmt
```

Make sure `~/.local/bin` is on your `PATH`, or install the binary somewhere
already on your `PATH`.

Verify the formatter:

```sh
c3fmt --version
c3fmt --check .
```

Format the repository:

```sh
c3fmt --in-place .
```

## Editor Setup

The C3 editor plugin repository provides syntax plugins for common editors,
including VS Code, NeoVim, Vim, and Zed:

- C3 editor plugins: <https://github.com/c3lang/editor-plugins>

The examples below assume `c3fmt` is on your `PATH`.

### VS Code And VS Code-Based Editors

Install C3 syntax support from the C3 editor plugins or the marketplace
extension you normally use for C3 files. For automatic formatting, use a
run-on-save extension that can invoke an external command because the syntax
plugin itself is not the formatter.

One common setup is the `emeraldwalk.runonsave` extension:

```json
{
  "emeraldwalk.runonsave": {
    "commands": [
      {
        "match": "\\.c3i?$",
        "cmd": "tmp=$(mktemp) && c3fmt --stdin --stdout < \"${file}\" > \"$tmp\" && cp \"$tmp\" \"${file}\"; rc=$?; rm -f \"$tmp\"; exit $rc"
      }
    ]
  }
}
```

If your editor supports tasks but not run-on-save commands, add a task and bind
it to a key:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "c3fmt current file",
      "type": "shell",
      "command": "tmp=$(mktemp) && c3fmt --stdin --stdout < \"${file}\" > \"$tmp\" && cp \"$tmp\" \"${file}\"; rc=$?; rm -f \"$tmp\"; exit $rc",
      "problemMatcher": []
    }
  ]
}
```

### Zed

Install the C3 extension from Zed's extension panel. Zed supports per-language
external formatters in `settings.json`; external formatters receive the buffer
on stdin and should write formatted text to stdout.

```json
{
  "languages": {
    "C3": {
      "format_on_save": "on",
      "formatter": {
        "external": {
          "command": "c3fmt",
          "arguments": ["--stdin", "--stdout"]
        }
      }
    }
  }
}
```

If your Zed installation uses a different language name for the C3 extension,
open `zed: open default settings` from the command palette and copy the exact
language key into the snippet above.

### Neovim

Use the C3 syntax plugin from `c3lang/editor-plugins`, then add a format-on-save
autocmd:

```lua
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.c3", "*.c3i" },
  callback = function()
    local view = vim.fn.winsaveview()
    vim.cmd("%!c3fmt --stdin --stdout")
    vim.fn.winrestview(view)
  end,
})
```

### Vim

Use the Vim plugin from `c3lang/editor-plugins`, then add this to your vimrc:

```vim
augroup c3fmt
  autocmd!
  autocmd BufWritePre *.c3,*.c3i let l:view = winsaveview() | silent %!c3fmt --stdin --stdout | call winrestview(l:view)
augroup END
```

## Git Hooks

This repository tracks Git hooks in `.githooks/`. Enable them once per clone:

```sh
git config core.hooksPath .githooks
```

The pre-commit hook formats each tracked C3 source file with the same
stdin/stdout command used by the editor integrations above:
`c3fmt --stdin --stdout`. If formatting changes any tracked C3 source files, the
hook re-stages those files so the commit includes the formatted code.

## Test Before Sending Changes

Run the formatter and tests before pushing:

```sh
c3fmt --in-place .
c3c test
```

For parser changes, add or update focused tests under `test/` so the grammar or
AST behavior is covered directly.
