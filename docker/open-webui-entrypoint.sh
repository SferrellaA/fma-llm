#!/bin/bash
set -euo pipefail

# Start Open WebUI in the background (start.sh -> exec uvicorn)
echo "Starting Open WebUI..."
bash start.sh &
WEBUI_PID=$!

# Wait for health check
echo "Waiting for server to be ready..."
for i in $(seq 1 120); do
  if curl -sf http://localhost:${PORT:-8080}/health > /dev/null 2>&1; then
    echo "Server healthy after ${i}s"
    break
  fi
  sleep 2
done

# Wait for the MCP bridge on the Ghidra container to be ready
MCP_URL=http://ghidra-mcp-headless:8090/mcp
echo "Waiting for MCP bridge at ${MCP_URL}..."
for i in $(seq 1 60); do
  # Use "initialize" (not tools/list) -- MCP Streamable HTTP requires
  # a session to be established before tool methods can be called.
  if curl -sf "${MCP_URL}" -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"healthcheck","version":"1.0"}}}' > /dev/null 2>&1; then
    echo "MCP bridge ready after ${i}s"
    break
  fi
  sleep 2
done

# Bootstrap: sign in, discover MCP tools, bind to the default model
python3 /docker/open-webui-bootstrap.py

# Hand off to the server process
echo "Entering server loop..."
wait $WEBUI_PID
