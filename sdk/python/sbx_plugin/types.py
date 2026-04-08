"""Domain types for the sbx-ui Plugin SDK."""

from dataclasses import dataclass


@dataclass
class Sandbox:
    """A Docker Sandbox instance."""

    name: str
    agent: str
    status: str  # "running", "stopped", "creating", "removing"
    workspace: str
    ports: list[dict] | None = None


@dataclass
class PortMapping:
    """A port mapping between host and sandbox."""

    hostPort: int
    sandboxPort: int
    protocolType: str = "tcp"


@dataclass
class PolicyRule:
    """A network policy rule."""

    id: str
    type: str
    decision: str  # "allow" or "deny"
    resources: str


@dataclass
class EnvVar:
    """An environment variable."""

    key: str
    value: str


@dataclass
class ExecResult:
    """Result of executing a command in a sandbox."""

    stdout: str
    stderr: str
    exitCode: int
