"""Tests for the JSON-RPC 2.0 transport and SDK types."""

import asyncio
import json
import io
import sys
from unittest.mock import patch

import pytest

from sbx_plugin.rpc import RpcTransport
from sbx_plugin.types import Sandbox, PortMapping, PolicyRule, EnvVar, ExecResult


# ---------------------------------------------------------------------------
# RpcTransport tests
# ---------------------------------------------------------------------------

class TestRpcTransportSend:
    """Test outgoing message encoding."""

    def test_send_writes_json_line(self):
        rpc = RpcTransport()
        buf = io.StringIO()
        with patch.object(sys, "stdout", buf):
            rpc._send({"jsonrpc": "2.0", "method": "test"})
        line = buf.getvalue()
        assert line.endswith("\n")
        msg = json.loads(line)
        assert msg == {"jsonrpc": "2.0", "method": "test"}

    def test_notify_sends_without_id(self):
        rpc = RpcTransport()
        buf = io.StringIO()
        with patch.object(sys, "stdout", buf):
            rpc.notify("shutdown")
        msg = json.loads(buf.getvalue())
        assert msg["method"] == "shutdown"
        assert "id" not in msg

    def test_notify_with_params(self):
        rpc = RpcTransport()
        buf = io.StringIO()
        with patch.object(sys, "stdout", buf):
            rpc.notify("event/created", {"name": "sb1"})
        msg = json.loads(buf.getvalue())
        assert msg["params"] == {"name": "sb1"}


class TestRpcTransportHandleMessage:
    """Test _handle_message dispatch logic."""

    @pytest.mark.asyncio
    async def test_response_resolves_pending_future(self):
        rpc = RpcTransport()
        loop = asyncio.get_event_loop()
        future = loop.create_future()
        rpc._pending[1] = future

        await rpc._handle_message({"jsonrpc": "2.0", "id": 1, "result": [{"name": "sb1"}]})

        assert future.done()
        assert future.result() == [{"name": "sb1"}]

    @pytest.mark.asyncio
    async def test_error_response_rejects_future(self):
        rpc = RpcTransport()
        loop = asyncio.get_event_loop()
        future = loop.create_future()
        rpc._pending[1] = future

        await rpc._handle_message({
            "jsonrpc": "2.0",
            "id": 1,
            "error": {"code": -32002, "message": "Sandbox not found"},
        })

        assert future.done()
        with pytest.raises(RuntimeError, match="Sandbox not found"):
            future.result()

    @pytest.mark.asyncio
    async def test_notification_calls_handler(self):
        rpc = RpcTransport()
        received = {}

        async def handler(params):
            received.update(params)

        rpc.on_notification("initialize", handler)

        await rpc._handle_message({
            "jsonrpc": "2.0",
            "method": "initialize",
            "params": {"pluginId": "test"},
        })

        assert received == {"pluginId": "test"}

    @pytest.mark.asyncio
    async def test_sync_notification_handler(self):
        rpc = RpcTransport()
        calls = []

        def handler(params):
            calls.append(params)

        rpc.on_notification("shutdown", handler)

        await rpc._handle_message({"jsonrpc": "2.0", "method": "shutdown"})

        assert len(calls) == 1

    @pytest.mark.asyncio
    async def test_request_from_host_calls_handler_and_responds(self):
        rpc = RpcTransport()
        buf = io.StringIO()

        async def handler(params):
            return "pong"

        rpc.on_request("ping", handler)

        with patch.object(sys, "stdout", buf):
            await rpc._handle_message({
                "jsonrpc": "2.0",
                "id": 99,
                "method": "ping",
                "params": {},
            })

        msg = json.loads(buf.getvalue())
        assert msg == {"jsonrpc": "2.0", "id": 99, "result": "pong"}

    @pytest.mark.asyncio
    async def test_request_handler_error_returns_error_response(self):
        rpc = RpcTransport()
        buf = io.StringIO()

        async def handler(params):
            raise ValueError("bad input")

        rpc.on_request("fail", handler)

        with patch.object(sys, "stdout", buf):
            await rpc._handle_message({
                "jsonrpc": "2.0",
                "id": 7,
                "method": "fail",
                "params": {},
            })

        msg = json.loads(buf.getvalue())
        assert msg["id"] == 7
        assert msg["error"]["code"] == -32603
        assert "bad input" in msg["error"]["message"]

    @pytest.mark.asyncio
    async def test_unknown_notification_does_not_crash(self):
        rpc = RpcTransport()
        # No handler registered — should silently ignore
        await rpc._handle_message({
            "jsonrpc": "2.0",
            "method": "event/unknown",
            "params": {},
        })

    @pytest.mark.asyncio
    async def test_unknown_response_id_does_not_crash(self):
        rpc = RpcTransport()
        # Response for a request we never sent
        await rpc._handle_message({
            "jsonrpc": "2.0",
            "id": 999,
            "result": "stale",
        })


class TestRpcTransportRequest:
    """Test outgoing request encoding."""

    @pytest.mark.asyncio
    async def test_request_sends_incrementing_ids(self):
        rpc = RpcTransport()
        buf = io.StringIO()
        loop = asyncio.get_event_loop()

        with patch.object(sys, "stdout", buf):
            # Start two requests (they'll pend forever without responses)
            t1 = asyncio.create_task(rpc.request("sandbox/list"))
            t2 = asyncio.create_task(rpc.request("sandbox/stop", {"name": "sb1"}))
            await asyncio.sleep(0.01)

        lines = [l for l in buf.getvalue().strip().split("\n") if l]
        assert len(lines) == 2

        msg1 = json.loads(lines[0])
        msg2 = json.loads(lines[1])
        assert msg1["id"] == 1
        assert msg1["method"] == "sandbox/list"
        assert msg2["id"] == 2
        assert msg2["params"] == {"name": "sb1"}

        # Cancel pending tasks
        t1.cancel()
        t2.cancel()
        try:
            await t1
        except (asyncio.CancelledError, RuntimeError):
            pass
        try:
            await t2
        except (asyncio.CancelledError, RuntimeError):
            pass


# ---------------------------------------------------------------------------
# Domain type tests
# ---------------------------------------------------------------------------

class TestTypes:
    def test_sandbox_from_dict(self):
        data = {"name": "sb1", "agent": "claude", "status": "running", "workspace": "/tmp/p"}
        sb = Sandbox(**data)
        assert sb.name == "sb1"
        assert sb.status == "running"
        assert sb.ports is None

    def test_sandbox_with_ports(self):
        sb = Sandbox(name="sb1", agent="claude", status="running", workspace="/tmp/p", ports=[{"hostPort": 8080}])
        assert len(sb.ports) == 1

    def test_port_mapping(self):
        pm = PortMapping(hostPort=8080, sandboxPort=3000)
        assert pm.protocolType == "tcp"

    def test_policy_rule(self):
        pr = PolicyRule(id="abc", type="network", decision="allow", resources="*.example.com")
        assert pr.decision == "allow"

    def test_env_var(self):
        ev = EnvVar(key="FOO", value="bar")
        assert ev.key == "FOO"

    def test_exec_result(self):
        er = ExecResult(stdout="hello", stderr="", exitCode=0)
        assert er.exitCode == 0
