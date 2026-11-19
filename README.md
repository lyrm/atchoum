# atchoum

```
                   .
                  / \
                 /   \
                /     \
               /       \
              /_________\
             (___________)
              |  >   <  |          A... A... A...
              |   ___   |
              |  (   )  |  * ~ . ~ *    ATCHOUM !!!
              |  ~~~~~  |  ~ * . ~
               \\\\|////   . ~ *
                \\\|///
               /\\\|///\
              /  \\|//  \
             / |  \|/  | \
            (_)|       |(_)
               |_______|
               |   |   |
              _|   |   |_
             (_____|_____)
```

A Claude Code plugin that provides an MCP server with
[Merlin](https://github.com/ocaml/merlin)-powered tools, so that Claude
navigates and edits OCaml code through Merlin rather than through text-based
tools such as `grep` or `sed`.

> **Status:** early development. The server exposes a single tool.

## Tools

The tools appear in Claude Code as `mcp__plugin_atchoum_merlin__<tool>`.

| Tool | Arguments | Result |
|------|-----------|--------|
| `type_enclosing` | `file` (path, absolute recommended), `line` (from 1), `col` (from 0) | Merlin's raw JSON answer to `type-enclosing`: the enclosing expressions, innermost first, with their positions and types |
| `locate` | `file`, `line`, `col` as above; optional `prefix` (identifier to locate instead of the one at the position, e.g. `List.map`) and `look_for` (`interface` or `implementation`) | Merlin's raw JSON answer to `locate`: the file and position of the definition, or a string explaining why it could not be found |

Each tool runs `ocamlmerlin single <command>` with the file's contents on
standard input.

## Requirements

- [opam](https://opam.ocaml.org/) 2.2 or later, to build the server.
- `ocamlmerlin` in the `PATH` of Claude Code at run time. It must match the
  compiler of the project being analysed, so it comes from that project's
  switch, not from atchoum's.

## Build

The project builds in a local opam switch:

```sh
opam switch create . 5.5.2 --deps-only --with-test --with-dev-setup
eval $(opam env)
dune build
dune test
```

`dune build` produces `_build/install/default/bin/atchoum-mcp`, the executable
that `.mcp.json` launches.

## Layout

```
atchoum/
├── .claude-plugin/
│   └── plugin.json   # Plugin manifest (name, version, metadata)
├── .mcp.json         # MCP server declaration
├── agents/           # Subagent definitions (*.md)
├── commands/         # Slash commands (*.md)
├── hooks/            # Hook configuration (hooks.json) and scripts
├── skills/           # Skills (<skill-name>/SKILL.md)
├── bin/              # atchoum-mcp: Eio main loop serving MCP over stdio
├── lib/              # Merlin calls (merlin.ml) and mcp-kit tools (server.ml)
└── test/             # Alcotest suite
```

Claude Code discovers every component directory at the plugin root
automatically. Empty directories hold a `.gitkeep` until they get content.

Paths inside the plugin must go through `${CLAUDE_PLUGIN_ROOT}`, which
Claude Code sets to the plugin's install location.

## MCP server

`.mcp.json` declares a stdio server named `merlin`, launched from
`${CLAUDE_PLUGIN_ROOT}/_build/install/default/bin/atchoum-mcp`. The server is
built with [mcp-kit](https://gitlab.com/nomadic-labs/ai-harness/ocaml-mcp) and
[Eio](https://github.com/ocaml-multicore/eio).

If the executable has not been built, `/mcp` shows the server as failed; the
rest of the plugin still loads.

## Local testing

Load the plugin from a checkout without installing it:

```sh
claude --plugin-dir /path/to/atchoum
```

Then use `/plugin` to check that `atchoum` is loaded, and `/mcp` to check the
state of the `merlin` server.

## License

MIT, see [LICENSE](LICENSE).
