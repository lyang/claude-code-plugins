# tmux-window-sync

Keeps the current **tmux window name** in sync with the active Claude Code
session. When Claude runs inside tmux, the window shows what the session is
about; outside tmux it does nothing.

## Window name priority

1. Custom name set with `/rename`
2. Claude's auto-generated conversation summary
3. The first user prompt (until the summary is generated)
4. The working directory's basename

The name updates on session start, on every prompt, and after each response, and
re-syncs when you switch sessions with `/resume`. When the session ends, the
window's original name and `automatic-rename` setting are restored.

Because the sync runs on those events, a `/rename` (and the first auto-generated
summary) takes effect on the **next** prompt or response, not the instant you
run it — there's no hook that fires on `/rename` itself, so expect at most one
turn of lag.

## Requirements

- `tmux` (the plugin no-ops when not running inside a tmux session)
- `jq` (used to parse the session transcript; the plugin no-ops if missing)

## Install

```bash
/plugin install tmux-window-sync@claude-code-plugins
```
