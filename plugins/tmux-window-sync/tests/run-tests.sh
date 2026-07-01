#!/usr/bin/env bash
# Plain-bash test runner. No -e: we want all assertions to run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
FIX="$HERE/fixtures"
export PATH="$HERE/stubs:$PATH"

pass=0; fail=0
check() { # desc expected actual
  if [[ "$2" == "$3" ]]; then pass=$((pass+1));
  else fail=$((fail+1)); printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$1" "$2" "$3"; fi
}
contains() { # desc needle haystack
  if [[ "$3" == *"$2"* ]]; then pass=$((pass+1));
  else fail=$((fail+1)); printf 'FAIL: %s\n  missing: %q\n  in:      %q\n' "$1" "$2" "$3"; fi
}

# ---- resolution unit tests (source the script) ----
# shellcheck disable=SC1091
source "$SCRIPTS/sync-window-name.sh"

check "custom-title wins"            "my-custom"           "$(resolve_window_name "$FIX/custom.jsonl" /tmp/proj)"
check "ai-title when no custom"      "Auto Summary"        "$(resolve_window_name "$FIX/aititle.jsonl" /tmp/proj)"
check "first prompt (string)"        "first user question" "$(resolve_window_name "$FIX/firstprompt.jsonl" /tmp/proj)"
check "first prompt (array)"         "array prompt text"   "$(resolve_window_name "$FIX/firstprompt-array.jsonl" /tmp/proj)"
check "dir basename on empty xscript" "proj"               "$(resolve_window_name "$FIX/empty.jsonl" /tmp/proj)"
check "dir basename when no file"    "myproj"              "$(resolve_window_name /nonexistent/file /a/b/myproj)"
long_name="$(resolve_window_name "$FIX/long.jsonl" /tmp/proj)"
check "truncated to 40 chars"        "40"                  "${#long_name}"

# sanitization: multibyte truncates by codepoint, control chars -> spaces, ends trimmed
mb_name="$(resolve_window_name "$FIX/multibyte.jsonl" /tmp/proj)"
check "multibyte truncated to 40 codepoints" "40" "$(jq -rn --arg s "$mb_name" '$s|length')"
check "control chars become spaces"  "a b c"               "$(resolve_window_name "$FIX/controlchars.jsonl" /tmp/proj)"
check "trims surrounding whitespace" "padded"              "$(resolve_window_name "$FIX/wstrim.jsonl" /tmp/proj)"
expected39="$(printf 'a%.0s' $(seq 1 39))"
check "no trailing space after truncation" "$expected39"   "$(resolve_window_name "$FIX/trailspace.jsonl" /tmp/proj)"

# session_title (the `claude -n NAME` name, from the hook payload) bridges the
# startup gap where the transcript file does not exist yet.
check "session_title when transcript empty"   "n-flag-name"  "$(resolve_window_name "$FIX/empty.jsonl" /tmp/proj "n-flag-name")"
check "session_title when no transcript file"  "startup-name" "$(resolve_window_name /nonexistent/file /a/b/myproj "startup-name")"
check "transcript custom-title outranks session_title" "my-custom" "$(resolve_window_name "$FIX/custom.jsonl" /tmp/proj "loser")"
check "session_title outranks ai-title"       "n-name"       "$(resolve_window_name "$FIX/aititle.jsonl" /tmp/proj "n-name")"
check "empty session_title falls back to basename" "proj"    "$(resolve_window_name "$FIX/empty.jsonl" /tmp/proj "")"

# ---- e2e tests (invoke the script as a subprocess) ----
LOG="$(mktemp)"
RDIR="$(mktemp -d)"
SDIR="$RDIR/claude-tmux-window-sync"

json() { # session_id source -> hook JSON on stdout
  printf '{"transcript_path":"%s","cwd":"/tmp/proj","session_id":"%s","source":"%s"}' \
    "$FIX/custom.jsonl" "$1" "$2"
}

# not in tmux -> no tmux calls
: > "$LOG"; rm -rf "$SDIR"
json s1 resume | env -u TMUX TMPDIR="$RDIR" TMUX_STUB_LOG="$LOG" bash "$SCRIPTS/sync-window-name.sh"
check "no-op when not in tmux" "" "$(cat "$LOG")"

# in tmux -> renames current window to the custom name
: > "$LOG"; rm -rf "$SDIR"
json s1 resume | env TMUX=1 TMUX_PANE=%3 TMPDIR="$RDIR" STUB_WINDOW_ID=@3 TMUX_STUB_LOG="$LOG" bash "$SCRIPTS/sync-window-name.sh"
contains "renames window to custom name" "rename-window -t %3 my-custom" "$(cat "$LOG")"

# startup `claude -n NAME`: transcript not created yet -> use session_title
# from the payload so the window shows NAME immediately, not the dir basename.
: > "$LOG"; rm -rf "$SDIR"
printf '{"transcript_path":"%s","cwd":"/tmp/proj","session_id":"s9","source":"startup","session_title":"my-n-name"}' "$RDIR/does-not-exist.jsonl" \
  | env TMUX=1 TMUX_PANE=%3 TMPDIR="$RDIR" STUB_WINDOW_ID=@3 TMUX_STUB_LOG="$LOG" bash "$SCRIPTS/sync-window-name.sh"
contains "startup uses session_title before transcript exists" "rename-window -t %3 my-n-name" "$(cat "$LOG")"

# startup -> snapshots the window's original name, keyed by window id
: > "$LOG"; rm -rf "$SDIR"
json startsess startup | env TMUX=1 TMUX_PANE=%5 TMPDIR="$RDIR" \
  STUB_WINDOW_ID=@7 STUB_WINDOW_NAME=bash STUB_AUTO_RENAME=on TMUX_STUB_LOG="$LOG" bash "$SCRIPTS/sync-window-name.sh"
check "snapshot written on startup" "present" "$([[ -f "$SDIR/win-_7" ]] && echo present || echo absent)"
contains "snapshot records orig name" "name=bash" "$(cat "$SDIR/win-_7" 2>/dev/null)"

# resume also snapshots, so `claude --resume` launches are restorable
: > "$LOG"; rm -rf "$SDIR"
json resumesess resume | env TMUX=1 TMUX_PANE=%5 TMPDIR="$RDIR" \
  STUB_WINDOW_ID=@7 STUB_WINDOW_NAME=bash TMUX_STUB_LOG="$LOG" bash "$SCRIPTS/sync-window-name.sh"
check "snapshot written on resume too" "present" "$([[ -f "$SDIR/win-_7" ]] && echo present || echo absent)"

# idempotent: a pre-existing snapshot is never overwritten (preserves true original)
: > "$LOG"; rm -rf "$SDIR"; mkdir -p "$SDIR"
printf 'name=%s\nautomatic_rename=%s\n' "the-real-original" "off" > "$SDIR/win-_7"
json s2 startup | env TMUX=1 TMUX_PANE=%5 TMPDIR="$RDIR" \
  STUB_WINDOW_ID=@7 STUB_WINDOW_NAME=already-ours TMUX_STUB_LOG="$LOG" bash "$SCRIPTS/sync-window-name.sh"
contains "snapshot is idempotent" "name=the-real-original" "$(cat "$SDIR/win-_7")"

# ---- restore tests ----
RESTORE="$SCRIPTS/restore-window-name.sh"

# restores name + automatic-rename, then removes the state file
: > "$LOG"; rm -rf "$SDIR"; mkdir -p "$SDIR"
printf 'name=%s\nautomatic_rename=%s\n' "orig-win" "on" > "$SDIR/win-_2"
printf '{"session_id":"sess1"}' | env TMUX=1 TMUX_PANE=%2 TMPDIR="$RDIR" STUB_WINDOW_ID=@2 TMUX_STUB_LOG="$LOG" bash "$RESTORE"
contains "restore: original window name" "rename-window -t %2 orig-win" "$(cat "$LOG")"
contains "restore: automatic-rename"     "set-window-option -t %2 automatic-rename on" "$(cat "$LOG")"
check "restore: state file removed" "absent" "$([[ -e "$SDIR/win-_2" ]] && echo present || echo absent)"

# empty saved auto -> clear the window-level override with -u
: > "$LOG"; rm -rf "$SDIR"; mkdir -p "$SDIR"
printf 'name=%s\nautomatic_rename=%s\n' "orig-win" "" > "$SDIR/win-_2"
printf '{"session_id":"sess1"}' | env TMUX=1 TMUX_PANE=%2 TMPDIR="$RDIR" STUB_WINDOW_ID=@2 TMUX_STUB_LOG="$LOG" bash "$RESTORE"
contains "restore: unset auto when empty" "set-window-option -t %2 -u automatic-rename" "$(cat "$LOG")"

# no snapshot -> no rename/option calls (only the window-id lookup runs)
: > "$LOG"; rm -rf "$SDIR"
printf '{"session_id":"ghost"}' | env TMUX=1 TMUX_PANE=%2 TMPDIR="$RDIR" STUB_WINDOW_ID=@9 TMUX_STUB_LOG="$LOG" bash "$RESTORE"
check "restore: no rename without snapshot" "" "$(grep -E 'rename-window|set-window-option' "$LOG")"

# not in tmux -> no-op
: > "$LOG"; rm -rf "$SDIR"; mkdir -p "$SDIR"
printf 'name=%s\nautomatic_rename=%s\n' "orig-win" "on" > "$SDIR/win-_2"
printf '{"session_id":"sess2"}' | env -u TMUX TMPDIR="$RDIR" STUB_WINDOW_ID=@2 TMUX_STUB_LOG="$LOG" bash "$RESTORE"
check "restore: no-op when not in tmux" "" "$(cat "$LOG")"

# ---- waiting-flash tests (the "waiting for input" indicator) ----
FLASH="$SCRIPTS/waiting-flash.sh"
# 'window-status-style' is NOT a substring of 'window-status-current-style'
# ('...status-current-style'), so these greps select each option's line exactly.
swo_style()   { grep -E 'set-window-option .* window-status-style( |$)|-u window-status-style( |$)' "$LOG" | tail -1; }
swo_current() { grep -E 'window-status-current-style' "$LOG" | tail -1; }

# not in tmux -> no-op
: > "$LOG"
env -u TMUX TMUX_PANE=%3 TMUX_STUB_LOG="$LOG" bash "$FLASH" on </dev/null
check "flash: no-op when not in tmux" "" "$(cat "$LOG")"

# on, no existing style -> append our style to "default" (keeps theme colors);
# also suppress the flash on the focused (current) window.
: > "$LOG"
env TMUX=1 TMUX_PANE=%3 STUB_WINDOW_STATUS_STYLE="" STUB_WINDOW_STATUS_CURRENT_STYLE="" TMUX_STUB_LOG="$LOG" bash "$FLASH" on </dev/null
check "flash on: appends to default" "set-window-option -t %3 window-status-style default,reverse,blink" "$(swo_style)"
check "flash on: suppresses on current window" "set-window-option -t %3 window-status-current-style default,noreverse,noblink" "$(swo_current)"

# on, custom existing style -> preserve the custom base, append our style
: > "$LOG"
env TMUX=1 TMUX_PANE=%3 STUB_WINDOW_STATUS_STYLE="fg=cyan,bg=black" STUB_WINDOW_STATUS_CURRENT_STYLE="fg=black,bg=cyan" TMUX_STUB_LOG="$LOG" bash "$FLASH" on </dev/null
check "flash on: preserves custom base" "set-window-option -t %3 window-status-style fg=cyan,bg=black,reverse,blink" "$(swo_style)"
check "flash on: preserves custom current base" "set-window-option -t %3 window-status-current-style fg=black,bg=cyan,noreverse,noblink" "$(swo_current)"

# on, already flashing -> idempotent, no stacking of the attributes
: > "$LOG"
env TMUX=1 TMUX_PANE=%3 STUB_WINDOW_STATUS_STYLE="default,reverse,blink" STUB_WINDOW_STATUS_CURRENT_STYLE="default,noreverse,noblink" TMUX_STUB_LOG="$LOG" bash "$FLASH" on </dev/null
check "flash on: idempotent (no stacking)" "set-window-option -t %3 window-status-style default,reverse,blink" "$(swo_style)"
check "flash on: idempotent current (no stacking)" "set-window-option -t %3 window-status-current-style default,noreverse,noblink" "$(swo_current)"

# off, base was default -> unset the override (revert to inherited)
: > "$LOG"
env TMUX=1 TMUX_PANE=%3 STUB_WINDOW_STATUS_STYLE="default,reverse,blink" STUB_WINDOW_STATUS_CURRENT_STYLE="default,noreverse,noblink" TMUX_STUB_LOG="$LOG" bash "$FLASH" off </dev/null
check "flash off: unset when base default" "set-window-option -t %3 -u window-status-style" "$(swo_style)"
check "flash off: unset current when base default" "set-window-option -t %3 -u window-status-current-style" "$(swo_current)"

# off, custom base -> restore the exact custom style
: > "$LOG"
env TMUX=1 TMUX_PANE=%3 STUB_WINDOW_STATUS_STYLE="fg=cyan,bg=black,reverse,blink" STUB_WINDOW_STATUS_CURRENT_STYLE="fg=black,bg=cyan,noreverse,noblink" TMUX_STUB_LOG="$LOG" bash "$FLASH" off </dev/null
check "flash off: restores custom base" "set-window-option -t %3 window-status-style fg=cyan,bg=black" "$(swo_style)"
check "flash off: restores custom current base" "set-window-option -t %3 window-status-current-style fg=black,bg=cyan" "$(swo_current)"

# off, nothing set -> unset (no-op-ish, still safe)
: > "$LOG"
env TMUX=1 TMUX_PANE=%3 STUB_WINDOW_STATUS_STYLE="" STUB_WINDOW_STATUS_CURRENT_STYLE="" TMUX_STUB_LOG="$LOG" bash "$FLASH" off </dev/null
check "flash off: unset when empty" "set-window-option -t %3 -u window-status-style" "$(swo_style)"
check "flash off: unset current when empty" "set-window-option -t %3 -u window-status-current-style" "$(swo_current)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
