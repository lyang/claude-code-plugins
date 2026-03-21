#!/bin/bash

PROJECT_NAME=$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")
CONTAINER="serena-${PROJECT_NAME}"
PORT=$(docker port "$CONTAINER" 24282 2>/dev/null | head -1 | cut -d: -f2)

if [[ -n "$PORT" ]]; then
  URL="http://localhost:${PORT}/dashboard/index.html"
  case "$(uname -s)" in
    Darwin)  open "$URL" ;;
    Linux)   xdg-open "$URL" ;;
    MINGW*|MSYS*|CYGWIN*) cmd.exe /c start "$URL" ;;
    *)       echo "Open manually: $URL"; exit 0 ;;
  esac
  echo "Opened Serena dashboard on port ${PORT}"
else
  echo "Error: Serena container '${CONTAINER}' is not running or dashboard port not found"
  exit 1
fi
