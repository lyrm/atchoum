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

> **Status:** early scaffolding. The MCP server is not implemented yet.

## Layout

```
atchoum/
├── .claude-plugin/
│   └── plugin.json   # Plugin manifest (name, version, metadata)
├── .mcp.json         # MCP server declaration
├── agents/           # Subagent definitions (*.md)
├── commands/         # Slash commands (*.md)
├── hooks/            # Hook configuration (hooks.json) and scripts
└── skills/           # Skills (<skill-name>/SKILL.md)
```

Claude Code discovers every component directory at the plugin root
automatically. Empty directories hold a `.gitkeep` until they get content.

Paths inside the plugin must go through `${CLAUDE_PLUGIN_ROOT}`, which
Claude Code sets to the plugin's install location.

## MCP server

`.mcp.json` declares a stdio server named `merlin`, launched from
`${CLAUDE_PLUGIN_ROOT}/_build/install/default/bin/atchoum-mcp`. That is where
`dune build` installs an executable whose `public_name` is `atchoum-mcp`.
The tools it exposes will appear in Claude Code as
`mcp__plugin_atchoum_merlin__<tool>`.

Until that executable exists, `/mcp` shows the server as failed. That is
expected and does not prevent the rest of the plugin from loading.

## Local testing

Load the plugin from a checkout without installing it:

```sh
claude --plugin-dir /path/to/atchoum
```

Then use `/plugin` to check that `atchoum` is loaded, and `/mcp` to check the
state of the `merlin` server.

## License

MIT, see [LICENSE](LICENSE).
