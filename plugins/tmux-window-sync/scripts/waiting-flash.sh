#!/usr/bin/env bash
# Toggle a "waiting for input" indicator on the current tmux window.
#
# It appends WAITING_STYLE to the window's window-status-style (the style tmux
# uses for the window's entry in the status bar while it is NOT the focused
# window) and removes it again on clear. Only style *attributes* are used, not
# colors: attributes survive a themed status bar (which usually hardcodes
# colors in window-status-format) and work on terminals/themes that ignore
# colors. `reverse` is honored everywhere (incl. Terminal.app); `blink`
# animates where the terminal supports it.
#
# Usage: waiting-flash.sh on|off   (hook JSON on stdin is ignored)

WAITING_STYLE="reverse,blink"

# flash_on <target>
# Append WAITING_STYLE to the window's current window-status-style, preserving
# whatever base style is already there. Idempotent: strips a trailing
# ",WAITING_STYLE" first so repeated calls never stack the attributes.
flash_on() {
  local target="$1" cur base
  cur="$(tmux show-window-options -t "$target" -v window-status-style 2>/dev/null || true)"
  base="${cur%,"$WAITING_STYLE"}"
  [[ -n "$base" ]] || base="default"
  tmux set-window-option -t "$target" window-status-style "$base,$WAITING_STYLE"
}

# flash_off <target>
# Remove WAITING_STYLE, restoring the original window-status-style. If the base
# was empty/default (the common case: no per-window override), unset it so the
# window reverts to the inherited default; otherwise restore the exact base.
flash_off() {
  local target="$1" cur base
  cur="$(tmux show-window-options -t "$target" -v window-status-style 2>/dev/null || true)"
  base="${cur%,"$WAITING_STYLE"}"
  if [[ -z "$base" || "$base" == "default" ]]; then
    tmux set-window-option -t "$target" -u window-status-style
  else
    tmux set-window-option -t "$target" window-status-style "$base"
  fi
}

main() {
  set -euo pipefail
  [[ -n "${TMUX:-}" ]] || exit 0
  command -v tmux >/dev/null 2>&1 || exit 0
  # Hooks pipe JSON we don't need; drain it so the writer never gets SIGPIPE.
  cat >/dev/null 2>&1 || true

  local action="${1:-}" target="${TMUX_PANE:-}"
  [[ -n "$target" ]] || target="$(tmux display-message -p '#{window_id}' 2>/dev/null || true)"
  [[ -n "$target" ]] || exit 0

  case "$action" in
    on)  flash_on "$target" ;;
    off) flash_off "$target" ;;
    *)   exit 0 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
