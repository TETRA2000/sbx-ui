"""Unit tests for CLI output parsers."""

import json
import unittest

from sbx_ui_cli.models import PolicyDecision, SandboxStatus
from sbx_ui_cli.parser import (
    MANAGED_END,
    MANAGED_START,
    parse_managed_env_vars,
    parse_policy_list,
    parse_policy_log_json,
    parse_ports_json,
    parse_sandbox_list_json,
    rebuild_persistent_sh,
)


class TestParseSandboxListJson(unittest.TestCase):
    def test_parse_running_sandbox(self):
        data = {
            "sandboxes": [
                {
                    "name": "test-sb",
                    "agent": "claude",
                    "status": "running",
                    "ports": [
                        {
                            "host_ip": "127.0.0.1",
                            "host_port": 8080,
                            "sandbox_port": 3000,
                            "protocol": "tcp",
                        }
                    ],
                    "workspaces": ["/home/user/project"],
                }
            ]
        }
        sandboxes = parse_sandbox_list_json(json.dumps(data))
        self.assertEqual(len(sandboxes), 1)
        s = sandboxes[0]
        self.assertEqual(s.name, "test-sb")
        self.assertEqual(s.agent, "claude")
        self.assertEqual(s.status, SandboxStatus.RUNNING)
        self.assertEqual(s.workspace, "/home/user/project")
        self.assertEqual(len(s.ports), 1)
        self.assertEqual(s.ports[0].host_port, 8080)
        self.assertEqual(s.ports[0].sandbox_port, 3000)

    def test_parse_sandbox_no_ports(self):
        data = {
            "sandboxes": [
                {
                    "name": "test",
                    "agent": "claude",
                    "status": "stopped",
                    "workspaces": ["/tmp"],
                }
            ]
        }
        sandboxes = parse_sandbox_list_json(json.dumps(data))
        self.assertEqual(len(sandboxes), 1)
        self.assertEqual(sandboxes[0].ports, [])
        self.assertEqual(sandboxes[0].status, SandboxStatus.STOPPED)

    def test_parse_empty_list(self):
        data = {"sandboxes": []}
        self.assertEqual(parse_sandbox_list_json(json.dumps(data)), [])

    def test_parse_multiple_sandboxes(self):
        data = {
            "sandboxes": [
                {"name": "a", "agent": "claude", "status": "running", "workspaces": ["/a"]},
                {"name": "b", "agent": "claude", "status": "stopped", "workspaces": ["/b"]},
            ]
        }
        sandboxes = parse_sandbox_list_json(json.dumps(data))
        self.assertEqual(len(sandboxes), 2)
        self.assertEqual(sandboxes[0].name, "a")
        self.assertEqual(sandboxes[1].name, "b")


class TestParsePolicyList(unittest.TestCase):
    def test_parse_policy_table(self):
        output = (
            "NAME                                         TYPE      DECISION   RESOURCES\n"
            "default-allow-all                            network   allow      **\n"
            "local:abc-123                                network   deny       evil.com\n"
        )
        rules = parse_policy_list(output)
        self.assertEqual(len(rules), 2)
        self.assertEqual(rules[0].id, "default-allow-all")
        self.assertEqual(rules[0].decision, PolicyDecision.ALLOW)
        self.assertEqual(rules[0].resources, "**")
        self.assertEqual(rules[1].decision, PolicyDecision.DENY)
        self.assertEqual(rules[1].resources, "evil.com")

    def test_parse_policy_table_with_blank_lines(self):
        output = (
            "NAME                                         TYPE      DECISION   RESOURCES\n"
            "default-allow-all                            network   allow      **\n"
            "\n"
            "local:abc-123                                network   deny       evil.com\n"
        )
        rules = parse_policy_list(output)
        self.assertEqual(len(rules), 2)

    def test_empty_output(self):
        self.assertEqual(parse_policy_list(""), [])
        self.assertEqual(parse_policy_list("NAME  TYPE  DECISION  RESOURCES\n"), [])


class TestParsePolicyLogJson(unittest.TestCase):
    def test_parse_mixed_entries(self):
        data = {
            "allowed_hosts": [
                {
                    "host": "api.example.com",
                    "vm_name": "test-sb",
                    "proxy_type": "forward",
                    "rule": "domain-allowed",
                    "last_seen": "2026-04-04T10:00:00+00:00",
                    "since": "2026-04-04T10:00:00+00:00",
                    "count_since": 5,
                }
            ],
            "blocked_hosts": [
                {
                    "host": "evil.com",
                    "vm_name": "test-sb",
                    "proxy_type": "forward",
                    "rule": "user-denied",
                    "last_seen": "2026-04-04T10:01:00+00:00",
                    "since": "2026-04-04T10:01:00+00:00",
                    "count_since": 3,
                }
            ],
        }
        entries = parse_policy_log_json(json.dumps(data))
        self.assertEqual(len(entries), 2)
        allowed = [e for e in entries if not e.blocked]
        blocked = [e for e in entries if e.blocked]
        self.assertEqual(len(allowed), 1)
        self.assertEqual(len(blocked), 1)
        self.assertEqual(allowed[0].host, "api.example.com")
        self.assertEqual(allowed[0].count, 5)
        self.assertEqual(blocked[0].host, "evil.com")


class TestParsePortsJson(unittest.TestCase):
    def test_parse_ports(self):
        data = [
            {"host_ip": "127.0.0.1", "host_port": 8080, "sandbox_port": 3000, "protocol": "tcp"},
            {"host_ip": "127.0.0.1", "host_port": 9090, "sandbox_port": 4000, "protocol": "tcp"},
        ]
        ports = parse_ports_json(json.dumps(data))
        self.assertEqual(len(ports), 2)
        self.assertEqual(ports[0].host_port, 8080)
        self.assertEqual(ports[1].sandbox_port, 4000)

    def test_empty_ports(self):
        self.assertEqual(parse_ports_json("[]"), [])


class TestEnvVarParsing(unittest.TestCase):
    def test_parse_managed_section(self):
        content = (
            "# user stuff\n"
            "export PATH=/usr/bin\n"
            "\n"
            f"{MANAGED_START}\n"
            "export MY_KEY=my_value\n"
            "export API_KEY=secret123\n"
            f"{MANAGED_END}\n"
            "\n"
            "# more user stuff\n"
        )
        vars = parse_managed_env_vars(content)
        self.assertEqual(len(vars), 2)
        self.assertEqual(vars[0].key, "MY_KEY")
        self.assertEqual(vars[0].value, "my_value")
        self.assertEqual(vars[1].key, "API_KEY")
        self.assertEqual(vars[1].value, "secret123")

    def test_no_managed_section(self):
        content = "export PATH=/usr/bin\n"
        self.assertEqual(parse_managed_env_vars(content), [])

    def test_empty_content(self):
        self.assertEqual(parse_managed_env_vars(""), [])

    def test_rebuild_preserves_user_content(self):
        from sbx_ui_cli.models import EnvVar as EV
        existing = (
            "# user content\n"
            "export PATH=/usr/bin\n"
            "\n"
            f"{MANAGED_START}\n"
            "export OLD_VAR=old\n"
            f"{MANAGED_END}\n"
            "\n"
            "# after content\n"
        )
        new_vars = [EV(key="NEW_VAR", value="new")]
        result = rebuild_persistent_sh(existing, new_vars)
        self.assertIn("# user content", result)
        self.assertIn("export PATH=/usr/bin", result)
        self.assertIn("export NEW_VAR=new", result)
        self.assertNotIn("OLD_VAR", result)
        self.assertIn("# after content", result)

    def test_rebuild_empty_vars_removes_section(self):
        existing = (
            f"{MANAGED_START}\n"
            "export KEY=val\n"
            f"{MANAGED_END}\n"
        )
        result = rebuild_persistent_sh(existing, [])
        self.assertEqual(result, "")


if __name__ == "__main__":
    unittest.main()
