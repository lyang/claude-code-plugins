#!/bin/bash

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_NAME=$(basename "$DIR")

exec docker run                                        \
  --rm                                                 \
  --interactive                                        \
  --name "serena-${PROJECT_NAME}"                      \
  --publish 0:24282                                    \
  --volume "${DIR}:/workspaces/${PROJECT_NAME}"         \
  --env    SERENA_DOCKER=1                             \
  ghcr.io/oraios/serena:latest                         \
    serena-mcp-server                                  \
      --transport stdio                                \
      --context   claude-code                          \
      --project   "/workspaces/${PROJECT_NAME}"
