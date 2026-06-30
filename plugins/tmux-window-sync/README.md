# tmux-window-sync

Keeps the current **tmux window name** in sync with the active Claude Code
session. When Claude runs inside tmux, the window shows what the session is
about; outside tmux it does nothing.

## Window name priority

1. A custom name set with `/rename`
2. A session name passed on launch with `claude -n <name>`
3. Claude's auto-generated conversation summary
4. The first user prompt (until the summary is generated)
5. The working directory's basename

The name updates on session start, on every prompt, and after each response, and
re-syncs when you switch sessions with `/resume`. When the session ends, the
window's original name and `automatic-rename` setting are restored.

A `claude -n <name>` name is read from the hook payload, so it shows **from the
moment the session starts** — even before the transcript file exists. (The
transcript is created lazily, a little after startup; without the payload name
the window would briefly fall back to the directory basename.)

A `/rename` (and the first auto-generated summary) lives only in the transcript,
so it takes effect on the **next** prompt or response, not the instant you run
it — there's no hook that fires on `/rename` itself, so expect at most one turn
of lag.

## Requirements

- `tmux` (the plugin no-ops when not running inside a tmux session)
- `jq` (used to parse the session transcript; the plugin no-ops if missing)

## Install

```bash
/plugin marketplace add lyang/claude-code-plugins
/plugin install tmux-window-sync@lyang-claude-plugins
```

## Updating

```bash
claude plugin marketplace update lyang-claude-plugins
claude plugin update tmux-window-sync@lyang-claude-plugins
```

Use the **marketplace-qualified** name — the bare `claude plugin update
tmux-window-sync` reports `Plugin "tmux-window-sync" not found`. Updates are
gated by the version in the manifest, so a restart is required to apply them.
