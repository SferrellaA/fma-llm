# fma-llm

## Origins
- Original: https://github.com/wellingtonlee/ghidra-docker-mcp (32 tools, Ghidra 12.0.4)
- Current: https://github.com/bethington/ghidra-mcp (249 tools, Ghidra 12.1)

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
6. Set `SHARED_FOLDER` in `.env` (defaults to `./shared`) — see [Shared Folder](#shared-folder) below.
7. Drop a binary into the shared folder, then in Open WebUI ask the model: *"Import `/shared/your-binary` and decompile main"*.

## Usage Examples

- "List all functions in the binary"
- "Decompile the main function"
- "Search for strings containing 'password'"
- "Show cross-references to this address"

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

## Tool Lazy Loading (200-Tool Limit)

The Ghidra MCP bridge exposes ~233 tools across 12+ categories, but some LLM
providers limit how many tools a model can receive. The bridge is configured in
**lazy mode** by default to stay within a 200-tool limit:

### How Lazy Mode Works

Lazy mode loads only the **3 default tool groups** on initial connection, giving
you ~81 immediately callable tools. The remaining tools stay dormant until
explicitly requested at runtime via MCP tool calls.

**Default groups always loaded:**

| Group | Tools | What You Get |
|---|---|---|
| **listing** | ~21 | List functions, strings, segments, imports, exports, classes |
| **function** | ~35 | Decompile, rename, prototype, variables, create/delete functions |
| **program** | ~25 | Metadata, save, scripts, memory read, bookmarks |

**Groups you can load on demand** (via `load_tool_group()`):

| Group | Tools | Runtime Command | Description |
|---|---|---|---|
| datatype | ~38 | `load_tool_group("datatype")` | Struct/enum/union CRUD, data types |
| analysis | ~23 | `load_tool_group("analysis")` | Completeness scoring, similarity, crypto, CFG |
| xref | ~12 | `load_tool_group("xref")` | Cross-references, call graphs |
| symbol | ~12 | `load_tool_group("symbol")` | Labels, globals, external locations |
| documentation | ~15 | `load_tool_group("documentation")` | Function hashing, cross-binary doc transfer |
| comment | ~7 | `load_tool_group("comment")` | Plate/decompiler/disassembly comments |
| malware | ~5 | `load_tool_group("malware")` | Anti-analysis detection, IOC extraction |
| emulation | ~3 | `load_tool_group("emulation")` | Function emulation |

### Runtime Usage

```python
# At any point during analysis, load additional tools:
load_tool_group("xref")       # Add cross-reference tools (+12)
load_tool_group("datatype")   # Add data type tools (+38)
load_tool_group("malware")    # Add malware analysis tools (+5)

# Check which tools are loaded:
list_tool_groups()

# Verify a specific tool is callable:
check_tools(tools="get_xrefs_to,decompile_function,list_functions")

# Unload a non-default group if you need to free up room:
unload_tool_group("datatype")

# Load everything at once (bypass the limit):
load_tool_group("all")
```

### Managing the Tool Count

- **~81 tools**: Default lazy mode (listing + function + program)
- **~140 tools**: Defaults + xref + symbol + comment + malware + emulation + documentation
- **~200 tools**: Defaults + xref + symbol + comment + malware + emulation + documentation + analysis + datatype
- **~233 tools**: `load_tool_group("all")` — everything

### Disabling Lazy Mode

If your LLM provider supports 200+ tools or you're running a local model with no
limit, edit `docker/entrypoint.sh` and remove the `--lazy` and `--default-groups`
flags from the bridge command to load all tools on startup.

## Configuration Reference

| Variable                  | Purpose                              | Default / Example                        |
|---------------------------|--------------------------------------|------------------------------------------|
| BASE_URL                  | OpenAI-compatible LLM endpoint       | https://api.openai.com/v1                |
| API_KEY                   | Your LLM provider key                | sk-...                                   |
| WEBUI_ADMIN_EMAIL         | Admin email for bootstrap auth       | demo@demo.demo                           |
| WEBUI_ADMIN_PASSWORD      | Admin password for bootstrap auth    | demo                                    |
| DEFAULT_MODEL_PARAMS      | Default model params (native tool)   | {"function_calling":"native"}            |
| WEBUI_SECRET_KEY          | Stable secret for Open WebUI sessions| (generate with openssl)                  |
| GHIDRA_MCP_AUTH_TOKEN     | Auth token for headless Ghidra MCP   | changeme                                 |
| SHARED_FOLDER             | Host path mounted at /shared (rw) in the Ghidra container — drop binaries here for the model to analyze, or host existing Ghidra projects | ./shared                                 |
| OWUI_PORT                 | Open WebUI host port                 | 80                                       |
| GHIDRA_MCP_HEADLESS_PORT  | Ghidra headless REST API host port   | 3334                                     |
| GHIDRA_MCP_BRIDGE_PORT    | Ghidra MCP bridge (Streamable HTTP)  | 3335                                     |

## Shared Folder

The optional `SHARED_FOLDER` environment variable mounts a host directory into the Ghidra
container at `/shared` (read-write). This gives the model a workspace to:

1. **Analyze new binaries** — Drop a binary into the shared folder on your host, then tell the model:
   > "Import the binary at `/shared/my-binary.exe` and decompile its main function"
   The model calls `import_file` pointing into `/shared`.

2. **Create Ghidra projects** — Tell the model to create a new project inside the shared folder:
   > "Create a new Ghidra project at `/shared/my-analysis` and import `/shared/my-binary.exe`"

3. **Work with existing Ghidra projects** — Point the model at an existing `.gpr` project:
   > "Open the project at `/shared/existing-project/existing-project.gpr` and list all functions"

**Example workflow:**

```bash
# 1. Set SHARED_FOLDER=./shared in your .env
# 2. Drop a binary into ./shared/
# 3. Restart: docker compose up -d
# 4. In Open WebUI, ask the model:
#    "Import /shared/my-binary.exe, create a project at /shared/analysis-project, decompile main"
```

> **Note:** The shared folder is mounted read-write (`:rw`) — Ghidra can write project files
> there and the model can reference files at `/shared/...`.

## Troubleshooting

- Check logs: `docker compose logs <service>`
- Rebuild ghidra: `docker compose build ghidra-mcp-headless`
- Reset everything: `docker compose down -v && docker compose up -d`
