#!/bin/bash

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

uv venv
uv pip install -r ghidramcp.requirements.txt
#uv run bridge_mcp_ghidra.py &
uvx mcpo --host localhost --port 3333 -- uv run bridge_mcp_ghidra.py

exit

# https://docs.openwebui.com/getting-started/env-configuration/
. .env
docker run -d -p 80:8080 \
-e ENABLE_OPENAI_API=True \
-e OPENAI_API_BASE_URL=$BASE_URL \
-e OPENAI_API_KEY=$API_KEY \
-e WEBUI_AUTH=False \
-e BYPASS_MODEL_ACCESS_CONTROL=True \
-e ENABLE_OLLAMA_API=False \
-e ENABLE_DIRECT_CONNECTIONS=False \
-v open-webui:/app/backend/data \
--name open-webui \
--restart always \
ghcr.io/open-webui/open-webui:main # the actual container name

echo "open-webui should be running at http://localhost"