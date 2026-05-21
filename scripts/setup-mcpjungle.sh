#!/bin/bash
# setup-mcpjungle.sh
#
# Post-startup registration and Tool Group management for MCPJungle.
# Complements the one-shot mcp-setup init container by providing:
# - Re-runnable registration (in case init container fails or needs re-run)
# - Functions to add/remove tools from the "re-tools" Tool Group
# - Listing of registered servers and their tools
#
# Run AFTER `docker compose up -d`.
# Must be executed from the project root directory.

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
MCPJUNGLE_SERVICE="mcpjungle"
GHIDRA_NAME="ghidra"
GROUP_NAME="re-tools"

# -----------------------------------------------------------------------------
# Helper: Check if Docker is available and compose context is valid
# -----------------------------------------------------------------------------
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker is not running or not accessible." >&2
        echo "Please start Docker Desktop / Docker daemon and try again." >&2
        exit 1
    fi

    if ! docker compose version >/dev/null 2>&1; then
        echo "Error: 'docker compose' is not available." >&2
        echo "Please ensure Docker Compose v2+ is installed." >&2
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Wait for MCPJungle health (used by register)
# -----------------------------------------------------------------------------
wait_for_health() {
    local max_retries=60
    local retry=0

    echo "Waiting for MCPJungle to become healthy (max ${max_retries}s)..."

    while [ $retry -lt $max_retries ]; do
        if docker compose exec -T "$MCPJUNGLE_SERVICE" /mcpjungle health >/dev/null 2>&1; then
            echo "MCPJungle is healthy."
            return 0
        fi

        retry=$((retry + 1))
        echo "  ... retry ${retry}/${max_retries}"
        sleep 1
    done

    echo "Error: Timed out waiting for MCPJungle health after ${max_retries} seconds." >&2
    echo "Check container logs: docker compose logs mcpjungle" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Check if ghidra is already registered (idempotent register)
# -----------------------------------------------------------------------------
is_ghidra_registered() {
    # List servers and grep for our name. Output is JSON-ish; we just need presence.
    if docker compose exec -T "$MCPJUNGLE_SERVICE" /mcpjungle list 2>/dev/null | grep -q "\"name\": \"${GHIDRA_NAME}\""; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Register ghidra-mcp with MCPJungle (idempotent)
# -----------------------------------------------------------------------------
cmd_register() {
    check_docker
    wait_for_health

    if is_ghidra_registered; then
        echo "ghidra is already registered. Skipping registration."
        return 0
    fi

    echo "Registering ghidra-mcp with MCPJungle..."
    docker compose exec -T "$MCPJUNGLE_SERVICE" /mcpjungle register \
        --name "$GHIDRA_NAME" \
        --description "Ghidra binary analysis MCP server" \
        --url http://ghidra-mcp:8080

    echo "Registration complete."
}

# -----------------------------------------------------------------------------
# Create the "re-tools" Tool Group (idempotent)
# -----------------------------------------------------------------------------
cmd_create_group() {
    check_docker

    # Try to create; if it already exists, MCPJungle will error — we treat that as success.
    if docker compose exec -T "$MCPJUNGLE_SERVICE" /mcpjungle group create \
        --name "$GROUP_NAME" \
        --description "Reverse engineering tools (curated subset)" 2>&1; then
        echo "Tool Group '${GROUP_NAME}' created (or already existed)."
    else
        # The error path is expected when group exists; we still consider it success.
        echo "Tool Group '${GROUP_NAME}' already exists."
    fi
}

# -----------------------------------------------------------------------------
# Add a tool to the re-tools group
# -----------------------------------------------------------------------------
cmd_group_add() {
    local tool_name="${1:-}"
    if [ -z "$tool_name" ]; then
        echo "Usage: $SCRIPT_NAME group-add <tool-name>" >&2
        exit 1
    fi

    check_docker
    echo "Adding tool '${tool_name}' to group '${GROUP_NAME}'..."
    docker compose exec -T "$MCPJUNGLE_SERVICE" /mcpjungle group add-tool \
        --group "$GROUP_NAME" \
        --tool "$tool_name"
    echo "Tool added."
}

# -----------------------------------------------------------------------------
# Remove a tool from the re-tools group
# -----------------------------------------------------------------------------
cmd_group_remove() {
    local tool_name="${1:-}"
    if [ -z "$tool_name" ]; then
        echo "Usage: $SCRIPT_NAME group-remove <tool-name>" >&2
        exit 1
    fi

    check_docker
    echo "Removing tool '${tool_name}' from group '${GROUP_NAME}'..."
    docker compose exec -T "$MCPJUNGLE_SERVICE" /mcpjungle group remove-tool \
        --group "$GROUP_NAME" \
        --tool "$tool_name"
    echo "Tool removed."
}

# -----------------------------------------------------------------------------
# List all registered MCP servers and their tools
# -----------------------------------------------------------------------------
cmd_list_tools() {
    check_docker
    echo "Registered MCP servers and tools:"
    docker compose exec -T "$MCPJUNGLE_SERVICE" /mcpjungle list --tools
}

# -----------------------------------------------------------------------------
# Show help / usage
# -----------------------------------------------------------------------------
cmd_help() {
    cat <<EOF
Usage: $SCRIPT_NAME <command> [args]

Post-startup MCPJungle registration and Tool Group management script.

Commands:
  register              Register ghidra-mcp with MCPJungle (idempotent, waits for health)
  group-add <tool>      Add a tool (by canonical name) to the "re-tools" group
  group-remove <tool>   Remove a tool from the "re-tools" group
  list-tools            List all registered MCP servers and their tools
  help                  Show this help message

No arguments:
  Run the default full setup: register + create group

Examples:
  $SCRIPT_NAME
  $SCRIPT_NAME register
  $SCRIPT_NAME group-add ghidra.list_functions
  $SCRIPT_NAME list-tools

Must be run from the project root (where docker-compose.yml lives).
EOF
}

# -----------------------------------------------------------------------------
# Default full setup (register + create group)
# -----------------------------------------------------------------------------
cmd_default() {
    cmd_register
    cmd_create_group
    echo "Default setup complete. Use '$SCRIPT_NAME list-tools' to inspect."
}

# -----------------------------------------------------------------------------
# Main dispatcher
# -----------------------------------------------------------------------------
main() {
    local cmd="${1:-}"

    case "$cmd" in
        register)
            cmd_register
            ;;
        group-add)
            shift
            cmd_group_add "$@"
            ;;
        group-remove)
            shift
            cmd_group_remove "$@"
            ;;
        list-tools)
            cmd_list_tools
            ;;
        help|--help|-h)
            cmd_help
            ;;
        "")
            cmd_default
            ;;
        *)
            echo "Error: Unknown command '$cmd'" >&2
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
