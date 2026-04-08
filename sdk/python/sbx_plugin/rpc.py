"""JSON-RPC 2.0 transport over stdin/stdout."""

from __future__ import annotations

import asyncio
import json
import sys
from typing import Any, Callable


class RpcTransport:
    """Bidirectional JSON-RPC 2.0 over stdin/stdout."""

    def __init__(self):
        self._next_id = 1
        self._pending: dict[int | str, asyncio.Future] = {}
        self._notification_handlers: dict[str, Callable] = {}
        self._request_handlers: dict[str, Callable] = {}

    def on_notification(self, method: str, handler: Callable) -> None:
        self._notification_handlers[method] = handler

    def on_request(self, method: str, handler: Callable) -> None:
        self._request_handlers[method] = handler

    async def request(
        self, method: str, params: dict[str, Any] | None = None
    ) -> Any:
        msg_id = self._next_id
        self._next_id += 1
        message = {"jsonrpc": "2.0", "id": msg_id, "method": method}
        if params is not None:
            message["params"] = params
        self._send(message)

        loop = asyncio.get_event_loop()
        future = loop.create_future()
        self._pending[msg_id] = future
        result = await future
        return result

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        message: dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            message["params"] = params
        self._send(message)

    def _send(self, message: dict) -> None:
        line = json.dumps(message, separators=(",", ":"))
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

    async def _handle_message(self, message: dict) -> None:
        if "method" in message and "id" in message:
            # Request from host
            handler = self._request_handlers.get(message["method"])
            if handler:
                try:
                    result = handler(message.get("params", {}))
                    if asyncio.iscoroutine(result):
                        result = await result
                    response = {
                        "jsonrpc": "2.0",
                        "id": message["id"],
                        "result": result,
                    }
                except Exception as e:
                    response = {
                        "jsonrpc": "2.0",
                        "id": message["id"],
                        "error": {"code": -32603, "message": str(e)},
                    }
                self._send(response)
        elif "method" in message:
            # Notification from host
            handler = self._notification_handlers.get(message["method"])
            if handler:
                try:
                    result = handler(message.get("params", {}))
                    if asyncio.iscoroutine(result):
                        await result
                except Exception as e:
                    print(f"Notification handler error: {e}", file=sys.stderr)
        elif "id" in message:
            # Response to our request
            future = self._pending.pop(message["id"], None)
            if future and not future.done():
                if "error" in message:
                    err = message["error"]
                    future.set_exception(
                        RuntimeError(f"{err['message']} (code: {err['code']})")
                    )
                else:
                    future.set_result(message.get("result"))

    async def _read_loop(self) -> None:
        loop = asyncio.get_event_loop()
        reader = asyncio.StreamReader()
        protocol = asyncio.StreamReaderProtocol(reader)
        await loop.connect_read_pipe(lambda: protocol, sys.stdin)

        while True:
            line = await reader.readline()
            if not line:
                break
            try:
                message = json.loads(line.decode())
                await self._handle_message(message)
            except json.JSONDecodeError:
                print(f"Failed to parse: {line}", file=sys.stderr)

    def run(self) -> None:
        """Start the event loop and read messages until stdin closes."""
        asyncio.run(self._read_loop())
