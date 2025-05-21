#!/bin/bash
. .env # BASE_URL API_KEY HOST PORT

check_installed() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "$1 not installed!"
        echo "Exiting"
        exit
    fi
}
check_installed docker
check_installed ghidra
check_installed uv

PID=$(lsof -t -i :$PORT)
if [ -n "$PID" ]; then
    echo "Port $PORT already bound by PID $PID; killing it..."
    kill $PID
fi

uv venv
uv pip install -r ghidramcp.requirements.txt
uvx mcpo --host $HOST --port $PORT -- uv run bridge_mcp_ghidra.py & 

echo "starting open-webui at http://localhost"
# https://docs.openwebui.com/getting-started/env-configuration/
docker run -d -p 80:8080 \
-e ENABLE_OPENAI_API=True \
-e OPENAI_API_BASE_URL=$BASE_URL \
-e OPENAI_API_KEY=$API_KEY \
-e WEBUI_AUTH=False \
-e BYPASS_MODEL_ACCESS_CONTROL=True \
-e ENABLE_OLLAMA_API=False \
-e ENABLE_DIRECT_CONNECTIONS=True \
-e USER_PERMISSIONS_FEATURES_DIRECT_TOOL_SERVERS \
-e USER_PERMISSIONS_WORKSPACE_TOOLS_ACCESS \
-e USER_PERMISSIONS_WORKSPACE_TOOLS_ALLOW_PUBLIC_SHARING \
-v open-webui:/app/backend/data \
--name open-webui \
--restart always \
ghcr.io/open-webui/open-webui:main # the actual container name