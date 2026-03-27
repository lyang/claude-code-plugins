# serena-mcp-docker

Claude Code plugin that launches [Serena](https://github.com/oraios/serena) as an MCP server inside Docker, providing LSP-powered code intelligence.

## Prerequisites

- Docker installed and running

## Installation

```bash
claude plugin add /path/to/serena-mcp-docker
```

## Improvements over the [official Docker setup](https://github.com/oraios/serena/blob/main/DOCKER.md)

- **Zero config** — no `compose.yaml`, `serena_config.yml`, or `compose.override.yml` needed
- **Auto-mounts current project** — uses `CLAUDE_PROJECT_DIR` so there's no manual volume configuration
- **Auto-activates the project** — passes `--project` directly, skipping manual activation after startup
- **Always pulls latest image** — `--pull always` ensures you're running the newest Serena release
- **Persists LSP cache** — a named Docker volume (`serena-lsp-cache-<project>`) keeps downloaded language servers across container restarts
- **Dynamic port assignment** — `--publish 0:24282` lets the OS pick an available port, avoiding conflicts

## Commands

- `/serena-dashboard` — Opens the Serena web dashboard in your browser
