# fma-llm Docker Compose Rewrite

## Goal

Rewrite fma-llm from a shell-script-based setup to a fully Docker Compose-based architecture. The project enables AI-assisted binary analysis by connecting Open WebUI to Ghidra via the MCP protocol, with a local LLM endpoint.

## Architecture

```
LLM Endpoint ──HTTP──▶ Open WebUI ──MCP Streamable HTTP──▶ MCPJungle ──▶ ghidra-docker-mcp
  (external)           (Docker)                             (Docker)     ──▶ future MCP servers
```

All components run in Docker containers, started with a single `docker compose up`.

## Components

### 1. Open WebUI
- Container: `ghcr.io/open-webui/open-webui:main`
- Purpose: Chat UI — user interacts with the LLM here, which calls MCP tools
- Config: Auth disabled, external LLM endpoint as OpenAI provider
- Connects to MCPJungle via native **MCP Streamable HTTP** (`type: "mcp"` in external tools config)
- Volume: `open-webui:/app/backend/data`

### 2. MCPJungle (Gateway)
- Container: `ghcr.io/mcpjungle/mcpjungle:latest-stdio`
- Purpose: Central MCP gateway — registers ghidra-docker-mcp (and future servers), exposes curated tool subsets via Tool Groups
- Exposes Streamable HTTP endpoint at `:8080/mcp`
- Uses Tool Groups to expose only desired ghidra-docker-mcp tools (not all 32)
- Volume: persistent config/db

### 3. ghidra-docker-mcp
- Container: Built from wellingtonlee/ghidra-docker-mcp
- Purpose: Headless Ghidra with MCP tools (decompile, search, cross-refs, emulation, etc.)
- Registers with MCPJungle as an upstream MCP server
- Volume mounts for binary input and project data

### 4. Future MCP Servers (placeholder)
- Additional services register with MCPJungle
- Tool Groups can be expanded or new groups created

## Key Decisions

- **MCPJungle Tool Groups** over per-tool disable — cleaner, groups can be named and scoped
- **Native MCP Streamable HTTP** from Open WebUI — no mcpo proxy needed (supported since OWUI v0.6.31)
- **ghidra-docker-mcp sourced as-is** — reference its existing Dockerfile; only customize if needed
- **LLM endpoint remains external** — BYO API key, configured via env vars
- **Auth disabled** on Open WebUI for simplicity (`WEBUI_AUTH=False`)

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | All services |
| `.env` | Secrets (API key, endpoint URL) |
| `example.env` | Template for `.env` |
| `README.md` | Updated docs |

## Constraints

- Single `docker compose up` to start everything
- No Ghidra desktop install required
- Future MCP servers can be added without changing the gateway config
