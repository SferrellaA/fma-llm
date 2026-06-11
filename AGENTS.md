# fma-llm — Agent Knowledge Base

## Project Overview

fma-llm is a Docker Compose stack for AI-assisted binary analysis. It wires together:

- **Open WebUI** — chat frontend where you talk to an LLM
- **ghidra-mcp-headless** — Ghidra 12.1 running headless with a REST API + Python MCP bridge (~233 tools, lazy-loaded to ~84)
- **open-terminal** — terminal MCP sidecar for running shell commands alongside Ghidra

The user drops a binary into a shared folder, and the LLM can decompile functions, search strings, find cross-references, etc. by calling MCP tools that run inside the headless Ghidra container.

---

## Architecture

```
LLM Endpoint ──▶ Open WebUI ──MCP Streamable HTTP──▶ ghidra-mcp-headless (combined container)
                                                      ├─ Java REST API (port 8089) — Ghidra 12.1 headless
                                                      └─ Python MCP bridge (port 8090) — 233 tools, lazy mode

open-terminal ──MCP Streamable HTTP──▶ Open WebUI (also registered in TOOL_SERVER_CONNECTIONS)
  └─ Shares same filesystem as ghidra-mcp-headless via SHARED_FOLDER
```

The Ghidra headless server and its MCP bridge run in a **single container**. The Java REST API starts in the background, then the Python bridge in the foreground. Open WebUI connects to the MCP bridge via Streamable HTTP. The bootstrap script auto-discovers and binds all MCP tools to the default model on every container start.

---

## Services

### `open-webui`

- **Image**: `ghcr.io/open-webui/open-webui:0.9.6`
- **Port**: 80 (host) → 8080 (container)
- **Auth**: Required. Admin credentials `demo@demo.demo` / `demo` used for bootstrap.
- **Key env vars**:
  - `OPENAI_API_BASE_URL` / `OPENAI_API_KEY` — LLM endpoint
  - `DEFAULT_MODELS` — which model to auto-bind tools to (default: `grok-4.3`)
  - `TOOL_SERVER_CONNECTIONS` — JSON array of MCP server registrations
  - `ENABLE_PERSISTENT_CONFIG=False` — force env vars over persisted DB config
  - `OFFLINE_MODE=True` — suppress backend network calls, "What's New" modal
  - `ENABLE_VERSION_UPDATE_CHECK=False`
  - `WEBUI_ADMIN_EMAIL` / `WEBUI_ADMIN_PASSWORD` — used by bootstrap
- **Bootstrap**: The `command:` override runs a multi-step startup script:
  1. Start Open WebUI in background
  2. Wait for health check
  3. Wait for ghidra-mcp-headless MCP bridge to be ready
  4. Sign in as admin, discover MCP tool servers
  5. Grant admin user read access to each tool
  6. Delete existing workspace model, create fresh with all tool IDs bound
- **Important quirks**:
  - `WEBUI_AUTH=False` does NOT disable API auth — only hides the login UI. The `/api/v1/tools/` endpoint still requires a JWT token. This caused bootstrap failures before the fix.
  - Built-in tools (automations, calendar, notes, code interpreter, memories) are disabled via env vars.
  - The "Welcome to version X" modal is controlled by `_app/version.json` hash comparison in browser localStorage. Pinned via `command:` override that writes a stable hash before server starts.
  - Model update endpoint (`POST /api/v1/models/model/update`) has a bug in v0.9.6 — `ModelForm(**form_data.model_dump())` double-wraps and returns 500. Workaround: delete-then-create instead of update.
  - Bootstrap's MCP health check must send `initialize` (not `tools/list`) — Streamable HTTP requires a session before tool methods.

### `ghidra-mcp-headless`

- **Build**: `docker/ghidra.Dockerfile` (multi-stage: builder → runtime)
- **Ports**: 8089 (REST API), 8090 (MCP bridge)
- **Upstream**: `bethington/ghidra-mcp` v5.13.1 — 249 tools upstream, ~233 reachable in this setup
- **Files**:
  - `docker/ghidra.Dockerfile` — Combined Ghidra + MCP bridge image
  - `docker/ghidra-entrypoint.sh` — Container startup script
- **Startup flow**:
  1. Build classpath from Ghidra JARs
  2. Start Java Ghidra headless server in background (PID tracked)
  3. Wait for `/check_connection` health check
  4. Start Python MCP bridge via a Python wrapper that monkey-patches the MCP library
- **Lazy mode**: `--lazy --default-groups listing,function,program,headless` — ~84 tools on startup
  - Remaining tools loaded at runtime via `load_tool_group()` MCP tool
  - Full list: listing (~21), function (~35), program (~25), headless, datatype (~38), analysis (~23), xref (~12), symbol (~12), documentation (~15), comment (~7), malware (~5), emulation (~3)
- **MCP Accept header patch**: Monkey-patches `StreamableHTTPServerTransport._check_accept_headers` to accept `Accept: */*` — Open WebUI's httpx sends `*/*` by default but MCP spec requires `application/json, text/event-stream`. Both must run in the same Python process.
- **Health check**: Container-level `HEALTHCHECK` pings `/check_connection` every 30s.
- **Volume mounts**:
  - `SHARED_FOLDER` → `/tmp` (read-write, shared with open-terminal)
  - `GHIDRA_PROJECTS_FOLDER` (defaults to `./shared/projects`) → `/projects`

### `open-terminal`

- **Image**: `ghcr.io/open-webui/open-terminal:latest`
- **Port**: 9000 (MCP Streamable HTTP)
- **Purpose**: Terminal MCP sidecar — run shell commands (`file`, `strings`, `objdump`, `xxd`, `gdb`) alongside Ghidra
- **Key env vars**:
  - `OPEN_TERMINAL_API_KEY=demo` — static, no auth setup per demo
  - `OPEN_TERMINAL_PIP_PACKAGES=fastmcp` — auto-installs MCP deps at startup
  - `OPEN_TERMINAL_PACKAGES=gdb` — auto-installs apt packages
- **Volume mounts**:
  - `SHARED_FOLDER` → `/home/user/shared`
  - `SHARED_FOLDER/projects` → `/home/user/projects`
- **Demo-only**: No persistent volume, ephemeral per `docker compose up`

---

## Key Technical Decisions

### Why combined ghidra-mcp-headless container (not separate)

The upstream ghidra-mcp project has two components: a Java REST API server and a Python MCP bridge. Originally they were separate containers. Merging them into one:
- Reduces container count
- Simplifies startup orchestration (bridge retries until Java is ready)
- Both in same process namespace for easier debugging

### Why lazy mode instead of a meta-tool proxy

The LLM's upstream API enforces a 200-tool limit. Several approaches were tried:

1. **MCPJungle** as gateway — added complexity, MCPJungle's tool grouping wasn't a clean fit
2. **AgentGateway** with `get_tool`/`invoke_tool` meta-tools — `toolMode: Search` is Enterprise-only (Kubernetes CRD), not in OSS
3. **Custom Python proxy** — built, merged into container, then abandoned when Accept header issues made the proxy-bridge communication brittle
4. **`--lazy` flag** (current) — simplest, uses upstream's built-in lazy loading. ~84 default tools, rest loadable on demand.

**Trade-off**: The model can only use the ~84 default tools directly. To use advanced tools (datatype, analysis, xref, etc.), it must first call `load_tool_group("name")`. This is documented in README.

### Why MCP Accept header patch is needed

Open WebUI's HTTP client (`httpx`) sends `Accept: */*` by default. The MCP Python library's Streamable HTTP transport strictly requires `application/json, text/event-stream` and returns 406 for anything else. The fix is a monkey-patch in `ghidra-entrypoint.sh` that wraps bridge startup:

```python
import mcp.server.streamable_http
orig = mcp.server.streamable_http.StreamableHTTPServerTransport._check_accept_headers
def _patched_check_accept(self, request):
    accept = request.headers.get('accept', '').strip()
    if accept in ('*/*', ''):
        return (True, True)
    return orig(self, request)
mcp.server.streamable_http.StreamableHTTPServerTransport._check_accept_headers = _patched_check_accept
import bridge_mcp_ghidra
bridge_mcp_ghidra.main()
```

Both the patch and bridge must run in the same Python process since it patches a module-level class method.

### Why delete-then-create for model binding

Open WebUI v0.9.6's `POST /api/v1/models/model/update` returns HTTP 500 when updating a model's `meta.toolIds`. The bug is in `ModelForm(**form_data.model_dump())` which double-wraps and fails on `access_grants=None`. The bootstrap works around it by:
1. `POST /api/v1/models/model/delete` — delete existing model (ignores 404 on first run)
2. `POST /api/v1/models/create` — create fresh model with all tool IDs

### Why admin sign-in is needed even for demo

`WEBUI_AUTH=False` (now removed) only hides the login UI — it does NOT disable API authentication. The `/api/v1/tools/` endpoint still requires a valid JWT token. The bootstrap must sign in to get a token before it can discover tools or bind them to a model.

### Why tool access grants are needed

Open WebUI's access control system silently skips tools the user doesn't have explicit read access to. When MCP tools are registered via `TOOL_SERVER_CONNECTIONS`, they get empty `access_grants: []`. The bootstrap must insert an `access_grant` row granting the admin user read access to each `server:mcp:*` tool.

---

## Common Issues & Resolutions

### Bootstrap fails silently

**Symptom**: Open WebUI starts but model has no tool bindings, or shows "create account" page.

**Checklist**:
1. `docker compose logs open-webui | grep -E 'Signed in|Discovered|Model created|Bootstrap complete'`
2. If "401 Unauthorized" on tool discovery → admin sign-in failed. Check credentials.
3. If "0 MCP tools discovered" → MCP bridge isn't reachable. Check ghidra-mcp-headless logs.
4. If "Model created" shows empty toolIds → timing race. Bootstrap ran before MCP tools registered.

### Container shows unhealthy

**Symptom**: `docker compose ps` shows `unhealthy` for ghidra-mcp-headless.

**Causes**:
- Container is still in its `start_period` (120s for Ghidra — Java startup + project loading)
- Bridge crashed. Check `docker compose logs ghidra-mcp-headless --tail=40`.
- Java OOM. Check `JAVA_OPTS` memory allocation.

### Tools not visible in chat

**Symptom**: Model says "I don't see any tools" or doesn't call them.

**Checklist**:
1. Is the model selected in the chat? Must be the workspace model (not base model).
2. Are tools bound? Check Admin Settings → Tools → the MCP server should have tools listed.
3. Does the user have access? Bootstrap must grant `access_grant` for admin user.
4. Is `function_calling` set to `native`? Check model params in DB.
5. Is tool toggle enabled in chat? Look for paperclip/puzzle icon.

### 406 Not Acceptable on MCP bridge

**Symptom**: `docker compose logs ghidra-mcp-headless` shows `HTTP/1.1 406 Not Acceptable`.

**Cause**: Client sent `Accept: */*` or `Accept: application/json` without `text/event-stream`.

**Fix**: The monkey-patch in `ghidra-entrypoint.sh` should handle this. If it persists, check that the patch is running (it's applied in the Python wrapper, not as a separate script).

### "Maximum tools limit reached" (200-tool limit)

**Symptom**: Chat completion fails with "215 tools provided but maximum is 200".

**Causes**:
- Lazy mode not active. Rebuild container: `docker compose build ghidra-mcp-headless`
- The bridge loaded all tools via `_auto_connect()` before lazy mode could apply.
- Verify: check logs for "Starting MCP bridge (foreground, lazy mode)"

---

## Volume Mount Strategy

```
Host: ./shared/           → ghidra-mcp-headless:/tmp
                            → open-terminal:/home/user/shared

Host: ./shared/projects/  → ghidra-mcp-headless:/projects
                            → open-terminal:/home/user/projects
```

- The Ghidra container sees shared folder at `/tmp` (consistent with upstream convention)
- Open-terminal sees it at `/home/user/shared` (working directory context)
- Projects live in a subdirectory of the shared folder, not a separate Docker volume
- No persistent volumes for open-terminal (ephemeral per `docker compose up`)

---

## Required Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| `BASE_URL` | LLM API endpoint | `https://api.openai.com/v1` |
| `API_KEY` | LLM API key | — |
| `DEFAULT_MODEL` | Model ID for tool binding | `grok-4.3` |
| `WEBUI_ADMIN_EMAIL` | Bootstrap admin login | `demo@demo.demo` |
| `WEBUI_ADMIN_PASSWORD` | Bootstrap admin password | `demo` |
| `GHIDRA_MCP_AUTH_TOKEN` | Bridge auth token | `changeme` |
| `SHARED_FOLDER` | Host path for shared files | `./shared` |
| `GHIDRA_PROJECTS_FOLDER` | Host path for Ghidra projects | `./shared/projects` |

---

## Git History (Recent)

```
dd51300 shifted what folders are mounted wehre a bit
3571ce6 adding open-terminal worked on first try!
77bc597 temp commit before adding a terminal
acca2da lifecyle tools now enabled by default
ab26cb4 ghidra tools configured correctly
4208497 disabled built-in tools and update/version modals
53788a8 conceding to needing an admin account, even for a demo
60bd8d7 removed junglemcp references; nto a gateway like I thought
e50e7df Combined the two ghidra containers
d512794 model and tools auto-enabled
7f4df31 Shifted to differnet ghidra mcp, autoconfigured openwebui connection
2e886c0 Removing legacy/slop
3820a48 EOD
4d1fd70 chore: remove obsolete version attribute from compose file
86a066e docs: rewrite README for Docker Compose setup
1dffdc3 feat: update example.env for Docker Compose setup
d5bd03a fix: tighten ghidra registration grep, improve group-create error handling
6418f61 feat: add scripts/setup-mcpjungle.sh for MCPJungle post-startup management
b1b65b1 fix: pin ghidra-mcp build to commit SHA, create binaries dir for bind mount
78cec08 feat: add docker-compose.yml for fma-llm rewrite
```

---

## Development Workflow

### Common commands

```bash
# Build and start everything
docker compose build ghidra-mcp-headless  # rebuild after entrypoint/Dockerfile changes
docker compose up -d

# Check status
docker compose ps
docker compose logs --tail=40 open-webui
docker compose logs --tail=40 ghidra-mcp-headless

# Force recreate (pick up docker-compose.yml changes)
docker compose up -d --force-recreate open-webui

# Full reset
docker compose down -v && docker compose up -d
```

### Debugging the bootstrap

The bootstrap Python script runs inside the `open-webui` container. To test it manually:

```bash
docker exec -it fma-llm-open-webui-1 python3 -c "
import json, os, urllib.request
BASE = 'http://localhost:8080'
# Test sign-in
req = urllib.request.Request(
    BASE + '/api/v1/auths/signin',
    data=json.dumps({'email': 'demo@demo.demo', 'password': 'demo'}).encode(),
    headers={'Content-Type': 'application/json'},
)
resp = json.loads(urllib.request.urlopen(req).read())
print('Token:', resp['token'][:20] + '...')
"
```

### Testing the MCP bridge directly

```bash
# Initialize session
curl -s http://localhost:3335/mcp -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

# List tools (use session ID from initialize response)
curl -s http://localhost:3335/mcp -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: <session_id>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

---

## File Reference

| File | Purpose |
|---|---|
| `docker-compose.yml` | Service definitions (open-webui, ghidra-mcp-headless, open-terminal) |
| `docker/ghidra.Dockerfile` | Multi-stage build: Ghidra 12.1 + MCP bridge |
| `docker/ghidra-entrypoint.sh` | Container startup: Java REST API → Python MCP bridge |
| `README.md` | User-facing documentation |
| `AGENTS.md` | This file — agent knowledge base |
| `.opencode/agents/fma-llm-transition.md` | Legacy agent definition from the shell→Docker rewrite phase |
| `example.env` | Environment variable template |
| `shared/` | Default shared folder for binary analysis |

---

## External References

- **ghidra-mcp**: https://github.com/bethington/ghidra-mcp (v5.13.1)
- **Open WebUI**: https://github.com/open-webui/open-webui (v0.9.6)
- **open-terminal**: https://github.com/open-webui/open-terminal
- **Ghidra**: https://github.com/NationalSecurityAgency/ghidra (v12.1)
- **MCP Streamable HTTP Spec**: https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/transports/
