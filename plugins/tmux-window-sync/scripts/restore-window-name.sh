#!/usr/bin/env bash
# Restore the tmux window name saved when the plugin first touched this window.
# Sourcing defines functions only; main() runs when executed directly.

STATE_DIR="${TMPDIR:-/tmp}/claude-tmux-window-sync"

# window_state_file <target>
# Echo the snapshot state-file path for the tmux window the pane belongs to.
# Must match the keying in sync-window-name.sh.
window_state_file() {
  local target="$1" wid
  if [[ -n "$target" ]]; then
    wid="$(tmux display-message -p -t "$target" '#{window_id}' 2>/dev/null || true)"
  else
    wid="$(tmux display-message -p '#{window_id}' 2>/dev/null || true)"
  fi
  [[ -n "$wid" ]] || wid="unknown"
  printf '%s/win-%s' "$STATE_DIR" "${wid//[^A-Za-z0-9]/_}"
}

# restore_window_name <target>
# Restore the saved name + automatic-rename for the pane's window, then drop
# the state file. No-op when no snapshot exists for this window.
restore_window_name() {
  local target="${1:-}" state_file orig="" auto="" k v
  state_file="$(window_state_file "$target")"
  [[ -f "$state_file" ]] || return 0
  while IFS='=' read -r k v; do
    case "$k" in
      name)             orig="$v" ;;
      automatic_rename) auto="$v" ;;
    esac
  done < "$state_file"

  if [[ -n "$orig" ]]; then
    if [[ -n "$target" ]]; then
      tmux rename-window -t "$target" "$orig"
    else
      tmux rename-window "$orig"
    fi
  fi

  # Restore the saved automatic-rename value. When the snapshot captured an
  # empty value (no window-level override originally), clear the override our
  # rename-window created with -u, reverting the window to the global default.
  if [[ -n "$auto" ]]; then
    if [[ -n "$target" ]]; then
      tmux set-window-option -t "$target" automatic-rename "$auto"
    else
      tmux set-window-option automatic-rename "$auto"
    fi
  else
    if [[ -n "$target" ]]; then
      tmux set-window-option -t "$target" -u automatic-rename
    else
      tmux set-window-option -u automatic-rename
    fi
  fi

  rm -f "$state_file"
}

main() {
  set -euo pipefail
  [[ -n "${TMUX:-}" ]] || exit 0
  restore_window_name "${TMUX_PANE:-}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
