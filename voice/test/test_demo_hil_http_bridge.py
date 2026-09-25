"""Tests for the competition-only Voice HTTP HIL adapter."""

import json
import urllib.error

from cleannav_interfaces.msg import TaskCommand

import cleannav_voice.demo_hil_http_bridge as bridge_module
from cleannav_voice.demo_hil_http_bridge import (
    VoiceHilHttpBridge,
    build_task_payload,
    resolve_hil_task_url,
    resolve_j6_base_url,
)


class _Response:
    def __init__(self, status=202, body=None):
        self.status = status
        self._body = json.dumps(body or {"accepted_for_delivery": True})
        self.calls = 0

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        self.calls += 1
        return self._body.encode("utf-8")


class _Logger:
    def __init__(self):
        self.info_messages = []
        self.error_messages = []

    def info(self, message):
        self.info_messages.append(message)

    def error(self, message):
        self.error_messages.append(message)


def _message(source=TaskCommand.SOURCE_VOICE):
    message = TaskCommand()
    message.source = source
    message.task_id = 30
    message.command_id = "voice:demo-1"
    message.confidence = 0.95
    message.raw_text = "清扫最近的落叶"
    message.valid_for.sec = 60
    message.user_confirmed = False
    return message


def _bridge():
    bridge = VoiceHilHttpBridge.__new__(VoiceHilHttpBridge)
    bridge._hil_task_url = "http://j6.test:18081/task"
    bridge._http_timeout_sec = 3.0
    bridge.logger = _Logger()
    bridge.get_logger = lambda: bridge.logger
    return bridge


def test_endpoint_cli_precedes_environment_and_default(monkeypatch):
    monkeypatch.setenv("CLEANNAV_J6_HIL_BASE_URL", "http://env-j6:19081/")
    assert resolve_j6_base_url() == "http://env-j6:19081"
    assert resolve_hil_task_url("http://cli-j6:29081/") == (
        "http://cli-j6:29081/task"
    )
    monkeypatch.delenv("CLEANNAV_J6_HIL_BASE_URL")
    assert resolve_hil_task_url() == "http://192.168.8.10:18081/task"


def test_voice_payload_preserves_task_command_fields():
    payload = build_task_payload(_message())
    assert payload == {
        "task_id": 30,
        "source": TaskCommand.SOURCE_VOICE,
        "command_id": "voice:demo-1",
        "confidence": 0.95,
        "raw_text": "清扫最近的落叶",
        "user_confirmed": False,
        "valid_for_sec": 60.0,
    }


def test_only_voice_source_is_forwarded(monkeypatch):
    bridge = _bridge()
    calls = []

    def fake_urlopen(request, *, timeout):
        calls.append((request, timeout))
        return _Response()

    monkeypatch.setattr(bridge_module.urllib.request, "urlopen", fake_urlopen)
    bridge._on_task_command(_message(TaskCommand.SOURCE_APP))
    assert calls == []
    bridge._on_task_command(_message())
    assert len(calls) == 1
    assert calls[0][0].full_url.endswith("/task")
    assert json.loads(calls[0][0].data.decode("utf-8"))["task_id"] == 30


def test_http_202_is_accepted(monkeypatch):
    bridge = _bridge()
    response = _Response(202)
    monkeypatch.setattr(
        bridge_module.urllib.request,
        "urlopen",
        lambda request, *, timeout: response,
    )
    bridge._on_task_command(_message())
    assert any("status=202" in item for item in bridge.logger.info_messages)
    assert bridge.logger.error_messages == []


def test_non_2xx_timeout_and_connection_refused_are_logged(monkeypatch):
    bridge = _bridge()
    response = _Response(500)
    monkeypatch.setattr(
        bridge_module.urllib.request,
        "urlopen",
        lambda request, *, timeout: response,
    )
    bridge._on_task_command(_message())
    assert len(bridge.logger.error_messages) == 1

    bridge.logger.error_messages.clear()
    monkeypatch.setattr(
        bridge_module.urllib.request,
        "urlopen",
        lambda request, *, timeout: (_ for _ in ()).throw(TimeoutError()),
    )
    bridge._on_task_command(_message())
    assert len(bridge.logger.error_messages) == 1

    bridge.logger.error_messages.clear()
    monkeypatch.setattr(
        bridge_module.urllib.request,
        "urlopen",
        lambda request, *, timeout: (_ for _ in ()).throw(
            urllib.error.URLError("refused")
        ),
    )
    bridge._on_task_command(_message())
    assert len(bridge.logger.error_messages) == 1
