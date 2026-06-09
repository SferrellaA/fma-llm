# fma-llm

## Origins
- Original: https://github.com/wellingtonlee/ghidra-docker-mcp (32 tools, Ghidra 12.0.4)
- Current: https://github.com/bethington/ghidra-mcp (249 tools, Ghidra 12.1)
- MCP gateway: https://github.com/mcpjungle/MCPJungle

fma-llm brings AI-assisted binary analysis to your desktop. Chat with an LLM that can decompile functions, search strings, find cross-references, and more by calling MCP tools that run inside a headless Ghidra container.

## Architecture

```
LLM Endpoint ──▶ Open WebUI ──MCP Streamable HTTP──▶ ghidra-mcp-bridge (MCP→REST gateway)
                                                     ──▶ ghidra-mcp-headless (Ghidra 12.1 REST API)
```

MCPJungle is currently disabled (commented out in docker-compose.yml). Open WebUI connects directly to the ghidra-mcp bridge. Add MCPJungle back when you need to aggregate multiple MCP servers.

## Prerequisites

- Docker and Docker Compose v2+
- An OpenAI-compatible LLM API key
- Optional: Ghidra desktop for GUI work (not required for MCP tool access)

## Quick Start

1. Clone the repo.
2. Copy `example.env` to `.env` and fill in your `BASE_URL` and `API_KEY`.
3. Run `docker compose up -d`. The first build of ghidra-mcp-headless can take several minutes.
4. Open http://localhost in your browser.
5. In Open WebUI, go to Admin Panel → Settings → External Tools → Add Connection:
   - Type: MCP Streamable HTTP
   - URL: `http://ghidra-mcp-bridge:8090/mcp`
   - Auth: None
6. Pick a tool-capable model in the chat UI.
7. Place a binary file in `./binaries/` and use the `import_file` MCP tool with path `/binaries/your-binary` to load it into Ghidra for analysis.

## Usage Examples

- "List all functions in the binary"
- "Decompile the main function"
- "Search for strings containing 'password'"
- "Show cross-references to this address"

## Adding Future MCP Servers (with MCPJungle)

MCPJungle is currently disabled. When you're ready to aggregate multiple MCP servers, uncomment the `mcpjungle` and `mcp-setup` services in docker-compose.yml, then:

```bash
./scripts/setup-mcpjungle.sh register --name <name> --url <internal-url>
```

## Tool Curation with MCPJungle Groups (with MCPJungle)

When MCPJungle is enabled, it exposes every tool by default. Use Tool Groups to curate a focused set for your chats.

```bash
./scripts/setup-mcpjungle.sh group-add <tool-name>
./scripts/setup-mcpjungle.sh group-remove <tool-name>
```

ghidra-mcp ships with 249 tools. See the full list in its [README](https://github.com/bethington/ghidra-mcp).

## Configuration Reference

| Variable                  | Purpose                              | Default / Example          |
|---------------------------|--------------------------------------|----------------------------|
| BASE_URL                  | OpenAI-compatible LLM endpoint       | https://api.openai.com/v1  |
| API_KEY                   | Your LLM provider key                | sk-...                     |
| WEBUI_SECRET_KEY          | Stable secret for Open WebUI sessions| (generate with openssl)    |
| GHIDRA_MCP_AUTH_TOKEN     | Auth token for headless Ghidra MCP   | changeme                   |
| OWUI_PORT                 | Open WebUI host port                 | 80                         |
| GHIDRA_MCP_HEADLESS_PORT  | Ghidra headless REST API host port   | 3334                       |
| GHIDRA_MCP_BRIDGE_PORT    | Ghidra MCP bridge (Streamable HTTP)  | 3335                       |

## Troubleshooting

- Check logs: `docker compose logs <service>`
- Rebuild ghidra: `docker compose build ghidra-mcp-headless`
- Reset everything: `docker compose down -v && docker compose up -d`
