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
| `type_enclosing` | `file` (path, absolute recommended), `line` (from 1), `col` (from 0) | The type of the innermost expression at the position, e.g. `('a -> 'b) -> 'a list -> 'b list` |
| `locate` | `file`, `line`, `col` as above; optional `prefix` (identifier to locate instead of the one at the position, e.g. `List.map`) and `look_for` (`interface` or `implementation`) | `FILE:LINE:COL` of the definition, then its source line; an error result with Merlin's reason when it is not found |

Each tool runs `ocamlmerlin single <command>` with the file's contents on
standard input, and keeps only the useful part of Merlin's JSON answer.

Guidance on when to use the tools lives in two places in
[`lib/server.ml`](lib/server.ml): the server `instructions`, which Claude Code
adds to the system prompt while the server is connected, and each tool's
description.

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
that the plugin launches.

## Layout

```
atchoum/
├── .claude-plugin/
│   └── plugin.json   # Plugin manifest: metadata and MCP server declaration
├── agents/           # Subagent definitions (*.md)
├── commands/         # Slash commands (*.md)
├── hooks/            # Hook configuration (hooks.json) and scripts
├── skills/           # Skills (<skill-name>/SKILL.md)
├── server/           # atchoum-mcp: Eio main loop serving MCP over stdio
├── lib/              # Merlin calls (merlin.ml) and mcp-kit tools (server.ml)
└── test/             # Alcotest suite
```

Claude Code discovers every component directory at the plugin root
automatically. Empty directories hold a `.gitkeep` until they get content.

Paths inside the plugin must go through `${CLAUDE_PLUGIN_ROOT}`, which
Claude Code sets to the plugin's install location.

## MCP server

The `mcpServers` field of `.claude-plugin/plugin.json` declares a stdio server
named `merlin`, launched from
`${CLAUDE_PLUGIN_ROOT}/_build/install/default/bin/atchoum-mcp`. The server is
built with [mcp-kit](https://gitlab.com/nomadic-labs/ai-harness/ocaml-mcp) and
[Eio](https://github.com/ocaml-multicore/eio).

The declaration lives in `plugin.json` rather than in a root `.mcp.json`:
Claude Code would also read a root `.mcp.json` as this repository's project
MCP configuration, where `${CLAUDE_PLUGIN_ROOT}` is undefined.

If the executable has not been built, `/mcp` shows the server as failed; the
rest of the plugin still loads.

## Evals

`evals/` holds [`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals.md)
cases: each runs a prompt on a scaffolded project with and without the plugin.

```sh
dune build
./evals/run.sh --case type-of-stdlib-function --runs 3
```

| Case | Tool | Question |
|------|------|----------|
| `type-of-stdlib-function` | `type_enclosing` | Type of `Seq.unfold` (answerable from memory) |
| `shadowed-list-map` | `type_enclosing` | Type of a `List.map` shadowed through `open` and `include` |
| `inferred-variant-type` | `type_enclosing` | Inferred type of an unannotated function with optional, labelled and polymorphic variant arguments |
| `aliased-create` | `locate` | Definition of `create` among 8 homonyms, reached through a module alias |
| `aliased-create-large` | `locate` | Same with 80 homonyms and 80 aliases |

| `merlin-repo-fold-n-map` | `type_enclosing` | Type of a Merlin-specific `List` function reached through `open Std` |
| `merlin-repo-punned-field` | `type_enclosing` | Inferred type of an unannotated, unexported function of `src/analysis/destruct.ml` |
| `merlin-repo-let-open-flatten` | `locate` | Definition of an unqualified `flatten` resolved through a local `let open` |
| `merlin-repo-printtyp-alias` | `locate` | Definition of a function reached through a local alias that shadows a compiler module |

The `hard` cases scaffold small dune projects (`./evals/run.sh --tag hard`);
they run `dune build`.

The `merlin-repo` cases (`./evals/run.sh --tag merlin-repo`) ask questions
about the code of Merlin itself. Their scaffold copies a prebuilt clone, which
must exist first:

```sh
git clone --depth 1 --branch v5.9.1-505 https://github.com/ocaml/merlin ~/src/merlin-bench
cd ~/src/merlin-bench
opam exec --switch=/path/to/atchoum -- dune build @src/check
```

The clone must be built with atchoum's local switch: `run.sh` runs the evals
in that switch's environment, and Merlin cannot read a project built by
another version of dune. The clone's path is set in each case's
`scaffold.sh`.

`run.sh` runs the evals on a minimal copy of the plugin (the checkout's
`_opam/` and `_build/` exceed the eval's entry limit), with the real MCP
server. It then copies the run traces to `evals/results/<timestamp>/traces/`
and prints mean tokens, cost and turns per case and arm (`evals/summarize.py`,
also written to `tokens.json`).

## Using the plugin

Build the server first (see [Build](#build)). Claude Code launches the
executable from the checkout, so it must exist in `_build`.

### Install from the local marketplace (CLI and VS Code)

`.claude-plugin/marketplace.json` makes the checkout a marketplace named
`atchoum-dev`. In Claude Code, in the terminal or in the VS Code extension:

```
/plugin marketplace add /path/to/atchoum
/plugin install atchoum@atchoum-dev
```

In VS Code, the **Manage plugins** dialog (`/plugins`) does the same from its
Marketplaces tab. A plugin from a local marketplace loads in place: nothing is
copied, and `${CLAUDE_PLUGIN_ROOT}` is the checkout itself.

### Load for one session only (CLI)

```sh
claude --plugin-dir /path/to/atchoum
```

Do not combine it with the installed plugin: the session copy replaces the
installed one.

### Check and reload

- `/mcp` lists the plugin's `merlin` server and its tools.
- After editing plugin files, run `/reload-plugins` or start a new session.
- After rebuilding the server, start a new session: a running server keeps its
  connection.
- `ocamlmerlin` (and `dune`) must be in the `PATH` of the Claude Code process,
  from the switch of the project being analysed. In VS Code, start the editor
  from a shell where `eval $(opam env)` has been run.

## License

MIT, see [LICENSE](LICENSE).
