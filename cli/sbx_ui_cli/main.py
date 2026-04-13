"""CLI entry point for sbx-ui-cli.

Provides subcommands mirroring the macOS GUI functionality:
  - Sandbox lifecycle: ls, create, stop, rm, run, exec
  - Network policies: policy {ls, allow, deny, rm, log}
  - Port forwarding: ports {ls, publish, unpublish}
  - Environment variables: env {ls, set, rm}
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Optional

from . import __version__
from .formatter import (
    bold,
    bright_green,
    bright_red,
    cyan,
    decision_color,
    dim,
    green,
    print_error,
    print_info,
    print_section,
    print_success,
    print_table,
    red,
    status_color,
    yellow,
)
from .models import SbxServiceError
from .service import SbxService


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="sbx-ui",
        description="Linux CLI for Docker Sandbox management",
    )
    parser.add_argument(
        "--version", action="version", version=f"sbx-ui-cli {__version__}"
    )
    parser.add_argument(
        "--json", dest="output_json", action="store_true",
        help="Output in JSON format",
    )

    sub = parser.add_subparsers(dest="command", metavar="COMMAND")

    # -- ls --
    p_ls = sub.add_parser("ls", help="List sandboxes")

    # -- create --
    p_create = sub.add_parser("create", help="Create a new sandbox")
    p_create.add_argument("workspace", help="Workspace path to mount")
    p_create.add_argument(
        "--name", "-n", help="Sandbox name (default: <agent>-<dirname>)"
    )
    p_create.add_argument(
        "--agent", "-a", default="claude",
        help="Agent to use (default: claude)",
    )

    # -- run --
    p_run = sub.add_parser(
        "run", help="Attach to a sandbox interactively"
    )
    p_run.add_argument("name", help="Sandbox name")

    # -- stop --
    p_stop = sub.add_parser("stop", help="Stop a sandbox")
    p_stop.add_argument("name", help="Sandbox name")

    # -- rm --
    p_rm = sub.add_parser("rm", help="Remove a sandbox")
    p_rm.add_argument("name", help="Sandbox name")

    # -- exec --
    p_exec = sub.add_parser("exec", help="Execute command in a sandbox")
    p_exec.add_argument("name", help="Sandbox name")
    p_exec.add_argument("cmd", help="Command to execute")
    p_exec.add_argument(
        "args", nargs="*", default=[], help="Command arguments"
    )

    # -- policy --
    p_policy = sub.add_parser("policy", help="Manage network policies")
    policy_sub = p_policy.add_subparsers(dest="policy_cmd", metavar="ACTION")

    p_pol_ls = policy_sub.add_parser("ls", help="List policies")

    p_pol_allow = policy_sub.add_parser(
        "allow", help="Add allow rule"
    )
    p_pol_allow.add_argument(
        "resources", help="Domain pattern to allow"
    )

    p_pol_deny = policy_sub.add_parser("deny", help="Add deny rule")
    p_pol_deny.add_argument(
        "resources", help="Domain pattern to deny"
    )

    p_pol_rm = policy_sub.add_parser("rm", help="Remove a policy rule")
    p_pol_rm.add_argument(
        "resources", help="Resource pattern to remove"
    )

    p_pol_log = policy_sub.add_parser("log", help="View policy log")
    p_pol_log.add_argument(
        "sandbox", nargs="?", default=None,
        help="Filter by sandbox name",
    )
    p_pol_log.add_argument(
        "--blocked", action="store_true",
        help="Show only blocked requests",
    )

    # -- ports --
    p_ports = sub.add_parser("ports", help="Manage port forwarding")
    ports_sub = p_ports.add_subparsers(dest="ports_cmd", metavar="ACTION")

    p_port_ls = ports_sub.add_parser("ls", help="List published ports")
    p_port_ls.add_argument("name", help="Sandbox name")

    p_port_pub = ports_sub.add_parser(
        "publish", help="Publish a port"
    )
    p_port_pub.add_argument("name", help="Sandbox name")
    p_port_pub.add_argument(
        "spec", help="Port spec HOST_PORT:SANDBOX_PORT"
    )

    p_port_unpub = ports_sub.add_parser(
        "unpublish", help="Unpublish a port"
    )
    p_port_unpub.add_argument("name", help="Sandbox name")
    p_port_unpub.add_argument(
        "spec", help="Port spec HOST_PORT:SANDBOX_PORT"
    )

    # -- env --
    p_env = sub.add_parser("env", help="Manage environment variables")
    env_sub = p_env.add_subparsers(dest="env_cmd", metavar="ACTION")

    p_env_ls = env_sub.add_parser(
        "ls", help="List environment variables"
    )
    p_env_ls.add_argument("name", help="Sandbox name")

    p_env_set = env_sub.add_parser("set", help="Set an environment variable")
    p_env_set.add_argument("name", help="Sandbox name")
    p_env_set.add_argument("key", help="Variable name")
    p_env_set.add_argument("value", help="Variable value")

    p_env_rm = env_sub.add_parser(
        "rm", help="Remove an environment variable"
    )
    p_env_rm.add_argument("name", help="Sandbox name")
    p_env_rm.add_argument("key", help="Variable name to remove")

    # -- status (convenience: show single sandbox details) --
    p_status = sub.add_parser(
        "status", help="Show detailed status of a sandbox"
    )
    p_status.add_argument("name", help="Sandbox name")

    args = parser.parse_args(argv)

    if not args.command:
        parser.print_help()
        return 0

    svc = SbxService()

    try:
        return _dispatch(svc, args)
    except SbxServiceError as e:
        print_error(str(e))
        return 1
    except KeyboardInterrupt:
        print()
        return 130
    except BrokenPipeError:
        return 0


def _dispatch(svc: SbxService, args: argparse.Namespace) -> int:
    cmd = args.command

    if cmd == "ls":
        return _cmd_ls(svc, args)
    elif cmd == "create":
        return _cmd_create(svc, args)
    elif cmd == "run":
        return _cmd_run(svc, args)
    elif cmd == "stop":
        return _cmd_stop(svc, args)
    elif cmd == "rm":
        return _cmd_rm(svc, args)
    elif cmd == "exec":
        return _cmd_exec(svc, args)
    elif cmd == "policy":
        return _dispatch_policy(svc, args)
    elif cmd == "ports":
        return _dispatch_ports(svc, args)
    elif cmd == "env":
        return _dispatch_env(svc, args)
    elif cmd == "status":
        return _cmd_status(svc, args)
    else:
        print_error(f"Unknown command: {cmd}")
        return 1


# -- Sandbox Lifecycle --


def _cmd_ls(svc: SbxService, args: argparse.Namespace) -> int:
    sandboxes = svc.list()
    if args.output_json:
        data = [
            {
                "name": s.name,
                "agent": s.agent,
                "status": s.status.value,
                "workspace": s.workspace,
                "ports": [
                    {
                        "host_port": p.host_port,
                        "sandbox_port": p.sandbox_port,
                        "protocol": p.protocol_type,
                    }
                    for p in s.ports
                ],
            }
            for s in sandboxes
        ]
        print(json.dumps(data, indent=2))
        return 0

    if not sandboxes:
        print_info("No sandboxes found. Create one with: sbx-ui create <workspace>")
        return 0

    rows = []
    for s in sandboxes:
        ports_str = ", ".join(
            f"{p.host_port}->{p.sandbox_port}/{p.protocol_type}"
            for p in s.ports
        ) if s.ports else ""
        rows.append([s.name, s.agent, s.status.value, ports_str, s.workspace])

    print_table(
        ["SANDBOX", "AGENT", "STATUS", "PORTS", "WORKSPACE"],
        rows,
        color_cols={2: status_color},
    )
    return 0


def _cmd_create(svc: SbxService, args: argparse.Namespace) -> int:
    print_info(
        f"Creating sandbox with agent '{args.agent}' "
        f"at {args.workspace}..."
    )
    sandbox = svc.create(args.agent, args.workspace, name=args.name)
    if args.output_json:
        print(json.dumps({
            "name": sandbox.name,
            "agent": sandbox.agent,
            "status": sandbox.status.value,
            "workspace": sandbox.workspace,
        }, indent=2))
    else:
        print_success(f"Created sandbox '{sandbox.name}'")
        print(f"  Workspace: {sandbox.workspace}")
        print(f"  Agent: {sandbox.agent}")
        print(f"  Status: {status_color(sandbox.status.value)}")
    return 0


def _cmd_run(svc: SbxService, args: argparse.Namespace) -> int:
    print_info(f"Attaching to sandbox '{args.name}'...")
    svc.run(args.name)  # replaces current process
    return 0  # unreachable


def _cmd_stop(svc: SbxService, args: argparse.Namespace) -> int:
    svc.stop(args.name)
    print_success(f"Stopped sandbox '{args.name}'")
    return 0


def _cmd_rm(svc: SbxService, args: argparse.Namespace) -> int:
    svc.rm(args.name)
    print_success(f"Removed sandbox '{args.name}'")
    return 0


def _cmd_exec(svc: SbxService, args: argparse.Namespace) -> int:
    result = svc.exec(args.name, args.cmd, args.args)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return 0


def _cmd_status(svc: SbxService, args: argparse.Namespace) -> int:
    sandboxes = svc.list()
    sandbox = next((s for s in sandboxes if s.name == args.name), None)
    if not sandbox:
        from .models import SandboxNotFoundError
        raise SandboxNotFoundError(args.name)

    if args.output_json:
        data = {
            "name": sandbox.name,
            "agent": sandbox.agent,
            "status": sandbox.status.value,
            "workspace": sandbox.workspace,
            "ports": [
                {
                    "host_port": p.host_port,
                    "sandbox_port": p.sandbox_port,
                    "protocol": p.protocol_type,
                }
                for p in sandbox.ports
            ],
        }
        # Add env vars and policies if sandbox is running
        if sandbox.status.value == "running":
            try:
                data["env_vars"] = [
                    {"key": v.key, "value": v.value}
                    for v in svc.env_list(args.name)
                ]
            except Exception:
                data["env_vars"] = []
        print(json.dumps(data, indent=2))
        return 0

    print_section(f"Sandbox: {sandbox.name}")
    print(f"  Agent:     {sandbox.agent}")
    print(f"  Status:    {status_color(sandbox.status.value)}")
    print(f"  Workspace: {sandbox.workspace}")

    if sandbox.ports:
        print()
        print(f"  {bold('Ports:')}")
        for p in sandbox.ports:
            print(
                f"    {p.host_port} → {p.sandbox_port}/{p.protocol_type}"
            )

    if sandbox.status.value == "running":
        try:
            env_vars = svc.env_list(args.name)
            if env_vars:
                print()
                print(f"  {bold('Environment Variables:')}")
                for v in env_vars:
                    print(f"    {cyan(v.key)}={v.value}")
        except Exception:
            pass

    print()
    return 0


# -- Policy Commands --


def _dispatch_policy(svc: SbxService, args: argparse.Namespace) -> int:
    if not args.policy_cmd:
        print_error("Usage: sbx-ui policy {ls|allow|deny|rm|log}")
        return 1

    if args.policy_cmd == "ls":
        return _cmd_policy_ls(svc, args)
    elif args.policy_cmd == "allow":
        return _cmd_policy_allow(svc, args)
    elif args.policy_cmd == "deny":
        return _cmd_policy_deny(svc, args)
    elif args.policy_cmd == "rm":
        return _cmd_policy_rm(svc, args)
    elif args.policy_cmd == "log":
        return _cmd_policy_log(svc, args)
    return 1


def _cmd_policy_ls(svc: SbxService, args: argparse.Namespace) -> int:
    rules = svc.policy_list()
    if args.output_json:
        data = [
            {
                "id": r.id,
                "type": r.type,
                "decision": r.decision.value,
                "resources": r.resources,
            }
            for r in rules
        ]
        print(json.dumps(data, indent=2))
        return 0

    if not rules:
        print_info("No network policies configured.")
        return 0

    rows = [
        [r.id, r.type, r.decision.value, r.resources]
        for r in rules
    ]
    print_table(
        ["NAME", "TYPE", "DECISION", "RESOURCES"],
        rows,
        color_cols={2: decision_color},
    )
    return 0


def _cmd_policy_allow(svc: SbxService, args: argparse.Namespace) -> int:
    rule = svc.policy_allow(args.resources)
    print_success(
        f"Policy added: {green('allow')} network {args.resources}"
    )
    return 0


def _cmd_policy_deny(svc: SbxService, args: argparse.Namespace) -> int:
    rule = svc.policy_deny(args.resources)
    print_success(
        f"Policy added: {red('deny')} network {args.resources}"
    )
    return 0


def _cmd_policy_rm(svc: SbxService, args: argparse.Namespace) -> int:
    svc.policy_remove(args.resources)
    print_success(f"Policy removed: {args.resources}")
    return 0


def _cmd_policy_log(svc: SbxService, args: argparse.Namespace) -> int:
    entries = svc.policy_log(sandbox_name=args.sandbox)

    if args.blocked:
        entries = [e for e in entries if e.blocked]

    if args.output_json:
        data = [
            {
                "sandbox": e.sandbox,
                "host": e.host,
                "proxy": e.proxy,
                "rule": e.rule,
                "count": e.count,
                "blocked": e.blocked,
                "last_seen": e.last_seen,
            }
            for e in entries
        ]
        print(json.dumps(data, indent=2))
        return 0

    if not entries:
        print_info("No policy log entries found.")
        return 0

    allowed = [e for e in entries if not e.blocked]
    blocked = [e for e in entries if e.blocked]

    if allowed:
        print_section("Allowed requests")
        rows = [
            [e.sandbox, e.host, e.proxy, e.rule, str(e.count)]
            for e in allowed
        ]
        print_table(
            ["SANDBOX", "HOST", "PROXY", "RULE", "COUNT"],
            rows,
        )

    if blocked:
        print_section("Blocked requests")
        rows = [
            [e.sandbox, e.host, e.proxy, e.rule, str(e.count)]
            for e in blocked
        ]
        print_table(
            ["SANDBOX", "HOST", "PROXY", "RULE", "COUNT"],
            rows,
        )

    return 0


# -- Port Commands --


def _dispatch_ports(svc: SbxService, args: argparse.Namespace) -> int:
    if not args.ports_cmd:
        print_error("Usage: sbx-ui ports {ls|publish|unpublish}")
        return 1

    if args.ports_cmd == "ls":
        return _cmd_ports_ls(svc, args)
    elif args.ports_cmd == "publish":
        return _cmd_ports_publish(svc, args)
    elif args.ports_cmd == "unpublish":
        return _cmd_ports_unpublish(svc, args)
    return 1


def _cmd_ports_ls(svc: SbxService, args: argparse.Namespace) -> int:
    ports = svc.ports_list(args.name)

    if args.output_json:
        data = [
            {
                "host_port": p.host_port,
                "sandbox_port": p.sandbox_port,
                "protocol": p.protocol_type,
            }
            for p in ports
        ]
        print(json.dumps(data, indent=2))
        return 0

    if not ports:
        print_info(f"No published ports for '{args.name}'.")
        return 0

    rows = [
        ["127.0.0.1", str(p.host_port), str(p.sandbox_port), p.protocol_type]
        for p in ports
    ]
    print_table(["HOST IP", "HOST PORT", "SANDBOX PORT", "PROTOCOL"], rows)
    return 0


def _parse_port_spec(spec: str) -> tuple[int, int]:
    """Parse HOST_PORT:SANDBOX_PORT spec."""
    parts = spec.split(":")
    if len(parts) != 2:
        raise SbxServiceError(
            f"Invalid port spec '{spec}'. Expected HOST_PORT:SANDBOX_PORT"
        )
    try:
        return int(parts[0]), int(parts[1])
    except ValueError:
        raise SbxServiceError(
            f"Invalid port numbers in '{spec}'. Expected integers."
        )


def _cmd_ports_publish(svc: SbxService, args: argparse.Namespace) -> int:
    host_port, sbx_port = _parse_port_spec(args.spec)
    svc.ports_publish(args.name, host_port, sbx_port)
    print_success(
        f"Published 127.0.0.1:{host_port} → {sbx_port}/tcp"
    )
    return 0


def _cmd_ports_unpublish(svc: SbxService, args: argparse.Namespace) -> int:
    host_port, sbx_port = _parse_port_spec(args.spec)
    svc.ports_unpublish(args.name, host_port, sbx_port)
    print_success(
        f"Unpublished 127.0.0.1:{host_port} → {sbx_port}/tcp"
    )
    return 0


# -- Environment Variable Commands --


def _dispatch_env(svc: SbxService, args: argparse.Namespace) -> int:
    if not args.env_cmd:
        print_error("Usage: sbx-ui env {ls|set|rm}")
        return 1

    if args.env_cmd == "ls":
        return _cmd_env_ls(svc, args)
    elif args.env_cmd == "set":
        return _cmd_env_set(svc, args)
    elif args.env_cmd == "rm":
        return _cmd_env_rm(svc, args)
    return 1


def _cmd_env_ls(svc: SbxService, args: argparse.Namespace) -> int:
    env_vars = svc.env_list(args.name)

    if args.output_json:
        data = [{"key": v.key, "value": v.value} for v in env_vars]
        print(json.dumps(data, indent=2))
        return 0

    if not env_vars:
        print_info(f"No managed environment variables for '{args.name}'.")
        return 0

    rows = [[v.key, v.value] for v in env_vars]
    print_table(["KEY", "VALUE"], rows, color_cols={0: cyan})
    return 0


def _cmd_env_set(svc: SbxService, args: argparse.Namespace) -> int:
    from .models import is_valid_env_key

    if not is_valid_env_key(args.key):
        print_error(
            f"Invalid env var key '{args.key}'. "
            "Must match [A-Za-z_][A-Za-z0-9_]*"
        )
        return 1
    svc.env_set(args.name, args.key, args.value)
    print_success(f"Set {cyan(args.key)}={args.value}")
    return 0


def _cmd_env_rm(svc: SbxService, args: argparse.Namespace) -> int:
    svc.env_remove(args.name, args.key)
    print_success(f"Removed {cyan(args.key)}")
    return 0
