# claude-code-plugins

Personal Claude Code plugin marketplace.

## Installation

```bash
/plugin marketplace add lyang/claude-code-plugins
```

## Available Plugins

| Plugin | Description |
|---|---|
| [serena-mcp-docker](plugins/serena-mcp-docker/) | Launch Serena MCP server in Docker for LSP-powered code intelligence |
| [tmux-window-sync](plugins/tmux-window-sync/) | Sync the tmux window name to the active Claude Code session, and highlight the window when it's waiting for input |

## Installing a Plugin

```bash
/plugin install serena-mcp-docker@lyang-claude-plugins
```

## Testing

CI (`.github/workflows/tests.yml`) runs on every push and pull request. A
`discover` job finds the plugins that ship tests and fans out a **separate test
job per plugin**, each run on Ubuntu and macOS; a `lint` job runs `shellcheck`
over all plugin shell scripts.

A plugin opts in to CI by providing an executable `tests/run-tests.sh` that
exits non-zero on failure — new plugins are discovered automatically, with no
workflow changes. Run every plugin's suite locally the same way CI does:

```bash
bash tests/run-all.sh
```
