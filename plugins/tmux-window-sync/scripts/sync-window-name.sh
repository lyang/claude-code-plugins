#!/usr/bin/env bash
# Sync the current tmux window name to the active Claude session.
# Sourcing this file defines functions only; main() runs when executed directly.

STATE_DIR="${TMPDIR:-/tmp}/claude-tmux-window-sync"
MAX_LEN=40

# window_state_file <target>
# Echo the snapshot state-file path for the tmux window the pane belongs to.
# Keyed by tmux window id so the original name survives /resume session
# switches within the same window. Must match restore-window-name.sh.
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

# resolve_window_name <transcript_path> <cwd>
# Echoes the window name by priority:
#   custom-title > ai-title > first user prompt text > basename(cwd)
resolve_window_name() {
  local transcript="$1" cwd="$2" name=""

  if [[ -f "$transcript" ]]; then
    name="$(jq -rs 'map(select(.type=="custom-title")) | last | .customTitle // empty' "$transcript" 2>/dev/null || true)"
    if [[ -z "$name" ]]; then
      name="$(jq -rs 'map(select(.type=="ai-title")) | last | .aiTitle // empty' "$transcript" 2>/dev/null || true)"
    fi
    if [[ -z "$name" ]]; then
      name="$(jq -rs '
        map(select(.type=="user")
            | .message.content
            | if type=="array" then (map(select(.type=="text").text) | join(" ")) else . end)
        | map(select(. != null and . != ""))
        | first // empty
      ' "$transcript" 2>/dev/null || true)"
    fi
  fi

  if [[ -z "$name" ]]; then
    name="$(basename "$cwd")"
  fi

  # Sanitize and bound: replace control chars (incl. ESC/CR/NL/TAB) with
  # spaces, trim the ends, truncate by Unicode codepoint (locale-independent)
  # so multibyte names are never cut mid-character, then trim again in case the
  # cut landed on an internal space.
  jq -rn --arg s "$name" --argjson n "$MAX_LEN" \
    '$s | gsub("[[:cntrl:]]"; " ") | gsub("^[[:space:]]+|[[:space:]]+$"; "") | .[0:$n] | gsub("[[:space:]]+$"; "")'
}

# snapshot_original <target>
# Record the window's current name + automatic-rename once per window, so
# SessionEnd can restore it. Idempotent: a window already snapshotted is left
# untouched, which preserves the true original across /resume switches.
snapshot_original() {
  local target="$1" state_file orig auto
  state_file="$(window_state_file "$target")"
  [[ -e "$state_file" ]] && return 0
  mkdir -p "$STATE_DIR"
  if [[ -n "$target" ]]; then
    orig="$(tmux display-message -p -t "$target" '#{window_name}' 2>/dev/null || true)"
    auto="$(tmux show-window-options -t "$target" -v automatic-rename 2>/dev/null || true)"
  else
    orig="$(tmux display-message -p '#{window_name}' 2>/dev/null || true)"
    auto="$(tmux show-window-options -v automatic-rename 2>/dev/null || true)"
  fi
  {
    printf 'name=%s\n' "$orig"
    printf 'automatic_rename=%s\n' "$auto"
  } > "$state_file"
}

main() {
  set -euo pipefail
  [[ -n "${TMUX:-}" ]] || exit 0
  command -v jq >/dev/null 2>&1 || exit 0

  local input transcript cwd source target name
  input="$(cat)"
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
  source="$(printf '%s' "$input" | jq -r '.source // empty')"
  [[ -n "$cwd" ]] || cwd="$PWD"
  target="${TMUX_PANE:-}"

  # `source` is present only on SessionStart events (startup/resume/clear/
  # compact). Snapshot the original window name on any of them, before the
  # first rename; window-keyed idempotency keeps the earliest (true) original.
  if [[ -n "$source" ]]; then
    snapshot_original "$target"
  fi

  name="$(resolve_window_name "$transcript" "$cwd")"
  [[ -n "$name" ]] || exit 0

  if [[ -n "$target" ]]; then
    tmux rename-window -t "$target" "$name"
  else
    tmux rename-window "$name"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
