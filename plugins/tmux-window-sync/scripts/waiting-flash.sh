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
# Usage: waiting-flash.sh on|off|ask   (hook JSON on stdin)
#   on   flash unconditionally
#   off  clear the flash
#   ask  Stop-hook mode: flash only if Claude's last message reads like a
#        question for the user, otherwise clear any stale flash. A regex catches
#        obvious questions instantly; anything else is classified by Haiku in a
#        detached background process (set TMUX_WINDOW_SYNC_LLM=0 to disable).

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

# last_message <hook-json>
# Echo Claude's final message: the Stop payload's last_assistant_message, else
# the last assistant text block in the transcript.
last_message() {
  local json="$1" msg transcript
  msg="$(jq -r '.last_assistant_message // empty' <<<"$json" 2>/dev/null || true)"
  if [[ -z "$msg" ]]; then
    transcript="$(jq -r '.transcript_path // empty' <<<"$json" 2>/dev/null || true)"
    [[ -f "$transcript" ]] && msg="$(jq -rs '
        map(select(.type=="assistant") | .message.content
            | if type=="array" then (map(select(.type=="text").text) | join("\n")) else . end
            | select(. != null and . != ""))
        | last // empty' "$transcript" 2>/dev/null || true)"
  fi
  printf '%s' "$msg"
}

# is_asking <message>
# True when one of the final two paragraphs has a line ending in "?" (ignoring trailing
# markdown/quote/bracket characters). Looking beyond the last line covers "Which one?" followed by an option list.
is_asking() {
  local para
  para="$(awk 'BEGIN{RS="";ORS="\n"} {a=b; b=$0} END{print a; print b}' <<<"$1")"
  grep -Eq '\?[]*_`"'"'"')>[:space:]]*$' <<<"$para"
}

STATE_DIR="${TMPDIR:-/tmp}/claude-tmux-window-sync"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

# token_file <target> -- per-window marker for the pending background check.
token_file() { printf '%s/ask-%s' "$STATE_DIR" "${1//[^A-Za-z0-9]/_}"; }

# llm_says_asking <message>
# Ask Haiku whether the message needs the user's input. Hooks are disabled in
# the nested session so its own Stop hook can't recurse into this script.
llm_says_asking() {
  local prompt answer msg="$1"
  # ${msg: -N} is empty when msg is shorter than N, so only trim long messages.
  (( ${#msg} > 1500 )) && msg="${msg: -1500}"
  prompt="Answer with exactly one word, YES or NO. Does this assistant message end by asking the user a question or requesting their input or decision before work can continue?

Message:
$msg"
  answer="$(cd "${TMPDIR:-/tmp}" && "$CLAUDE_BIN" -p --model haiku \
    --settings '{"disableAllHooks":true}' --no-session-persistence \
    --tools "" --disable-slash-commands "$prompt" 2>/dev/null </dev/null || true)"
  [[ "$answer" =~ ^[[:space:]]*[Yy][Ee][Ss] ]]
}

# ask_later <target> <message>
# Classify in the background, then flash only if this turn is still the latest
# (the token is deleted by `off` when the next prompt is submitted).
ask_later() {
  local target="$1" msg="$2" tf tok
  tf="$(token_file "$target")"
  mkdir -p "$STATE_DIR"
  tok="$$.$RANDOM.$SECONDS"
  printf '%s' "$tok" > "$tf"
  check() {
    if llm_says_asking "$msg" && [[ "$(cat "$tf" 2>/dev/null)" == "$tok" ]]; then
      flash_on "$target"
    fi
  }
  if [[ "${TMUX_WINDOW_SYNC_LLM_SYNC:-0}" == 1 ]]; then
    check
  else
    ( check ) >/dev/null 2>&1 </dev/null &
    disown 2>/dev/null || true
  fi
}

main() {
  set -euo pipefail
  [[ -n "${TMUX:-}" ]] || exit 0
  command -v tmux >/dev/null 2>&1 || exit 0
  # Always drain stdin so the hook writer never gets SIGPIPE.
  local input
  input="$(cat 2>/dev/null || true)"

  local action="${1:-}" target="${TMUX_PANE:-}"
  [[ -n "$target" ]] || target="$(tmux display-message -p '#{window_id}' 2>/dev/null || true)"
  [[ -n "$target" ]] || exit 0

  case "$action" in
    on)  flash_on "$target" ;;
    off) rm -f "$(token_file "$target")"; flash_off "$target" ;;
    ask) local msg=""
         command -v jq >/dev/null 2>&1 && msg="$(last_message "$input")"
         if [[ -n "$msg" ]] && is_asking "$msg"; then
           rm -f "$(token_file "$target")"; flash_on "$target"
         else
           flash_off "$target"
           if [[ -n "$msg" && "${TMUX_WINDOW_SYNC_LLM:-1}" != 0 ]] \
              && command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
             ask_later "$target" "$msg"
           fi
         fi ;;
    *)   exit 0 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
