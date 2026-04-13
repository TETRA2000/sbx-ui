"""Unit tests for data models and validation."""

import unittest

from sbx_ui_cli.models import (
    EnvVar,
    InvalidNameError,
    PortMapping,
    Sandbox,
    SandboxNotFoundError,
    SandboxStatus,
    is_valid_env_key,
    is_valid_name,
)


class TestValidation(unittest.TestCase):
    def test_valid_sandbox_names(self):
        self.assertTrue(is_valid_name("my-sandbox"))
        self.assertTrue(is_valid_name("claude-project"))
        self.assertTrue(is_valid_name("test123"))
        self.assertTrue(is_valid_name("a"))

    def test_invalid_sandbox_names(self):
        self.assertFalse(is_valid_name(""))
        self.assertFalse(is_valid_name("-leading-hyphen"))
        self.assertFalse(is_valid_name("UPPERCASE"))
        self.assertFalse(is_valid_name("has spaces"))
        self.assertFalse(is_valid_name("has_underscore"))

    def test_valid_env_keys(self):
        self.assertTrue(is_valid_env_key("MY_VAR"))
        self.assertTrue(is_valid_env_key("_PRIVATE"))
        self.assertTrue(is_valid_env_key("API_KEY_2"))
        self.assertTrue(is_valid_env_key("a"))

    def test_invalid_env_keys(self):
        self.assertFalse(is_valid_env_key(""))
        self.assertFalse(is_valid_env_key("2STARTS_WITH_NUM"))
        self.assertFalse(is_valid_env_key("has-hyphen"))
        self.assertFalse(is_valid_env_key("has space"))


class TestModels(unittest.TestCase):
    def test_sandbox_id(self):
        s = Sandbox(
            name="test", agent="claude",
            status=SandboxStatus.RUNNING, workspace="/tmp"
        )
        self.assertEqual(s.id, "test")

    def test_port_mapping_id(self):
        p = PortMapping(host_port=8080, sandbox_port=3000)
        self.assertEqual(p.id, "8080-3000")

    def test_env_var_id(self):
        v = EnvVar(key="MY_KEY", value="my_value")
        self.assertEqual(v.id, "MY_KEY")

    def test_sandbox_status_values(self):
        self.assertEqual(SandboxStatus("running"), SandboxStatus.RUNNING)
        self.assertEqual(SandboxStatus("stopped"), SandboxStatus.STOPPED)

    def test_error_messages(self):
        e = SandboxNotFoundError("test-sb")
        self.assertIn("test-sb", str(e))

        e = InvalidNameError("BAD")
        self.assertIn("BAD", str(e))


if __name__ == "__main__":
    unittest.main()
