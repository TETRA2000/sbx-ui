"""Output parsers for sbx CLI responses.

Ports the Swift SbxOutputParser logic to Python, handling both JSON
and tabular CLI output formats.
"""

from __future__ import annotations

import json
import re
from typing import Optional

from .models import (
    EnvVar,
    PolicyDecision,
    PolicyLogEntry,
    PolicyRule,
    PortMapping,
    Sandbox,
    SandboxStatus,
    is_valid_env_key,
)

_PORT_PATTERN = re.compile(r"(\d+)\s*[-\u2192>]+\s*(\d+)")

MANAGED_START = "# --- sbx-ui managed (DO NOT EDIT) ---"
MANAGED_END = "# --- end sbx-ui managed ---"


def parse_sandbox_list_json(stdout: str) -> list[Sandbox]:
    """Parse `sbx ls --json` output."""
    data = json.loads(stdout)
    sandboxes = []
    for s in data.get("sandboxes", []):
        ports = []
        for p in s.get("ports") or []:
            ports.append(
                PortMapping(
                    host_port=p["host_port"],
                    sandbox_port=p["sandbox_port"],
                    protocol_type=p.get("protocol", "tcp"),
                )
            )
        try:
            status = SandboxStatus(s["status"])
        except ValueError:
            status = SandboxStatus.STOPPED
        workspaces = s.get("workspaces") or []
        sandboxes.append(
            Sandbox(
                name=s["name"],
                agent=s["agent"],
                status=status,
                workspace=workspaces[0] if workspaces else "",
                ports=ports,
            )
        )
    return sandboxes


def parse_policy_list(stdout: str) -> list[PolicyRule]:
    """Parse `sbx policy ls` tabular output."""
    lines = [l for l in stdout.split("\n") if l.strip()]
    if len(lines) < 2:
        return []

    header = lines[0]
    id_range = _find_column_range(header, "NAME")
    type_range = _find_column_range(header, "TYPE")
    decision_range = _find_column_range(header, "DECISION")
    resources_range = _find_column_range(header, "RESOURCES")

    if not all([id_range, type_range, decision_range, resources_range]):
        return []

    rules = []
    for line in lines[1:]:
        rule_id = _extract_column(line, id_range).strip()
        rule_type = _extract_column(line, type_range).strip()
        decision_str = _extract_column(line, decision_range).strip().lower()
        resources = _extract_column(line, resources_range).strip()

        if not rule_id:
            continue
        try:
            decision = PolicyDecision(decision_str)
        except ValueError:
            continue

        rules.append(
            PolicyRule(
                id=rule_id,
                type=rule_type,
                decision=decision,
                resources=resources,
            )
        )
    return rules


def parse_policy_log_json(stdout: str) -> list[PolicyLogEntry]:
    """Parse `sbx policy log --json` output."""
    data = json.loads(stdout)
    entries = []

    for entry in data.get("allowed_hosts", []):
        entries.append(
            PolicyLogEntry(
                sandbox=entry["vm_name"],
                type="network",
                host=entry["host"],
                proxy=entry["proxy_type"],
                rule=entry["rule"],
                last_seen=entry.get("last_seen", ""),
                count=entry.get("count_since", 0),
                blocked=False,
            )
        )

    for entry in data.get("blocked_hosts", []):
        entries.append(
            PolicyLogEntry(
                sandbox=entry["vm_name"],
                type="network",
                host=entry["host"],
                proxy=entry["proxy_type"],
                rule=entry["rule"],
                last_seen=entry.get("last_seen", ""),
                count=entry.get("count_since", 0),
                blocked=True,
            )
        )

    return entries


def parse_ports_json(stdout: str) -> list[PortMapping]:
    """Parse `sbx ports <name> --json` output."""
    data = json.loads(stdout)
    return [
        PortMapping(
            host_port=p["host_port"],
            sandbox_port=p["sandbox_port"],
            protocol_type=p.get("protocol", "tcp"),
        )
        for p in data
    ]


def parse_managed_env_vars(file_content: str) -> list[EnvVar]:
    """Parse the sbx-ui managed section from /etc/sandbox-persistent.sh."""
    lines = file_content.split("\n")
    in_managed = False
    result = []

    for line in lines:
        trimmed = line.strip()
        if trimmed == MANAGED_START:
            in_managed = True
            continue
        if trimmed == MANAGED_END:
            break
        if in_managed:
            if not trimmed or trimmed.startswith("#"):
                continue
            stripped = trimmed
            if stripped.startswith("export "):
                stripped = stripped[7:]
            eq_idx = stripped.find("=")
            if eq_idx < 0:
                continue
            key = stripped[:eq_idx].strip()
            value = stripped[eq_idx + 1 :].strip()
            if not is_valid_env_key(key):
                continue
            result.append(EnvVar(key=key, value=value))
    return result


def rebuild_persistent_sh(
    existing_content: str, managed_vars: list[EnvVar]
) -> str:
    """Rebuild /etc/sandbox-persistent.sh preserving user content."""
    lines = existing_content.split("\n")
    before: list[str] = []
    after: list[str] = []
    in_managed = False
    past_managed = False

    for line in lines:
        trimmed = line.strip()
        if trimmed == MANAGED_START:
            in_managed = True
            continue
        if trimmed == MANAGED_END:
            in_managed = False
            past_managed = True
            continue
        if in_managed:
            continue
        if past_managed:
            after.append(line)
        else:
            before.append(line)

    # Build managed block
    managed_block: list[str] = []
    if managed_vars:
        managed_block.append(MANAGED_START)
        for v in managed_vars:
            managed_block.append(f"export {v.key}={v.value}")
        managed_block.append(MANAGED_END)

    # Assemble
    parts: list[str] = []

    before_lines = list(before)
    if managed_block:
        while before_lines and not before_lines[-1].strip():
            before_lines.pop()
    parts.extend(before_lines)

    if managed_block:
        if parts and parts[-1].strip():
            parts.append("")
        parts.extend(managed_block)

    if after:
        after_lines = list(after)
        while after_lines and not after_lines[0].strip():
            after_lines.pop(0)
        if after_lines:
            if managed_block:
                parts.append("")
            parts.extend(after_lines)

    result = "\n".join(parts)
    if not result:
        return ""
    return result if result.endswith("\n") else result + "\n"


# -- Private helpers --


def _find_column_range(
    header: str, column: str
) -> Optional[tuple[int, int]]:
    """Find the start/end positions of a column in a fixed-width header."""
    idx = header.find(column)
    if idx < 0:
        return None
    start = idx
    # Find start of next column (uppercase letter after whitespace gap)
    pos = idx + len(column)
    in_gap = False
    next_start = len(header)
    while pos < len(header):
        ch = header[pos]
        if ch == " ":
            in_gap = True
        elif in_gap and ch.isupper():
            next_start = pos
            break
        pos += 1
    return (start, next_start)


def _extract_column(line: str, col_range: Optional[tuple[int, int]]) -> str:
    """Extract a column value from a fixed-width line."""
    if col_range is None:
        return ""
    start, end = col_range
    if start >= len(line):
        return ""
    return line[start : min(end, len(line))]
