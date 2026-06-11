# fma-llm

fma-llm brings AI-assisted binary analysis to your desktop. Chat with an LLM that can decompile functions, search strings, find cross-references, and run shell commands — all through MCP tools running inside a headless Ghidra container.

Built on [bethington/ghidra-mcp](https://github.com/bethington/ghidra-mcp) (v5.13.1, Ghidra 12.1).

## Architecture

Three services make up the stack. An LLM endpoint feeds into **Open WebUI** (port 80), which connects over MCP Streamable HTTP to two tool servers. The first is **ghidra-mcp-headless**, a combined container that runs Ghidra 12.1's headless REST API (port 8089) and a Python MCP bridge (port 8090) translating ~233 Ghidra tools into MCP calls. The Java REST API starts in the background, then the Python bridge launches in the foreground. The second is **open-terminal**, a terminal MCP sidecar (port 9000) for running shell commands — `file`, `strings`, `objdump`, `xxd`, `gdb` — alongside Ghidra analysis. Both tool servers share the same `SHARED_FOLDER` on disk, so the LLM can import a binary into Ghidra and inspect it with shell commands in the same conversation.

## Prerequisites

- Docker and Docker Compose v2+
- An OpenAI-compatible LLM API key
- Optional: Ghidra desktop for GUI work (not required for MCP tool access)

## Quick Start

1. Clone the repo.
2. Copy `example.env` to `.env` and fill in your `BASE_URL` and `API_KEY`.
3. Run `docker compose up -d`. The first build of ghidra-mcp-headless can take several minutes.
4. Open http://localhost in your browser.
5. Sign in with `demo@demo.demo` / `demo`.
6. Pick the default model (`grok-4.3`) or a tool-capable model of your choice. All MCP tools are **auto-bound to the model** at startup — no manual configuration needed.
7. Set `SHARED_FOLDER` in `.env` (defaults to `./shared`) — see [Shared Folder](#shared-folder) below.
8. Drop a binary into the shared folder, then ask the model: *"Import `/tmp/your-binary` and decompile main"*.

## Usage Examples

- "Import `/tmp/my-binary.exe` and decompile main"
- "List all functions in the binary"
- "Search for strings containing `password`"
- "Show cross-references to this address"
- "Run `file /home/user/shared/my-binary.exe`" (via open-terminal)

## Auto-Config: MCP Tools Bound at Startup

Open WebUI auto-discovers and binds all MCP tools to the default model on every container start:

1. `TOOL_SERVER_CONNECTIONS` registers both MCP servers (ghidra-mcp-headless, open-terminal) with Open WebUI.
2. On startup, the container runs a bootstrap script that signs in as admin, discovers all registered `server:mcp:*` tool IDs, and grants the admin user read access to each.
3. It then deletes any existing workspace model and creates a fresh one with all tool IDs attached and `function_calling: native` enabled.
4. Every new chat has full tool access without manual per-chat tool selection.

## Tool Lazy Loading (200-Tool Limit)

The Ghidra MCP bridge exposes ~233 tools across 12+ categories, but some LLM providers limit how many tools a model can receive. The bridge is configured in **lazy mode** by default to stay within a 200-tool limit.

### How Lazy Mode Works

Lazy mode loads only the **4 default tool groups** on initial connection, giving you ~84 immediately callable tools. The remaining tools stay dormant until explicitly requested at runtime.

**Default groups always loaded:**

| Group | Tools | What You Get |
|---|---|---|
| **listing** | ~21 | List functions, strings, segments, imports, exports, classes |
| **function** | ~35 | Decompile, rename, prototype, variables, create/delete functions |
| **program** | ~25 | Metadata, save, scripts, memory read, bookmarks |
| **headless** | ~3 | Import file, create project, open project |

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

- **~84 tools**: Default lazy mode (listing + function + program + headless)
- **~140 tools**: Defaults + xref + symbol + comment + malware + emulation + documentation
- **~200 tools**: Defaults + xref + symbol + comment + malware + emulation + documentation + analysis + datatype
- **~233 tools**: `load_tool_group("all")` — everything

### Disabling Lazy Mode

If your LLM provider supports 200+ tools or you're running a local model with no limit, edit `docker/ghidra-entrypoint.sh` and remove the `--lazy` and `--default-groups` flags from the bridge command to load all tools on startup.

## open-terminal Sidecar

The stack includes [open-terminal](https://github.com/open-webui/open-terminal) as a terminal MCP sidecar. It provides shell access alongside Ghidra analysis:

- Run `file`, `strings`, `objdump`, `xxd`, `gdb` on binaries
- Execute build scripts or extract data from analysis results
- Shares the same `SHARED_FOLDER` — files are visible at `/home/user/shared/`

The terminal MCP tools are auto-discovered and bound to the model alongside Ghidra's tools on every startup.

## Configuration Reference

| Variable | Purpose | Default / Example |
|---|---|---|
| `BASE_URL` | OpenAI-compatible LLM endpoint | `https://api.openai.com/v1` |
| `API_KEY` | Your LLM provider key | `sk-...` |
| `DEFAULT_MODEL` | Model ID for tool binding | `grok-4.3` |
| `WEBUI_ADMIN_EMAIL` | Admin email for bootstrap auth | `demo@demo.demo` |
| `WEBUI_ADMIN_PASSWORD` | Admin password for bootstrap auth | `demo` |
| `DEFAULT_MODEL_PARAMS` | Default model params (native tool) | `{"function_calling":"native"}` |
| `GHIDRA_MCP_AUTH_TOKEN` | Auth token for headless Ghidra MCP | `changeme` |
| `SHARED_FOLDER` | Host path mounted into Ghidra (`/tmp`) and open-terminal (`/home/user/shared`) | `./shared` |
| `GHIDRA_PROJECTS_FOLDER` | Host path for Ghidra projects at `/projects` | `./shared/projects` |
| `OWUI_PORT` | Open WebUI host port | `80` |
| `GHIDRA_MCP_HEADLESS_PORT` | Ghidra headless REST API host port | `3334` |
| `GHIDRA_MCP_BRIDGE_PORT` | Ghidra MCP bridge (Streamable HTTP) host port | `3335` |
| `OPEN_TERMINAL_MCP_PORT` | open-terminal MCP host port | `9000` |

## Shared Folder

The `SHARED_FOLDER` environment variable (defaults to `./shared`) mounts a host directory into both containers. This gives the model a shared workspace:

### Inside the Ghidra container (`/tmp`)

1. **Analyze new binaries** — Drop a binary into the shared folder on your host, then tell the model:
   > "Import the binary at `/tmp/my-binary.exe` and decompile its main function"

2. **Create Ghidra projects** — Tell the model to create a new project:
   > "Create a new Ghidra project at `/projects/my-analysis` and import `/tmp/my-binary.exe`"

3. **Work with existing Ghidra projects** — Point the model at an existing `.gpr` project:
   > "Open the project at `/projects/existing-project/existing-project.gpr` and list all functions"

### Inside the open-terminal container (`/home/user/shared`)

1. **Inspect binaries** — Run shell commands against files in the shared folder:
   > "Run `file /home/user/shared/my-binary.exe`"

2. **Debug with GDB** — GDB is pre-installed:
   > "Run `gdb -batch -ex 'info functions' /home/user/shared/my-binary.exe`"

3. **Cross-reference with Ghidra results** — Use Ghidra's analysis output from the terminal.

**Example workflow:**

```bash
# 1. Set SHARED_FOLDER=./shared in your .env
# 2. Drop a binary into ./shared/
# 3. Restart: docker compose up -d
# 4. In Open WebUI, ask the model:
#    "Import /tmp/my-binary.exe into Ghidra, decompile main,
#     then run 'strings /home/user/shared/my-binary.exe' to find plaintext secrets"
```

> **Note:** Both containers share the same host directory. Files created by one are immediately visible to the other.

## Troubleshooting

- **Check logs**: `docker compose logs <service>`
- **Rebuild ghidra**: `docker compose build ghidra-mcp-headless`
- **Tools not visible in chat?** Make sure you've selected the workspace model (not the base model) and the tool toggle is enabled in the chat input.
- **Admin login page instead of chat?** The first startup creates the admin account. Sign in with `demo@demo.demo` / `demo`.
- **Reset everything**: `docker compose down -v && docker compose up -d`
