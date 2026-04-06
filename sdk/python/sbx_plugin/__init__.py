"""sbx-ui Plugin SDK for Python."""

from sbx_plugin.rpc import RpcTransport
from sbx_plugin.types import Sandbox, PortMapping, PolicyRule, EnvVar, ExecResult

__all__ = [
    "SbxPlugin",
    "Sandbox",
    "PortMapping",
    "PolicyRule",
    "EnvVar",
    "ExecResult",
]


class SbxPlugin:
    """Main plugin class for building sbx-ui plugins.

    Example:
        >>> plugin = SbxPlugin()
        >>>
        >>> @plugin.on("initialize")
        ... async def on_init(params):
        ...     sandboxes = await plugin.sandbox.list()
        ...     await plugin.ui.log(f"Found {len(sandboxes)} sandboxes")
        >>>
        >>> plugin.start()
    """

    def __init__(self):
        self._rpc = RpcTransport()
        self._handlers: dict[str, object] = {}
        self.sandbox = _SandboxApi(self._rpc)
        self.ports = _PortsApi(self._rpc)
        self.env_vars = _EnvVarsApi(self._rpc)
        self.policy = _PolicyApi(self._rpc)
        self.file = _FileApi(self._rpc)
        self.ui = _UiApi(self._rpc)

    def on(self, event: str):
        """Decorator to register a handler for host notifications."""

        def decorator(handler):
            self._handlers[event] = handler
            return handler

        return decorator

    def start(self):
        """Start the plugin — begins listening for messages from the host."""
        for event, handler in self._handlers.items():
            self._rpc.on_notification(event, handler)
        self._rpc.run()


class _SandboxApi:
    def __init__(self, rpc: RpcTransport):
        self._rpc = rpc

    async def list(self) -> list[Sandbox]:
        result = await self._rpc.request("sandbox/list")
        return [Sandbox(**s) for s in result]

    async def exec(
        self, name: str, command: str, args: list[str] | None = None
    ) -> ExecResult:
        result = await self._rpc.request(
            "sandbox/exec", {"name": name, "command": command, "args": args or []}
        )
        return ExecResult(**result)

    async def stop(self, name: str) -> None:
        await self._rpc.request("sandbox/stop", {"name": name})

    async def run(
        self, agent: str, workspace: str, name: str | None = None
    ) -> Sandbox:
        params = {"agent": agent, "workspace": workspace}
        if name:
            params["name"] = name
        result = await self._rpc.request("sandbox/run", params)
        return Sandbox(**result)


class _PortsApi:
    def __init__(self, rpc: RpcTransport):
        self._rpc = rpc

    async def list(self, name: str) -> list[PortMapping]:
        result = await self._rpc.request("sandbox/ports/list", {"name": name})
        return [PortMapping(**p) for p in result]

    async def publish(
        self, name: str, host_port: int, sbx_port: int
    ) -> PortMapping:
        result = await self._rpc.request(
            "sandbox/ports/publish",
            {"name": name, "hostPort": host_port, "sbxPort": sbx_port},
        )
        return PortMapping(**result)

    async def unpublish(self, name: str, host_port: int, sbx_port: int) -> None:
        await self._rpc.request(
            "sandbox/ports/unpublish",
            {"name": name, "hostPort": host_port, "sbxPort": sbx_port},
        )


class _EnvVarsApi:
    def __init__(self, rpc: RpcTransport):
        self._rpc = rpc

    async def list(self, name: str) -> list[EnvVar]:
        result = await self._rpc.request("sandbox/envVars/list", {"name": name})
        return [EnvVar(**e) for e in result]

    async def set(self, name: str, key: str, value: str) -> None:
        await self._rpc.request(
            "sandbox/envVars/set", {"name": name, "key": key, "value": value}
        )


class _PolicyApi:
    def __init__(self, rpc: RpcTransport):
        self._rpc = rpc

    async def list(self) -> list[PolicyRule]:
        result = await self._rpc.request("policy/list")
        return [PolicyRule(**r) for r in result]

    async def allow(self, resources: str) -> PolicyRule:
        result = await self._rpc.request("policy/allow", {"resources": resources})
        return PolicyRule(**result)

    async def deny(self, resources: str) -> PolicyRule:
        result = await self._rpc.request("policy/deny", {"resources": resources})
        return PolicyRule(**result)

    async def remove(self, resource: str) -> None:
        await self._rpc.request("policy/remove", {"resource": resource})


class _FileApi:
    def __init__(self, rpc: RpcTransport):
        self._rpc = rpc

    async def read(self, path: str) -> dict:
        return await self._rpc.request("file/read", {"path": path})

    async def write(self, path: str, content: str) -> None:
        await self._rpc.request("file/write", {"path": path, "content": content})


class _UiApi:
    def __init__(self, rpc: RpcTransport):
        self._rpc = rpc

    async def notify(
        self, title: str, message: str, level: str = "info"
    ) -> None:
        await self._rpc.request(
            "ui/notify", {"title": title, "message": message, "level": level}
        )

    async def log(self, message: str, level: str = "info") -> None:
        await self._rpc.request("ui/log", {"message": message, "level": level})
