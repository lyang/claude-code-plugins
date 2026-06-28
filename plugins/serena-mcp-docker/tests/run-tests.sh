#!/usr/bin/env bash
# Plain-bash test runner for serena-mcp-docker. No -e: we want every
# assertion to run. Both scripts only shell out to docker / openers / uname,
# so we stub those on PATH and assert on the command lines they would run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
export PATH="$HERE/stubs:$PATH"

pass=0; fail=0
contains() { # desc needle haystack
  if [[ "$3" == *"$2"* ]]; then pass=$((pass+1));
  else fail=$((fail+1)); printf 'FAIL: %s\n  missing: %q\n  in:      %q\n' "$1" "$2" "$3"; fi
}
not_contains() { # desc needle haystack
  if [[ "$3" != *"$2"* ]]; then pass=$((pass+1));
  else fail=$((fail+1)); printf 'FAIL: %s\n  unexpected: %q\n  in:         %q\n' "$1" "$2" "$3"; fi
}
check() { # desc expected actual
  if [[ "$2" == "$3" ]]; then pass=$((pass+1));
  else fail=$((fail+1)); printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$1" "$2" "$3"; fi
}

RDIR="$(mktemp -d)"
trap 'rm -rf "$RDIR"' EXIT
DLOG="$RDIR/docker.log"
OLOG="$RDIR/open.log"

# ===================================================================
# run-serena.sh
# ===================================================================
RUN="$SCRIPTS/run-serena.sh"

# --- fresh project (no .serena/project.yml): bootstraps then serves ---
PROJ="$RDIR/myproj"; mkdir -p "$PROJ"
: > "$DLOG"
env CLAUDE_PROJECT_DIR="$PROJ" DOCKER_STUB_LOG="$DLOG" bash "$RUN"
log="$(cat "$DLOG")"
contains "fresh: bootstraps project config"   "project create /workspaces/myproj" "$log"
contains "fresh: starts the mcp server"        "start-mcp-server"                  "$log"
contains "serve: names the container"          "--name serena-myproj"              "$log"
contains "serve: stdio transport"              "--transport stdio"                 "$log"
contains "serve: claude-code context"          "--context claude-code"             "$log"
contains "serve: project path is the workdir"  "--project /workspaces/myproj"      "$log"
contains "serve: publishes dashboard port"     "--publish 0:24282"                 "$log"
contains "serve: SERENA_DOCKER env flag"       "--env SERENA_DOCKER=1"             "$log"
contains "serve: mounts project at workdir"    "--volume $PROJ:/workspaces/myproj" "$log"
contains "serve: mounts named lsp cache"       "serena-lsp-cache-myproj"           "$log"
contains "serve: always pulls latest image"    "--pull always"                     "$log"
contains "serve: uses the oraios image"        "ghcr.io/oraios/serena:latest"      "$log"

# --- existing project config: skip the bootstrap step ---
PROJ2="$RDIR/hasconf"; mkdir -p "$PROJ2/.serena"
printf 'project_name: hasconf\n' > "$PROJ2/.serena/project.yml"
: > "$DLOG"
env CLAUDE_PROJECT_DIR="$PROJ2" DOCKER_STUB_LOG="$DLOG" bash "$RUN"
log="$(cat "$DLOG")"
not_contains "existing config: no re-bootstrap"  "project create" "$log"
contains     "existing config: still serves"     "start-mcp-server" "$log"

# --- no CLAUDE_PROJECT_DIR: fall back to the current directory basename ---
PROJ3="$RDIR/cwdproj"; mkdir -p "$PROJ3/.serena"
printf 'project_name: cwdproj\n' > "$PROJ3/.serena/project.yml"
: > "$DLOG"
( cd "$PROJ3" && env -u CLAUDE_PROJECT_DIR DOCKER_STUB_LOG="$DLOG" bash "$RUN" )
log="$(cat "$DLOG")"
contains "cwd fallback: container from cwd basename" "--name serena-cwdproj" "$log"
contains "cwd fallback: project path from cwd"        "--project /workspaces/cwdproj" "$log"

# ===================================================================
# open-dashboard.sh
# ===================================================================
OPEN="$SCRIPTS/open-dashboard.sh"

# --- running container, Linux: parse port and xdg-open the dashboard URL ---
: > "$DLOG"; : > "$OLOG"
out="$(env CLAUDE_PROJECT_DIR="$RDIR/myproj" STUB_DOCKER_PORT="0.0.0.0:49160" \
        STUB_UNAME=Linux DOCKER_STUB_LOG="$DLOG" OPEN_STUB_LOG="$OLOG" \
        bash "$OPEN" 2>&1)"; rc=$?
check    "linux: exits 0 on success"        "0" "$rc"
contains "linux: queries the right container" "port serena-myproj 24282" "$(cat "$DLOG")"
contains "linux: opens parsed port via xdg-open" \
         "xdg-open http://localhost:49160/dashboard/index.html" "$(cat "$OLOG")"
contains "linux: reports the port to the user" "port 49160" "$out"

# --- running container, macOS: same URL via `open` ---
: > "$OLOG"
env CLAUDE_PROJECT_DIR="$RDIR/myproj" STUB_DOCKER_PORT="0.0.0.0:49160" \
    STUB_UNAME=Darwin OPEN_STUB_LOG="$OLOG" bash "$OPEN" >/dev/null 2>&1
contains "macos: opens URL via open" \
         "open http://localhost:49160/dashboard/index.html" "$(cat "$OLOG")"

# --- no port mapping (container down): error out, open nothing ---
: > "$OLOG"
out="$(env CLAUDE_PROJECT_DIR="$RDIR/myproj" STUB_UNAME=Linux \
        OPEN_STUB_LOG="$OLOG" bash "$OPEN" 2>&1)"; rc=$?
check        "down: exits non-zero"     "1"          "$rc"
contains     "down: explains the failure" "is not running" "$out"
check        "down: opens nothing"      ""           "$(cat "$OLOG")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
