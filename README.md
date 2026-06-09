# fma-llm

## Origins
- Original: https://github.com/wellingtonlee/ghidra-docker-mcp (32 tools, Ghidra 12.0.4)
- Current: https://github.com/bethington/ghidra-mcp (249 tools, Ghidra 12.1)
- MCP gateway: https://github.com/mcpjungle/MCPJungle

fma-llm brings AI-assisted binary analysis to your desktop. Chat with an LLM that can decompile functions, search strings, find cross-references, and more by calling MCP tools that run inside a headless Ghidra container.

## Architecture

```
LLM Endpoint ──▶ Open WebUI ──MCP Streamable HTTP──▶ ghidra-mcp-headless (combined container)
                                                      ├─ Python MCP bridge (MCP→REST gateway, port 8090)
                                                      └─ Ghidra 12.1 headless REST API (port 8089)
```

The Ghidra headless server and its MCP bridge run in a **single container** (`ghidra-mcp-headless`).
The container starts the Java REST API in the background, then the Python bridge in the
foreground — both run as separate processes inside the same container. Open WebUI connects
to the MCP bridge at port 8090, which translates MCP tool calls to Ghidra's REST API on
port 8089.

MCPJungle is currently disabled (commented out in docker-compose.yml). Open WebUI connects
directly to the MCP bridge. Add MCPJungle back when you need to aggregate multiple MCP servers.

## Prerequisites

- Docker and Docker Compose v2+
- An OpenAI-compatible LLM API key
- Optional: Ghidra desktop for GUI work (not required for MCP tool access)

## Quick Start

1. Clone the repo.
2. Copy `example.env` to `.env` and fill in your `BASE_URL` and `API_KEY`.
3. Run `docker compose up -d`. The first build of ghidra-mcp-headless can take several minutes.
4. Open http://localhost in your browser.
5. Pick the default model (`grok-4.3`) or a tool-capable model of your choice. All MCP tools are
   **auto-bound to the model** at startup — no manual configuration needed.
6. Place a binary file in `./binaries/` and use the `import_file` MCP tool with path `/binaries/your-binary` to load it into Ghidra for analysis.

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

## Auto-Config: MCP Tools Bound at Startup

Open WebUI auto-discovers and binds all MCP tools to the default model on every container
start. Here's how it works:

1. `TOOL_SERVER_CONNECTIONS` registers MCP servers with Open WebUI at the application level.
2. On startup, the container runs a bootstrap script that signs in via the admin API
   (`WEBUI_ADMIN_EMAIL`/`WEBUI_ADMIN_PASSWORD`), discovers all registered `server:mcp:*`
   tool IDs, and creates/updates a workspace model with every tool ID attached.
3. The model's `meta.toolIds` array is populated automatically — every new chat has full
   tool access without manual per-chat tool selection.

**Future-proof**: Adding a new MCP server to `TOOL_SERVER_CONNECTIONS` is automatically
picked up on the next restart. No script changes needed.

## Configuration Reference

| Variable                  | Purpose                              | Default / Example                        |
|---------------------------|--------------------------------------|------------------------------------------|
| BASE_URL                  | OpenAI-compatible LLM endpoint       | https://api.openai.com/v1                |
| API_KEY                   | Your LLM provider key                | sk-...                                   |
| WEBUI_ADMIN_EMAIL         | Admin email for bootstrap auth       | admin@fma-llm.local                      |
| WEBUI_ADMIN_PASSWORD      | Admin password for bootstrap auth    | changeme-admin-pw                        |
| DEFAULT_MODEL_PARAMS      | Default model params (native tool)   | {"function_calling":"native"}            |
| WEBUI_SECRET_KEY          | Stable secret for Open WebUI sessions| (generate with openssl)                  |
| GHIDRA_MCP_AUTH_TOKEN     | Auth token for headless Ghidra MCP   | changeme                                 |
| OWUI_PORT                 | Open WebUI host port                 | 80                                       |
| GHIDRA_MCP_HEADLESS_PORT  | Ghidra headless REST API host port   | 3334                                     |
| GHIDRA_MCP_BRIDGE_PORT    | Ghidra MCP bridge (Streamable HTTP)  | 3335                                     |

## Troubleshooting

- Check logs: `docker compose logs <service>`
- Rebuild ghidra: `docker compose build ghidra-mcp-headless`
- Reset everything: `docker compose down -v && docker compose up -d`
