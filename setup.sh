#!/bin/bash

if ! command -v ghidra >/dev/null 2>&1; then
    echo "ghidra not installed!"
    exit
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "docker not installed!"
    exit
fi

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