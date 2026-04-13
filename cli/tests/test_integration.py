"""Integration tests using mock-sbx CLI emulator.

These tests exercise the full service layer by invoking the mock-sbx
bash script, mirroring the Swift UI/E2E tests approach.
"""

import os
import shutil
import tempfile
import unittest
from pathlib import Path

# Resolve paths
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
TOOLS_DIR = PROJECT_ROOT / "tools"

from sbx_ui_cli.models import (
    DockerNotRunningError,
    InvalidNameError,
    PortConflictError,
    SandboxNotFoundError,
    SandboxStatus,
    SbxServiceError,
)
from sbx_ui_cli.service import SbxService


def _make_service() -> tuple[SbxService, str]:
    """Create a service pointing to mock-sbx with a fresh state dir."""
    state_dir = tempfile.mkdtemp(prefix="mock-sbx-test-")
    env = os.environ.copy()
    env["SBX_MOCK_STATE_DIR"] = state_dir
    env["PATH"] = f"{TOOLS_DIR}:{env.get('PATH', '/usr/bin:/bin')}"
    # Patch os.environ for subprocess calls
    os.environ["SBX_MOCK_STATE_DIR"] = state_dir
    os.environ["PATH"] = env["PATH"]
    sbx_path = str(TOOLS_DIR / "sbx")
    return SbxService(sbx_command=sbx_path), state_dir


class IntegrationTestBase(unittest.TestCase):
    """Base class that sets up mock-sbx environment."""

    def setUp(self):
        self._orig_env = {
            "PATH": os.environ.get("PATH"),
            "SBX_MOCK_STATE_DIR": os.environ.get("SBX_MOCK_STATE_DIR"),
        }
        self.svc, self.state_dir = _make_service()

    def tearDown(self):
        # Restore env
        for key, val in self._orig_env.items():
            if val is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = val
        # Clean up state dir
        shutil.rmtree(self.state_dir, ignore_errors=True)


class TestSandboxLifecycle(IntegrationTestBase):
    def test_list_empty(self):
        sandboxes = self.svc.list()
        self.assertEqual(len(sandboxes), 0)

    def test_create_and_list(self):
        sb = self.svc.create("claude", "/tmp/test-project", name="test-sb")
        self.assertEqual(sb.name, "test-sb")
        self.assertEqual(sb.agent, "claude")
        self.assertEqual(sb.status, SandboxStatus.RUNNING)

        sandboxes = self.svc.list()
        self.assertEqual(len(sandboxes), 1)
        self.assertEqual(sandboxes[0].name, "test-sb")

    def test_create_invalid_name(self):
        with self.assertRaises(InvalidNameError):
            self.svc.create("claude", "/tmp/project", name="INVALID")

    def test_stop_sandbox(self):
        self.svc.create("claude", "/tmp/project", name="stop-test")
        self.svc.stop("stop-test")
        sandboxes = self.svc.list()
        stopped = [s for s in sandboxes if s.name == "stop-test"]
        self.assertEqual(len(stopped), 1)
        self.assertEqual(stopped[0].status, SandboxStatus.STOPPED)

    def test_remove_sandbox(self):
        self.svc.create("claude", "/tmp/project", name="rm-test")
        self.svc.rm("rm-test")
        sandboxes = self.svc.list()
        self.assertEqual(len(sandboxes), 0)

    def test_stop_nonexistent(self):
        with self.assertRaises(SandboxNotFoundError):
            self.svc.stop("nonexistent")

    def test_rm_nonexistent(self):
        with self.assertRaises(SandboxNotFoundError):
            self.svc.rm("nonexistent")


class TestPolicies(IntegrationTestBase):
    def test_list_default_policies(self):
        rules = self.svc.policy_list()
        # mock-sbx seeds 10 default allow rules
        self.assertGreater(len(rules), 0)
        # All defaults should be allow
        for r in rules:
            self.assertEqual(r.decision.value, "allow")

    def test_allow_policy(self):
        rule = self.svc.policy_allow("new.example.com")
        self.assertEqual(rule.resources, "new.example.com")
        self.assertEqual(rule.decision.value, "allow")

    def test_deny_policy(self):
        rule = self.svc.policy_deny("evil.example.com")
        self.assertEqual(rule.resources, "evil.example.com")
        self.assertEqual(rule.decision.value, "deny")

    def test_remove_policy(self):
        self.svc.policy_allow("removable.example.com")
        rules_before = self.svc.policy_list()
        count_before = len(rules_before)

        self.svc.policy_remove("removable.example.com")
        rules_after = self.svc.policy_list()
        self.assertEqual(len(rules_after), count_before - 1)

    def test_policy_log(self):
        entries = self.svc.policy_log()
        # mock-sbx seeds policy log entries
        self.assertGreater(len(entries), 0)
        blocked = [e for e in entries if e.blocked]
        allowed = [e for e in entries if not e.blocked]
        self.assertGreater(len(blocked), 0)
        self.assertGreater(len(allowed), 0)

    def test_policy_log_filter_sandbox(self):
        entries = self.svc.policy_log(sandbox_name="claude-myproject")
        for e in entries:
            self.assertEqual(e.sandbox, "claude-myproject")


class TestPorts(IntegrationTestBase):
    def test_ports_list_empty(self):
        self.svc.create("claude", "/tmp/project", name="port-test")
        ports = self.svc.ports_list("port-test")
        self.assertEqual(len(ports), 0)

    def test_publish_and_list(self):
        self.svc.create("claude", "/tmp/project", name="port-test")
        mapping = self.svc.ports_publish("port-test", 8080, 3000)
        self.assertEqual(mapping.host_port, 8080)
        self.assertEqual(mapping.sandbox_port, 3000)

        ports = self.svc.ports_list("port-test")
        self.assertEqual(len(ports), 1)
        self.assertEqual(ports[0].host_port, 8080)

    def test_unpublish(self):
        self.svc.create("claude", "/tmp/project", name="port-test")
        self.svc.ports_publish("port-test", 8080, 3000)
        self.svc.ports_unpublish("port-test", 8080, 3000)
        ports = self.svc.ports_list("port-test")
        self.assertEqual(len(ports), 0)


class TestEnvironmentVariables(IntegrationTestBase):
    def test_env_list_empty(self):
        self.svc.create("claude", "/tmp/project", name="env-test")
        env_vars = self.svc.env_list("env-test")
        self.assertEqual(len(env_vars), 0)

    def test_env_set_and_list(self):
        self.svc.create("claude", "/tmp/project", name="env-test")
        self.svc.env_set("env-test", "MY_KEY", "my_value")
        env_vars = self.svc.env_list("env-test")
        self.assertEqual(len(env_vars), 1)
        self.assertEqual(env_vars[0].key, "MY_KEY")
        self.assertEqual(env_vars[0].value, "my_value")

    def test_env_set_multiple(self):
        self.svc.create("claude", "/tmp/project", name="env-test")
        self.svc.env_set("env-test", "KEY1", "val1")
        self.svc.env_set("env-test", "KEY2", "val2")
        env_vars = self.svc.env_list("env-test")
        self.assertEqual(len(env_vars), 2)
        keys = {v.key for v in env_vars}
        self.assertIn("KEY1", keys)
        self.assertIn("KEY2", keys)

    def test_env_update_existing(self):
        self.svc.create("claude", "/tmp/project", name="env-test")
        self.svc.env_set("env-test", "MY_KEY", "old_value")
        self.svc.env_set("env-test", "MY_KEY", "new_value")
        env_vars = self.svc.env_list("env-test")
        self.assertEqual(len(env_vars), 1)
        self.assertEqual(env_vars[0].value, "new_value")

    def test_env_remove(self):
        self.svc.create("claude", "/tmp/project", name="env-test")
        self.svc.env_set("env-test", "MY_KEY", "my_value")
        self.svc.env_remove("env-test", "MY_KEY")
        env_vars = self.svc.env_list("env-test")
        self.assertEqual(len(env_vars), 0)


class TestCLIMain(IntegrationTestBase):
    """Test the CLI main entry point with mock-sbx."""

    def _run_cli(self, argv: list[str]) -> int:
        from sbx_ui_cli.main import main
        return main(argv)

    def test_ls_empty(self):
        rc = self._run_cli(["ls"])
        self.assertEqual(rc, 0)

    def test_ls_json_empty(self):
        rc = self._run_cli(["--json", "ls"])
        self.assertEqual(rc, 0)

    def test_help(self):
        # --help raises SystemExit(0)
        with self.assertRaises(SystemExit) as cm:
            self._run_cli(["--help"])
        self.assertEqual(cm.exception.code, 0)

    def test_version(self):
        with self.assertRaises(SystemExit) as cm:
            self._run_cli(["--version"])
        self.assertEqual(cm.exception.code, 0)

    def test_policy_ls(self):
        rc = self._run_cli(["policy", "ls"])
        self.assertEqual(rc, 0)

    def test_policy_log(self):
        rc = self._run_cli(["policy", "log"])
        self.assertEqual(rc, 0)

    def test_no_command_shows_help(self):
        rc = self._run_cli([])
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
