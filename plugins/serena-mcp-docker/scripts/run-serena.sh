#!/bin/bash

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_NAME=$(basename "$DIR")
CACHE_VOLUME="serena-lsp-cache-${PROJECT_NAME}"
LSP_CACHE_DIR="/workspaces/serena/config/language_servers/static"

exec docker run \
  --pull always \
  --rm \
  --interactive \
  --name "serena-${PROJECT_NAME}" \
  --publish 0:24282 \
  --volume "${DIR}:/workspaces/${PROJECT_NAME}" \
  --volume "${CACHE_VOLUME}:${LSP_CACHE_DIR}" \
  --env SERENA_DOCKER=1 \
  ghcr.io/oraios/serena:latest \
    serena-mcp-server \
      --transport stdio \
      --context claude-code \
      --project "/workspaces/${PROJECT_NAME}"
