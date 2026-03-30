---
name: serena-warmup
description: Pre-warm Serena's LSP cache for the current project
allowed-tools: ["mcp__plugin_serena-mcp-docker_serena__list_dir", "mcp__plugin_serena-mcp-docker_serena__get_symbols_overview"]
---

1. Use `list_dir` on the project root (recursive, skip ignored files) to discover source files
2. Call `get_symbols_overview` on key source files (not directories) to trigger LSP indexing
3. Report what was cached
