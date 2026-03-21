# serena-mcp-docker

Claude Code plugin that launches [Serena](https://github.com/oraios/serena) as an MCP server inside Docker, providing LSP-powered code intelligence.

## Prerequisites

- Docker installed and running

## Installation

```bash
claude plugin add /path/to/serena-mcp-docker
```

## How it works

When enabled, the plugin registers a `serena` MCP server that:

1. Mounts your project directory into a Docker container
2. Runs `serena-mcp-server` with stdio transport using the `ghcr.io/oraios/serena:latest` image
3. Exposes the Serena dashboard on a dynamically assigned port

Serena then provides code intelligence tools (go-to-definition, find references, diagnostics, etc.) via the Model Context Protocol.

## Commands

- `/serena-dashboard` — Opens the Serena web dashboard in your browser
