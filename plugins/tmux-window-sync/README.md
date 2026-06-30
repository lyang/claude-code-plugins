# tmux-window-sync

Keeps the current **tmux window name** in sync with the active Claude Code
session, and **highlights the window** when the session is waiting for your
input. When Claude runs inside tmux, the window shows what the session is about
and flags when it needs you; outside tmux it does nothing.

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

## Waiting-for-input indicator

When Claude finishes a turn and is waiting for your input, the window's entry in
the tmux status bar is highlighted so you can spot it from another window. It
clears the moment you send your next prompt.

The highlight is applied by appending a style to the window's
`window-status-style` (`reverse,blink` by default) and is removed again when you
respond — your existing window/status colors are preserved and restored. Only
style **attributes** are used, never colors, because:

- A themed status bar usually hardcodes colors in `window-status-format`, which
  override `window-status-style` colors — but attributes pass through.
- `reverse` (inverse video) is honored by essentially every terminal, including
  Terminal.app, with no configuration. `blink` animates on terminals that
  support it (e.g. iTerm2 with "blinking text" enabled), and is simply ignored
  elsewhere — so you always get at least the `reverse` cue.

Note the highlight shows on the window's entry while it is **not** your focused
window (tmux draws the focused window with `window-status-current-style`), which
is exactly when you need it. To change the look, edit `WAITING_STYLE` at the top
of `scripts/waiting-flash.sh` (e.g. `reverse`, `blink`, `reverse,blink,bold`).

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
