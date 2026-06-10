"""
MCP proxy that exposes only get_tool and invoke_tool meta-tools.
All tool calls are forwarded to an upstream MCP server.

Usage:
  UPSTREAM_URL=http://ghidra-mcp-headless:8090/mcp python proxy.py
"""

import os
import json
import asyncio
import logging
import re
from aiohttp import web
import httpx

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("mcp-proxy")

UPSTREAM_URL = os.environ.get("UPSTREAM_URL", "http://localhost:8090/mcp")
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8091"))

META_TOOLS = [
    {
        "name": "get_tool",
        "description": "Get the JSON schema for a specific tool by name. Use this to discover a tool's parameters before invoking it.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "The name of the tool to retrieve"
                }
            },
            "required": ["name"]
        }
    },
    {
        "name": "invoke_tool",
        "description": "Invoke a named tool with the given arguments. The name must be one of the tools returned by get_tool.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "The name of the tool to invoke"
                },
                "arguments": {
                    "type": "object",
                    "description": "Tool arguments as a JSON object. Use get_tool to discover the expected shape."
                }
            },
            "required": ["name", "arguments"]
        }
    }
]

# Regex to extract JSON payload from SSE data: lines
SSE_DATA_RE = re.compile(r'^data: (.+)$', re.MULTILINE)


def _parse_sse(body: str) -> dict | None:
    match = SSE_DATA_RE.search(body)
    if match:
        return json.loads(match.group(1))
    return None


class UpstreamClient:
    def __init__(self, base_url: str):
        self.base_url = base_url
        self._client = httpx.AsyncClient(timeout=180.0)
        self._session_id: str | None = None
        self._tools_cache: list[dict] | None = None

    async def close(self):
        await self._client.aclose()

    async def init_session(self):
        logger.info("Initializing upstream session...")
        resp = await self._send_raw({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "mcp-proxy", "version": "1.0.0"}
            }
        })
        self._session_id = resp.headers.get("mcp-session-id", "")
        body = resp.text
        payload = _parse_sse(body)
        if payload and "result" in payload:
            logger.info(
                "Upstream initialized: session=%s capabilities=%s",
                self._session_id,
                payload["result"].get("capabilities", {}),
            )
        else:
            logger.warning("Failed to parse initialize response: %s", body[:200])
            raise RuntimeError("Upstream initialize failed")

        # Send notifications/initialized (fire-and-forget)
        await self._send_raw({
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        })
        logger.info("Upstream session initialized (id=%s)", self._session_id)

    async def _headers(self) -> dict:
        hdrs = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self._session_id:
            hdrs["Mcp-Session-Id"] = self._session_id
        return hdrs

    async def _send_raw(self, body: dict) -> httpx.Response:
        resp = await self._client.post(
            self.base_url,
            json=body,
            headers=await self._headers(),
        )
        if resp.status_code == 202:
            return resp
        resp.raise_for_status()
        return resp

    async def _send_json(self, body: dict) -> dict | None:
        resp = await self._send_raw(body)
        if resp.status_code == 202:
            return None
        text = resp.text.strip()
        if not text:
            return None
        payload = _parse_sse(text)
        if payload is None:
            logger.error("Failed to parse SSE response: %s", text[:300])
            return {"error": {"code": -32700, "message": "Parse error"}}
        return payload

    async def list_tools(self) -> list[dict]:
        payload = await self._send_json({
            "jsonrpc": "2.0",
            "id": "list-tools",
            "method": "tools/list",
            "params": {}
        })
        if payload and "result" in payload:
            tools = payload["result"].get("tools", [])
            self._tools_cache = tools
            logger.info("Fetched %d tools from upstream", len(tools))
            return tools
        logger.warning("Failed to list upstream tools: %s", payload)
        return []

    async def call_tool(self, name: str, arguments: dict) -> dict:
        payload = await self._send_json({
            "jsonrpc": "2.0",
            "id": "call-tool",
            "method": "tools/call",
            "params": {
                "name": name,
                "arguments": arguments
            }
        })
        return payload or {"error": {"code": -32000, "message": "No response from upstream"}}


def make_error(id_val, code: int, message: str, data=None) -> dict:
    err: dict = {"jsonrpc": "2.0", "error": {"code": code, "message": message}}
    if id_val is not None:
        err["id"] = id_val
    if data is not None:
        err["error"]["data"] = data
    return err


def make_result(id_val, result: dict) -> dict:
    return {"jsonrpc": "2.0", "id": id_val, "result": result}


async def handle_mcp(request: web.Request) -> web.Response:
    upstream: UpstreamClient = request.app["upstream"]
    try:
        body = await request.json()
    except json.JSONDecodeError:
        return web.json_response(make_error(None, -32700, "Parse error"), status=400)

    msg_id = body.get("id")
    method = body.get("method")
    params = body.get("params", {})
    logger.debug("MCP request: method=%s id=%s", method, msg_id)

    if method == "initialize":
        return web.json_response(make_result(msg_id, {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "experimental": {},
                "tools": {"listChanged": False}
            },
            "serverInfo": {"name": "mcp-ghidra-proxy", "version": "1.0.0"}
        }))

    if method == "notifications/initialized":
        return web.json_response({}, status=202)

    if method == "tools/list":
        return web.json_response(make_result(msg_id, {"tools": META_TOOLS}))

    if method == "tools/call":
        tool_name = params.get("name", "")
        tool_args = params.get("arguments", {})

        if tool_name == "get_tool":
            target = tool_args.get("name", "")
            upstream_tools = await upstream.list_tools()
            for t in upstream_tools:
                if t["name"] == target:
                    return web.json_response(make_result(msg_id, {
                        "content": [
                            {"type": "text", "text": json.dumps(t, indent=2)}
                        ]
                    }))
            return web.json_response(make_result(msg_id, {
                "content": [
                    {"type": "text", "text": json.dumps({"error": f"Tool '{target}' not found"})}
                ],
                "isError": True
            }))

        if tool_name == "invoke_tool":
            target = tool_args.get("name", "")
            target_args = tool_args.get("arguments", {})
            try:
                payload = await upstream.call_tool(target, target_args)
                if "error" in payload:
                    return web.json_response(make_result(msg_id, {
                        "content": [{"type": "text", "text": json.dumps(payload["error"])}],
                        "isError": True
                    }))
                return web.json_response(make_result(msg_id, payload["result"]))
            except Exception as e:
                logger.exception("Failed to invoke tool '%s'", target)
                return web.json_response(make_result(msg_id, {
                    "content": [{"type": "text", "text": str(e)}],
                    "isError": True
                }))

        return web.json_response(make_error(msg_id, -32601, f"Unknown tool: {tool_name}"))

    if method == "ping":
        return web.json_response(make_result(msg_id, {}))

    return web.json_response(make_error(msg_id, -32601, f"Method not found: {method}"))


async def health(_request: web.Request) -> web.Response:
    return web.json_response({"status": "ok"})


async def app_factory() -> web.Application:
    upstream = UpstreamClient(UPSTREAM_URL)

    async def init_upstream():
        for attempt in range(30):
            try:
                await upstream.init_session()
                await upstream.list_tools()
                logger.info("Upstream connected on attempt %d", attempt + 1)
                return
            except Exception as e:
                logger.warning(
                    "Upstream not ready (attempt %d/30): %s", attempt + 1, e
                )
                await asyncio.sleep(2)
        logger.error("Failed to connect to upstream after 30 attempts")

    asyncio.create_task(init_upstream())

    app = web.Application()
    app["upstream"] = upstream
    app.router.add_post("/mcp", handle_mcp)
    app.router.add_get("/health", health)

    async def cleanup(app_):
        await upstream.close()
    app.on_cleanup.append(cleanup)

    return app


if __name__ == "__main__":
    logger.info("Starting MCP proxy (upstream=%s, bind=%s:%s)", UPSTREAM_URL, HOST, PORT)
    web.run_app(app_factory(), host=HOST, port=PORT)
