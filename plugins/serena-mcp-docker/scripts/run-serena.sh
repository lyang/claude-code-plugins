#!/bin/bash

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_NAME=$(basename "$DIR")
CACHE_VOLUME="serena-lsp-cache-${PROJECT_NAME}"
LSP_CACHE_DIR="/workspaces/serena/config/language_servers/static"

IMAGE="ghcr.io/oraios/serena:latest"
WORKDIR="/workspaces/${PROJECT_NAME}"

DOCKER_ARGS=(
  --rm
  --interactive
  --pull always
  --publish 0:24282
  --volume "${DIR}:${WORKDIR}"
  --volume "${CACHE_VOLUME}:${LSP_CACHE_DIR}"
  --env SERENA_DOCKER=1
)

# Auto-create project config with language inference if missing
if [[ ! -f "${DIR}/.serena/project.yml" ]]; then
  docker run "${DOCKER_ARGS[@]}" "$IMAGE" \
    serena project create "$WORKDIR"
fi

exec docker run \
  --name "serena-${PROJECT_NAME}" \
  "${DOCKER_ARGS[@]}" \
  "$IMAGE" \
    serena \
      start-mcp-server \
      --transport stdio \
      --context claude-code \
      --project "$WORKDIR"
