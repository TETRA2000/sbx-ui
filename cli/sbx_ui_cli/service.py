"""Service layer wrapping the sbx CLI.

Ports the Swift RealSbxService/CliExecutor logic to Python, invoking
the sbx CLI as a subprocess and parsing its output.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Optional

from .models import (
    CliResult,
    DockerNotRunningError,
    EnvVar,
    InvalidNameError,
    PortConflictError,
    PortMapping,
    PolicyLogEntry,
    PolicyRule,
    Sandbox,
    SandboxNotFoundError,
    SbxServiceError,
    is_valid_name,
)
from .parser import (
    parse_managed_env_vars,
    parse_policy_list,
    parse_policy_log_json,
    parse_ports_json,
    parse_sandbox_list_json,
    rebuild_persistent_sh,
)


class SbxService:
    """Wraps the sbx CLI, mirroring the Swift SbxServiceProtocol interface."""

    def __init__(self, sbx_command: Optional[str] = None):
        self._sbx = sbx_command or self._resolve_sbx()

    # -- Lifecycle --

    def list(self) -> list[Sandbox]:
        result = self._exec(["ls", "--json"])
        self._check(result)
        return parse_sandbox_list_json(result.stdout)

    def create(
        self,
        agent: str,
        workspace: str,
        name: Optional[str] = None,
    ) -> Sandbox:
        args = ["create", agent, workspace]
        if name:
            if not is_valid_name(name):
                raise InvalidNameError(name)
            args += ["--name", name]
        result = self._exec(args)
        self._check(result)
        # Re-fetch to get the sandbox with full details
        sandboxes = self.list()
        target = name or f"{agent}-{Path(workspace).name}"
        for s in sandboxes:
            if s.name == target or s.workspace == workspace:
                return s
        raise SbxServiceError("Sandbox not found after creation")

    def run(self, name: str) -> None:
        """Attach to a running sandbox interactively (replaces current process)."""
        os.execvp(self._sbx, [self._sbx, "run", name])

    def stop(self, name: str) -> None:
        result = self._exec(["stop", name])
        self._check(result)

    def rm(self, name: str) -> None:
        result = self._exec(["rm", "-f", name])
        self._check(result)

    # -- Network Policies --

    def policy_list(self) -> list[PolicyRule]:
        result = self._exec(["policy", "ls"])
        self._check(result)
        return parse_policy_list(result.stdout)

    def policy_allow(self, resources: str) -> PolicyRule:
        result = self._exec(["policy", "allow", "network", resources])
        self._check(result)
        rules = self.policy_list()
        for r in rules:
            if r.resources == resources and r.decision.value == "allow":
                return r
        from .models import PolicyDecision
        return PolicyRule(
            id="unknown", type="network", decision=PolicyDecision.ALLOW,
            resources=resources,
        )

    def policy_deny(self, resources: str) -> PolicyRule:
        result = self._exec(["policy", "deny", "network", resources])
        self._check(result)
        rules = self.policy_list()
        for r in rules:
            if r.resources == resources and r.decision.value == "deny":
                return r
        from .models import PolicyDecision
        return PolicyRule(
            id="unknown", type="network", decision=PolicyDecision.DENY,
            resources=resources,
        )

    def policy_remove(self, resource: str) -> None:
        result = self._exec(["policy", "rm", "network", "--resource", resource])
        self._check(result)

    def policy_log(
        self, sandbox_name: Optional[str] = None
    ) -> list[PolicyLogEntry]:
        args = ["policy", "log"]
        if sandbox_name:
            args.append(sandbox_name)
        args.append("--json")
        result = self._exec(args)
        self._check(result)
        if not result.stdout.strip() or "No policy log" in result.stdout:
            return []
        return parse_policy_log_json(result.stdout)

    # -- Port Forwarding --

    def ports_list(self, name: str) -> list[PortMapping]:
        result = self._exec(["ports", name, "--json"])
        self._check(result)
        if not result.stdout.strip() or "No published" in result.stdout:
            return []
        return parse_ports_json(result.stdout)

    def ports_publish(
        self, name: str, host_port: int, sbx_port: int
    ) -> PortMapping:
        result = self._exec(
            ["ports", name, "--publish", f"{host_port}:{sbx_port}"]
        )
        self._check(result)
        return PortMapping(
            host_port=host_port,
            sandbox_port=sbx_port,
            protocol_type="tcp",
        )

    def ports_unpublish(
        self, name: str, host_port: int, sbx_port: int
    ) -> None:
        result = self._exec(
            ["ports", name, "--unpublish", f"{host_port}:{sbx_port}"]
        )
        self._check(result)

    # -- Environment Variables --

    def env_list(self, name: str) -> list[EnvVar]:
        result = self._exec(
            ["exec", name, "cat", "/etc/sandbox-persistent.sh"]
        )
        if result.exit_code != 0:
            if "No such file" in result.stderr or "No such file" in result.stdout:
                return []
            self._check(result)
        return parse_managed_env_vars(result.stdout)

    def env_set(self, name: str, key: str, value: str) -> None:
        """Add or update a managed environment variable."""
        current = self.env_list(name)
        updated = [v for v in current if v.key != key]
        updated.append(EnvVar(key=key, value=value))
        self._env_sync(name, updated)

    def env_remove(self, name: str, key: str) -> None:
        """Remove a managed environment variable."""
        current = self.env_list(name)
        updated = [v for v in current if v.key != key]
        self._env_sync(name, updated)

    def _env_sync(self, name: str, vars: list[EnvVar]) -> None:
        """Sync managed env vars to /etc/sandbox-persistent.sh."""
        read_result = self._exec(
            ["exec", name, "cat", "/etc/sandbox-persistent.sh"]
        )
        existing = read_result.stdout if read_result.exit_code == 0 else ""
        new_content = rebuild_persistent_sh(existing, vars)

        if not new_content:
            rm_result = self._exec(
                ["exec", "-d", name, "bash", "-c",
                 "rm -f /etc/sandbox-persistent.sh"]
            )
            self._check(rm_result)
        else:
            script = (
                f"cat > /etc/sandbox-persistent.sh << 'SBXENVEOF'\n"
                f"{new_content}SBXENVEOF"
            )
            write_result = self._exec(
                ["exec", "-d", name, "bash", "-c", script]
            )
            self._check(write_result)

    # -- Exec --

    def exec(self, name: str, command: str, args: list[str]) -> CliResult:
        result = self._exec(["exec", name, command] + args)
        self._check(result)
        return result

    # -- Private --

    def _resolve_sbx(self) -> str:
        """Find the sbx command on PATH."""
        sbx = shutil.which("sbx")
        if sbx:
            return sbx
        # Check common locations
        for path in ["/usr/local/bin/sbx", "/usr/bin/sbx", "/opt/homebrew/bin/sbx"]:
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        return "sbx"  # Fall through, let subprocess raise FileNotFoundError

    def _exec(self, args: list[str]) -> CliResult:
        """Execute an sbx CLI command."""
        try:
            proc = subprocess.run(
                [self._sbx] + args,
                capture_output=True,
                text=True,
                timeout=60,
            )
            return CliResult(
                stdout=proc.stdout,
                stderr=proc.stderr,
                exit_code=proc.returncode,
            )
        except FileNotFoundError:
            raise SbxServiceError(
                f"sbx CLI not found at '{self._sbx}'. "
                "Install it from https://docs.docker.com/sandbox/"
            )
        except subprocess.TimeoutExpired:
            raise SbxServiceError("sbx command timed out after 60 seconds")

    def _check(self, result: CliResult) -> None:
        """Check CLI result for errors, classifying them into specific types."""
        if result.exit_code == 0:
            return

        stderr = result.stderr.strip()
        stdout = result.stdout.strip()
        error_text = stderr or stdout

        if "docker" in error_text.lower() and (
            "not running" in error_text.lower()
            or "cannot connect" in error_text.lower()
        ):
            raise DockerNotRunningError()

        if "not found" in error_text:
            # Extract sandbox name from: Error: sandbox 'name' not found
            parts = error_text.split("'")
            name = parts[1] if len(parts) >= 2 else "unknown"
            raise SandboxNotFoundError(name)

        if "already published" in error_text:
            import re
            match = re.search(r"(\d+)/tcp is already published", error_text)
            if match:
                raise PortConflictError(int(match.group(1)))

        raise SbxServiceError(
            error_text or f"Command failed with exit code {result.exit_code}"
        )
