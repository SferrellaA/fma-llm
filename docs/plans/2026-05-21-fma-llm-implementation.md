# fma-llm Docker Compose Rewrite — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite fma-llm from shell-script-based setup to all-Docker Compose architecture with Open WebUI, MCPJungle gateway, and ghidra-docker-mcp.

**Architecture:** Open WebUI connects to MCPJungle via native MCP Streamable HTTP. MCPJungle registers ghidra-docker-mcp (SSE transport) as an upstream server, with a Tool Group curating which tools are exposed. Future MCP servers can be added as additional services that register with MCPJungle. All started with `docker compose up`.

**Tech Stack:** Docker Compose, Open WebUI, MCPJungle, ghidra-docker-mcp (Python/FastMCP), Ghidra (headless Java)

---

### Task 1: Create docker-compose.yml

**Files:**
- Create: `docker-compose.yml`

**Step 1: Write docker-compose.yml**

Create the main compose file with four services:
- `open-webui` — Chat UI, connects to MCPJungle as MCP tool server
- `mcpjungle` — MCP gateway, exposes Streamable HTTP on port 8080
- `ghidra-mcp` — Headless Ghidra with MCP tools (SSE transport)
- `mcp-setup` — One-shot init container that registers ghidra-mcp with MCPJungle and creates a Tool Group

```yaml
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    ports:
      - "80:8080"
    environment:
      - OPENAI_API_BASE_URL=${BASE_URL}
      - OPENAI_API_KEY=${API_KEY}
      - WEBUI_AUTH=False
      - ENABLE_OLLAMA_API=False
      - ENABLE_OPENAI_API=True
      - BYPASS_MODEL_ACCESS_CONTROL=True
      - ENABLE_DIRECT_CONNECTIONS=True
    volumes:
      - open-webui-data:/app/backend/data
    restart: unless-stopped
    depends_on:
      mcp-setup:
        condition: service_completed_successfully

  mcpjungle:
    image: ghcr.io/mcpjungle/mcpjungle:latest-stdio
    ports:
      - "8080:8080"
    volumes:
      - mcpjungle-data:/data
    environment:
      - SQLITE_DB_PATH=/data/mcpjungle.db
    healthcheck:
      test: ["CMD", "/mcpjungle", "health"]
      interval: 5s
      timeout: 3s
      retries: 10
    restart: unless-stopped

  ghidra-mcp:
    build:
      context: ./ghidra-mcp
      dockerfile: Dockerfile
    ports:
      - "3333:8080"
    volumes:
      - ./binaries:/home/ghidra/binaries:ro
      - ghidra-projects:/home/ghidra/projects
    environment:
      - GHIDRA_ANALYSIS_TIMEOUT_SECONDS=300
      - GHIDRA_MAX_HEAP=2g
    command: ["--transport", "sse"]
    restart: unless-stopped

  mcp-setup:
    image: ghcr.io/mcpjungle/mcpjungle:latest-stdio
    depends_on:
      mcpjungle:
        condition: service_healthy
      ghidra-mcp:
        condition: service_started
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        echo "Waiting for ghidra-mcp SSE endpoint..."
        until wget -q --spider http://ghidra-mcp:8080; do sleep 1; done
        echo "Registering ghidra-mcp with MCPJungle..."
        /mcpjungle register --name ghidra --url http://ghidra-mcp:8080
        echo "Creating Tool Group 'ghidra-tools'..."
        /mcpjungle group create --name ghidra-tools --description "Curated Ghidra analysis tools"
        echo "Setup complete."

volumes:
  open-webui-data:
  mcpjungle-data:
  ghidra-projects:
```

**Details:**

Key env vars to document:
- `BASE_URL` — LLM endpoint URL (e.g., `https://api.openai.com/v1`)
- `API_KEY` — LLM API key
- Both loaded from `.env` file

The mcp-setup container:
- Waits for MCPJungle health check to pass
- Waits for ghidra-mcp SSE endpoint to be reachable
- Registers ghidra-mcp as an upstream MCP server in MCPJungle
- Creates a Tool Group (user can add specific tools to it later via MCPJungle CLI)

**Network:** All services communicate over the default compose network. Internal hostnames match service names.

**Step 2: Verify file exists**

Run: `ls -la docker-compose.yml`
Expected: File exists, valid YAML

---

### Task 2: Create MCPJungle setup script

**Files:**
- Create: `scripts/setup-mcpjungle.sh`

**Step 1: Write setup script**

```bash
#!/bin/bash
# Registers MCP servers with MCPJungle and configures Tool Groups.
# Run after `docker compose up -d`

set -e

echo "Waiting for MCPJungle..."
until docker compose exec mcpjungle /mcpjungle health 2>/dev/null; do
  sleep 1
done

echo "Registering ghidra-mcp..."
docker compose exec mcpjungle /mcpjungle register \
  --name ghidra \
  --description "Ghidra binary analysis MCP server" \
  --url http://ghidra-mcp:8080

echo "Creating tool group 're-tools' for reverse engineering..."
docker compose exec mcpjungle /mcpjungle group create \
  --name re-tools \
  --description "Reverse engineering tools (curated subset)"

echo "Done. ghidra-mcp registered and 're-tools' group created."
```

**Step 2: Make executable**

Run: `chmod +x scripts/setup-mcpjungle.sh`

---

### Task 3: Update example.env

**Files:**
- Modify: `example.env`

**Step 1: Write new example.env**

```env
# LLM endpoint
BASE_URL=https://api.openai.com/v1
API_KEY=sk-your-key-here

# Open WebUI
WEBUI_SECRET_KEY=change-me-to-random-string

# Ports (optional overrides)
OWUI_PORT=80
MCPJUNGLE_PORT=8080
GHIDRA_MCP_PORT=3333
```

---

### Task 4: Update .gitignore (done)

Already completed — covers ghidra-projects/, mcpjungle.db, volumes/, data/, __pycache__/, *.log, .DS_Store.

---

### Task 5: Rewrite README.md

**Files:**
- Modify: `README.md`

**Step 1: Write new README**

Replace the current README with Docker Compose instructions:

```markdown
# fma-llm

AI-assisted binary analysis. Chat with Ghidra through natural language.

Open WebUI → MCPJungle (gateway) → ghidra-docker-mcp + future MCP servers

## Prerequisites

- Docker & Docker Compose
- An OpenAI-compatible LLM API key

## Quick Start

1. Clone and enter the repo
2. Copy `example.env` to `.env` and fill in your API key and endpoint
3. Start everything:
   `docker compose up -d`
4. Register MCP servers with MCPJungle:
   `./scripts/setup-mcpjungle.sh`
5. Open http://localhost
6. In Open WebUI: Admin Panel → Settings → External Tools → Add Connection
   - Type: MCP Streamable HTTP
   - URL: http://mcpjungle:8080/mcp
   - Auth: None
7. Select a tool-capable model in the chat UI
8. Start analyzing — ask it to decompile functions, search strings, find cross-references
```

Include full step-by-step with screenshots reference.

---

### Task 6: Verification

**Step 1: Lint check**

Run: `docker compose config`
Expected: Valid compose file, no errors

**Step 2: Build check**

Run: `docker compose build`
Expected: All images build/pull successfully

**Step 3: LSP diagnostics**

Run diagnostics on all changed files.
Expected: Clean diagnostics
