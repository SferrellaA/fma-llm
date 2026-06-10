#!/bin/bash
# Combined entrypoint for Ghidra headless server + MCP bridge.
# Starts the Ghidra REST API (Java) in the background, then the Python
# MCP↔HTTP bridge in the foreground so the container stays alive.

set -e

# ---- Configuration from environment variables ----
PORT=${GHIDRA_MCP_PORT:-8089}
BIND_ADDRESS=${GHIDRA_MCP_BIND_ADDRESS:-"0.0.0.0"}
JAVA_OPTS=${JAVA_OPTS:-"-Xmx4g -XX:+UseG1GC"}
GHIDRA_USER=${GHIDRA_USER:-""}

# Shared Ghidra server configuration
GHIDRA_SERVER_HOST=${GHIDRA_SERVER_HOST:-""}
GHIDRA_SERVER_PORT=${GHIDRA_SERVER_PORT:-""}
GHIDRA_SERVER_USER=${GHIDRA_SERVER_USER:-""}

# ---- Colors for output ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  GhidraMCP Headless + MCP Bridge${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Bind Address: ${BIND_ADDRESS}"
echo "  REST API Port: ${PORT}"
echo "  MCP Bridge Port: 8090"
echo "  Meta Proxy Port: 8091"
echo "  Java Options: ${JAVA_OPTS}"
echo "  Ghidra Home: ${GHIDRA_HOME}"
[ -n "${GHIDRA_USER}" ] && echo "  Ghidra User: ${GHIDRA_USER}"
[ -n "${GHIDRA_SERVER_HOST}" ] && echo "  Server Host: ${GHIDRA_SERVER_HOST}"
[ -n "${GHIDRA_SERVER_PORT}" ] && echo "  Server Port: ${GHIDRA_SERVER_PORT}"
[ -n "${GHIDRA_SERVER_USER}" ] && echo "  Server User: ${GHIDRA_SERVER_USER}"
echo ""

# ---- Verify Ghidra installation ----
if [ ! -d "${GHIDRA_HOME}" ]; then
    echo -e "${RED}Error: Ghidra not found at ${GHIDRA_HOME}${NC}"
    exit 1
fi

# ---- Build classpath ----
CLASSPATH="/app/GhidraMCP.jar"

for jar in ${GHIDRA_HOME}/Ghidra/Framework/*/lib/*.jar; do
    CLASSPATH="${CLASSPATH}:${jar}"
done

for jar in ${GHIDRA_HOME}/Ghidra/Features/*/lib/*.jar; do
    CLASSPATH="${CLASSPATH}:${jar}"
done

for jar in ${GHIDRA_HOME}/Ghidra/Processors/*/lib/*.jar; do
    CLASSPATH="${CLASSPATH}:${jar}"
done

if [ -d "/app/lib" ]; then
    for jar in /app/lib/*.jar; do
        [ -f "$jar" ] && CLASSPATH="${CLASSPATH}:${jar}"
    done
fi

# ---- Signal handling ----
GHIDRA_PID=""
BRIDGE_PID=""
PROXY_PID=""

cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down...${NC}"

    # Stop proxy first (no new connections)
    if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
        echo "Stopping meta-tool proxy (PID $PROXY_PID)..."
        kill "$PROXY_PID" 2>/dev/null || true
        wait "$PROXY_PID" 2>/dev/null || true
    fi

    # Stop bridge second (handles in-flight MCP requests)
    if [ -n "$BRIDGE_PID" ] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
        echo "Stopping MCP bridge (PID $BRIDGE_PID)..."
        kill "$BRIDGE_PID" 2>/dev/null || true
        wait "$BRIDGE_PID" 2>/dev/null || true
    fi

    # Then stop Ghidra server
    if [ -n "$GHIDRA_PID" ] && kill -0 "$GHIDRA_PID" 2>/dev/null; then
        echo "Stopping Ghidra server (PID $GHIDRA_PID)..."
        kill "$GHIDRA_PID" 2>/dev/null || true
        wait "$GHIDRA_PID" 2>/dev/null || true
    fi

    echo -e "${GREEN}Shutdown complete.${NC}"
    exit 0
}

trap cleanup SIGTERM SIGINT

# ---- Start Ghidra headless server ----
BUILD_ARGS="--port ${PORT} --bind ${BIND_ADDRESS}"

# Append any passed arguments
if [ "$#" -gt 0 ]; then
    BUILD_ARGS="${BUILD_ARGS} $@"
fi

# Check if a program file should be loaded
if [ -n "${PROGRAM_FILE}" ] && [ -f "${PROGRAM_FILE}" ]; then
    echo -e "${YELLOW}Loading program: ${PROGRAM_FILE}${NC}"
    BUILD_ARGS="${BUILD_ARGS} --file ${PROGRAM_FILE}"
fi

# Check if a project should be loaded
if [ -n "${PROJECT_PATH}" ] && [ -d "${PROJECT_PATH}" ]; then
    echo -e "${YELLOW}Loading project: ${PROJECT_PATH}${NC}"
    BUILD_ARGS="${BUILD_ARGS} --project ${PROJECT_PATH}"
fi

USER_OPT=""
if [ -n "${GHIDRA_USER}" ]; then
    USER_OPT="-Duser.name=${GHIDRA_USER}"
fi

echo -e "${GREEN}Starting Ghidra headless server in background...${NC}"
java \
    ${JAVA_OPTS} \
    ${USER_OPT} \
    -Dghidra.home=${GHIDRA_HOME} \
    -Dapplication.name=GhidraMCP \
    -classpath "${CLASSPATH}" \
    com.xebyte.headless.GhidraMCPHeadlessServer \
    ${BUILD_ARGS} &
GHIDRA_PID=$!
echo "Ghidra server PID: $GHIDRA_PID"

# ---- Wait for Ghidra to be healthy ----
echo -e "${YELLOW}Waiting for Ghidra server to be ready...${NC}"
for i in $(seq 1 120); do
    if curl -sf http://localhost:${PORT}/check_connection > /dev/null 2>&1; then
        echo -e "${GREEN}Ghidra server healthy after ${i}s${NC}"
        break
    fi
    if ! kill -0 "$GHIDRA_PID" 2>/dev/null; then
        echo -e "${RED}ERROR: Ghidra server exited prematurely${NC}"
        exit 1
    fi
    sleep 2
done

# ---- Start MCP bridge in foreground ----
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Services running:${NC}"
echo -e "${GREEN}    REST API:     http://0.0.0.0:${PORT}${NC}"
echo -e "${GREEN}    MCP bridge:   http://0.0.0.0:8090/mcp (internal)${NC}"
echo -e "${GREEN}    MCP proxy:    http://0.0.0.0:8091/mcp (get_tool/invoke_tool)${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "${GREEN}Starting MCP bridge...${NC}"
/app/venv/bin/python /app/bridge_mcp_ghidra.py \
    --transport streamable-http \
    --mcp-host 0.0.0.0 \
    --mcp-port 8090 &
BRIDGE_PID=$!
echo "MCP bridge PID: $BRIDGE_PID"

# Wait for bridge to be ready
echo -e "${YELLOW}Waiting for MCP bridge to be ready...${NC}"
for i in $(seq 1 30); do
    if curl -sf http://localhost:8090/mcp -X POST \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"healthcheck","version":"1.0"}}}' > /dev/null 2>&1; then
        echo -e "${GREEN}MCP bridge ready after ${i}s${NC}"
        break
    fi
    sleep 2
done

# Start meta-tool proxy (get_tool / invoke_tool) — connects to the MCP bridge
echo -e "${GREEN}Starting meta-tool proxy...${NC}"
UPSTREAM_URL=http://localhost:8090/mcp \
    /app/venv/bin/python /app/proxy.py &
PROXY_PID=$!
echo "Meta-tool proxy PID: $PROXY_PID"

# Wait for proxy to be ready
echo -e "${YELLOW}Waiting for meta-tool proxy to be ready...${NC}"
for i in $(seq 1 30); do
    if curl -sf http://localhost:8091/health > /dev/null 2>&1; then
        echo -e "${GREEN}Meta-tool proxy ready after ${i}s${NC}"
        break
    fi
    sleep 2
done

# Wait for the bridge to exit (blocks until bridge dies)
wait $BRIDGE_PID
BRIDGE_EXIT=$?

# Kill proxy when bridge exits
if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
    kill "$PROXY_PID" 2>/dev/null || true
    wait "$PROXY_PID" 2>/dev/null || true
fi

# Bridge exited. Clean up Ghidra server before exiting.
echo -e "${YELLOW}MCP bridge exited (code $BRIDGE_EXIT). Cleaning up...${NC}"
if [ -n "$GHIDRA_PID" ] && kill -0 "$GHIDRA_PID" 2>/dev/null; then
    kill "$GHIDRA_PID" 2>/dev/null || true
    wait "$GHIDRA_PID" 2>/dev/null || true
fi

exit $BRIDGE_EXIT
