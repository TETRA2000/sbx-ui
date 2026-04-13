"""Domain models matching sbx CLI JSON schemas."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class SandboxStatus(Enum):
    RUNNING = "running"
    STOPPED = "stopped"
    CREATING = "creating"
    REMOVING = "removing"


class PolicyDecision(Enum):
    ALLOW = "allow"
    DENY = "deny"


@dataclass
class PortMapping:
    host_port: int
    sandbox_port: int
    protocol_type: str = "tcp"

    @property
    def id(self) -> str:
        return f"{self.host_port}-{self.sandbox_port}"


@dataclass
class Sandbox:
    name: str
    agent: str
    status: SandboxStatus
    workspace: str
    ports: list[PortMapping] = field(default_factory=list)

    @property
    def id(self) -> str:
        return self.name


@dataclass
class PolicyRule:
    id: str
    type: str  # "network"
    decision: PolicyDecision
    resources: str


@dataclass
class PolicyLogEntry:
    sandbox: str
    type: str  # "network"
    host: str
    proxy: str  # "forward", "transparent"
    rule: str
    last_seen: str
    count: int
    blocked: bool

    @property
    def id(self) -> str:
        return f"{self.sandbox}-{self.host}-{self.proxy}"


@dataclass
class EnvVar:
    key: str
    value: str

    @property
    def id(self) -> str:
        return self.key


@dataclass
class CliResult:
    stdout: str
    stderr: str
    exit_code: int


class SbxServiceError(Exception):
    """Base error for sbx service operations."""
    pass


class SandboxNotFoundError(SbxServiceError):
    def __init__(self, name: str):
        self.name = name
        super().__init__(f"Sandbox '{name}' not found")


class PortConflictError(SbxServiceError):
    def __init__(self, port: int):
        self.port = port
        super().__init__(f"Port {port} is already in use")


class DockerNotRunningError(SbxServiceError):
    def __init__(self):
        super().__init__(
            "Docker is not running. Please start Docker and try again."
        )


class InvalidNameError(SbxServiceError):
    def __init__(self, name: str):
        self.name = name
        super().__init__(
            f"Invalid sandbox name '{name}'. "
            "Names must be lowercase alphanumeric with hyphens, no leading hyphen."
        )


# Validation helpers matching Swift SbxValidation
_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
_ENV_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def is_valid_name(name: str) -> bool:
    return bool(_NAME_RE.match(name))


def is_valid_env_key(key: str) -> bool:
    return bool(_ENV_KEY_RE.match(key))
