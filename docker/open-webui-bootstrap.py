import json
import os
import urllib.error
import urllib.request
import sys

BASE = "http://localhost:{}".format(int(os.environ.get("PORT", "8080")))
ADMIN_EMAIL = os.environ.get("WEBUI_ADMIN_EMAIL", "")
ADMIN_PW = os.environ.get("WEBUI_ADMIN_PASSWORD", "")
DEFAULT_MODEL = os.environ.get("DEFAULT_MODELS", "grok-4.3")

if not ADMIN_EMAIL or not ADMIN_PW:
    print("SKIP: WEBUI_ADMIN_EMAIL/PASSWORD not set")
    sys.exit(0)

# Sign in as admin
req = urllib.request.Request(
    BASE + "/api/v1/auths/signin",
    data=json.dumps({"email": ADMIN_EMAIL, "password": ADMIN_PW}).encode(),
    headers={"Content-Type": "application/json"},
)
try:
    resp = json.loads(urllib.request.urlopen(req).read())
    token = resp["token"]
    print("Signed in as admin")
except Exception as e:
    print(f"WARN: Sign in failed: {e} -- tools will need manual setup")
    sys.exit(0)

auth_hdr = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

# Discover ALL MCP tool servers (auto-detects future additions)
req = urllib.request.Request(
    BASE + "/api/v1/tools/", headers={"Authorization": f"Bearer {token}"}
)
try:
    tools = json.loads(urllib.request.urlopen(req).read())
    mcp_ids = [t["id"] for t in tools if t["id"].startswith("server:mcp:")]
    print(f"Discovered {len(mcp_ids)} MCP tool(s): {mcp_ids}")
except Exception as e:
    print(f"WARN: Tool discovery failed: {e}")
    mcp_ids = []

if not mcp_ids:
    print("SKIP: No MCP tools discovered")
    sys.exit(0)

# Get the upstream model's capabilities (so override preserves them)
caps = {}
try:
    req = urllib.request.Request(
        BASE + "/api/models", headers={"Authorization": f"Bearer {token}"}
    )
    body = json.loads(urllib.request.urlopen(req).read())
    models = body.get("data", [])
    model_data = next((m for m in models if m.get("id") == DEFAULT_MODEL), None)
    if model_data:
        caps = model_data.get("info", {}).get("meta", {}, {}).get("capabilities", {})
        print(f"Model \"{DEFAULT_MODEL}\" found with capabilities: {list(caps.keys())}")
except Exception as e:
    print(f"WARN: Model discovery failed: {e}")

# Create/update a workspace model with all tool IDs
payload = json.dumps(
    {
        "id": DEFAULT_MODEL,
        "base_model_id": None,
        "name": DEFAULT_MODEL,
        "meta": {
            "toolIds": mcp_ids,
            "capabilities": caps,
            "description": "Auto-bound to {} MCP tool server(s)".format(
                len(mcp_ids)
            ),
        },
        "params": {"function_calling": "native"},
        "is_active": True,
    }
)

try:
    req = urllib.request.Request(
        BASE + "/api/v1/models/model/delete",
        data=json.dumps({"id": DEFAULT_MODEL}).encode(),
        headers=auth_hdr,
    )
    urllib.request.urlopen(req)
    print("Deleted existing model")
except urllib.error.HTTPError as e:
    if b"NOT_FOUND" not in e.read():
        print(f"WARN: Model delete gave HTTP {e.code} (ignoring)")
except Exception:
    pass  # First run -- model doesn't exist yet

# Then create fresh (works on first run and after delete)
try:
    req = urllib.request.Request(
        BASE + "/api/v1/models/create",
        data=payload.encode(),
        headers=auth_hdr,
    )
    resp = json.loads(urllib.request.urlopen(req).read())
    print(
        "Model created: {} -- tools: {}".format(
            resp.get("id"), resp.get("meta", {}).get("toolIds", [])
        )
    )
except urllib.error.HTTPError as e:
    err = e.read().decode()
    print(f"WARN: Model create failed (HTTP {e.code}): {err[:200]}")
except Exception as e:
    print(f"WARN: Model create failed: {e}")

print("Bootstrap complete.")
