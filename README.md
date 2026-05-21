# fma-llm

## Re-Write TODO
https://github.com/wellingtonlee/ghidra-docker-mcp
https://github.com/mcpjungle/MCPJungle
Uses dockerfiles and docker compose

fma-llm brings AI-assisted binary analysis to your desktop. Chat with an LLM that can decompile functions, search strings, find cross-references, and more by calling MCP tools that run inside a headless Ghidra container.

## Architecture

```
LLM Endpoint ──▶ Open WebUI ──MCP Streamable HTTP──▶ MCPJungle ──▶ ghidra-docker-mcp
                                                               ──▶ future MCP servers
```

## Prerequisites

- Docker and Docker Compose v2+
- An OpenAI-compatible LLM API key
- Optional: Ghidra desktop for GUI work (not required for MCP tool access)

## Quick Start

1. Clone the repo.
2. Copy `example.env` to `.env` and fill in your `BASE_URL` and `API_KEY`.
3. Run `docker compose up -d`. The first build of ghidra-mcp can take several minutes.
4. Run `./scripts/setup-mcpjungle.sh` to verify registration and create the default tool group.
5. Open http://localhost in your browser.
6. In Open WebUI, go to Admin Panel → Settings → External Tools → Add Connection:
   - Type: MCP Streamable HTTP
   - URL: `http://mcpjungle:8080/mcp`
   - Auth: None
7. Pick a tool-capable model in the chat UI.
8. Import a binary into the `./binaries` volume and start asking questions.

## Usage Examples

- "List all functions in the binary"
- "Decompile the main function"
- "Search for strings containing 'password'"
- "Show cross-references to this address"

## Adding Future MCP Servers

Add a new service to `docker-compose.yml`, expose its SSE endpoint, then run:

```bash
./scripts/setup-mcpjungle.sh register --name <name> --url <internal-url>
```

## Tool Curation with MCPJungle Groups

MCPJungle exposes every tool by default. Use Tool Groups to curate a focused set for your chats.

```bash
./scripts/setup-mcpjungle.sh group-add <tool-name>
./scripts/setup-mcpjungle.sh group-remove <tool-name>
```

ghidra-docker-mcp ships with 32 tools. See the full list in its [README](https://github.com/wellingtonlee/ghidra-docker-mcp).

## Configuration Reference

| Variable            | Purpose                              | Default / Example          |
|---------------------|--------------------------------------|----------------------------|
| BASE_URL            | OpenAI-compatible LLM endpoint       | https://api.openai.com/v1  |
| API_KEY             | Your LLM provider key                | sk-...                     |
| WEBUI_SECRET_KEY    | Stable secret for Open WebUI sessions| (generate with openssl)    |
| OWUI_PORT           | Open WebUI host port                 | 80                         |
| MCPJUNGLE_PORT      | MCPJungle host port                  | 8080                       |
| GHIDRA_MCP_PORT     | ghidra-mcp host port                 | 3333                       |

## Troubleshooting

- Check logs: `docker compose logs <service>`
- Rebuild ghidra-mcp: `docker compose build ghidra-mcp`
- Reset everything: `docker compose down -v && docker compose up -d`
