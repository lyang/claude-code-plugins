#!/usr/bin/env bash
# Toggle a "waiting for input" indicator on the current tmux window.
#
# tmux draws a window's entry in the status bar with one of two styles depending
# on focus: window-status-current-style for the *active* window, and
# window-status-style for every *other* (unfocused) window. To make the
# indicator behave like a real "needs attention" signal we drive both:
#
#   * window-status-style        += WAITING_STYLE   (reverse,blink)  -> the tab
#     flashes while the window is UNFOCUSED, so you notice it from another window.
#   * window-status-current-style += SUPPRESS_STYLE (noreverse,noblink) -> the
#     flash is explicitly cancelled while the window IS focused. This is what
#     makes the flash stop the instant you switch TO the window (tmux re-renders
#     it as the current window with the flash attributes turned off) -- no
#     window-focus hook needed, which Claude Code doesn't emit anyway.
#
# Only style *attributes* are used, not colors: attributes survive a themed
# status bar (which usually hardcodes colors in window-status-format) and work
# on terminals/themes that ignore colors. `reverse` is honored everywhere (incl.
# Terminal.app); `blink` animates where the terminal supports it.
#
# Usage: waiting-flash.sh on|off   (hook JSON on stdin is ignored)

WAITING_STYLE="reverse,blink"
SUPPRESS_STYLE="noreverse,noblink"

# append_style <target> <option> <suffix>
# Append <suffix> to the window option <option>, preserving whatever base style
# is already there. Idempotent: strips a trailing ",<suffix>" first so repeated
# calls never stack the attributes.
append_style() {
  local target="$1" option="$2" suffix="$3" cur base
  cur="$(tmux show-window-options -t "$target" -v "$option" 2>/dev/null || true)"
  base="${cur%,"$suffix"}"
  [[ -n "$base" ]] || base="default"
  tmux set-window-option -t "$target" "$option" "$base,$suffix"
}

# remove_style <target> <option> <suffix>
# Remove <suffix>, restoring the original <option>. If the base was
# empty/default (the common case: no per-window override), unset it so the
# window reverts to the inherited default; otherwise restore the exact base.
remove_style() {
  local target="$1" option="$2" suffix="$3" cur base
  cur="$(tmux show-window-options -t "$target" -v "$option" 2>/dev/null || true)"
  base="${cur%,"$suffix"}"
  if [[ -z "$base" || "$base" == "default" ]]; then
    tmux set-window-option -t "$target" -u "$option"
  else
    tmux set-window-option -t "$target" "$option" "$base"
  fi
}

# flash_on <target> -- flash while unfocused, stay clean while focused.
flash_on() {
  local target="$1"
  append_style "$target" window-status-style "$WAITING_STYLE"
  append_style "$target" window-status-current-style "$SUPPRESS_STYLE"
}

# flash_off <target> -- restore both styles to their pre-flash state.
flash_off() {
  local target="$1"
  remove_style "$target" window-status-style "$WAITING_STYLE"
  remove_style "$target" window-status-current-style "$SUPPRESS_STYLE"
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
