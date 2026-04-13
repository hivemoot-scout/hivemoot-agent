"""Tests for hivemoot-agent CLI entrypoints."""

import io
import os
import sys
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from hivemoot_agent.__main__ import _cmd_doctor, _resolve_doctor_provider


def test_resolve_doctor_provider_prefers_agent_provider():
    env = {"AGENT_PROVIDER": "codex", "DOCKER_PROVIDER": "all"}
    with patch.dict(os.environ, env, clear=True):
        assert _resolve_doctor_provider() == "codex"


def test_resolve_doctor_provider_falls_back_to_baked_provider():
    env = {"DOCKER_PROVIDER": "gemini"}
    with patch.dict(os.environ, env, clear=True):
        assert _resolve_doctor_provider() == "gemini"


def test_resolve_doctor_provider_defaults_to_claude():
    with patch.dict(os.environ, {}, clear=True):
        assert _resolve_doctor_provider() == "claude"


def test_cmd_doctor_checks_configured_provider_binary():
    env = {"AGENT_PROVIDER": "codex"}
    with patch.dict(os.environ, env, clear=True):
        with patch("shutil.which", side_effect=lambda name: f"/usr/bin/{name}"):
            stdout = io.StringIO()
            stderr = io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                code = _cmd_doctor(None)

    assert code == 0
    assert "codex: /usr/bin/codex" in stdout.getvalue()
    assert "python3: /usr/bin/python3" in stdout.getvalue()
    assert stderr.getvalue() == ""


def test_cmd_doctor_reports_missing_provider_binary():
    env = {"AGENT_PROVIDER": "opencode"}

    def fake_which(name: str) -> str | None:
        return None if name == "opencode" else f"/usr/bin/{name}"

    with patch.dict(os.environ, env, clear=True):
        with patch("shutil.which", side_effect=fake_which):
            stdout = io.StringIO()
            stderr = io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                code = _cmd_doctor(None)

    assert code == 1
    assert "python3: /usr/bin/python3" in stdout.getvalue()
    assert "opencode: not found" in stderr.getvalue()


def test_cmd_doctor_rejects_unknown_provider():
    env = {"AGENT_PROVIDER": "unknown"}
    with patch.dict(os.environ, env, clear=True):
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            code = _cmd_doctor(None)

    assert code == 1
    assert stdout.getvalue() == ""
    assert "unsupported AGENT_PROVIDER 'unknown'" in stderr.getvalue()
