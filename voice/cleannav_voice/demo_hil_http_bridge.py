#!/usr/bin/env python3
"""Competition-only Voice TaskCommand to J6 HTTP HIL adapter.

The production Voice pipeline still ends at the formal ``TaskCommand``. This
module only adds the Demo transport to J6; HTTP is not part of ASR or intent
parsing, and future J6-native Voice should not depend on this PC bridge.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from typing import Mapping

import rclpy
from rclpy.node import Node
from rclpy.qos import (
    QoSDurabilityPolicy,
    QoSHistoryPolicy,
    QoSProfile,
    QoSReliabilityPolicy,
)

from cleannav_interfaces.msg import TaskCommand


DEFAULT_J6_BASE_URL = "http://192.168.8.10:18081"
J6_BASE_URL_ENV = "CLEANNAV_J6_HIL_BASE_URL"
DEFAULT_HTTP_TIMEOUT_SEC = 3.0
HIL_TASK_URL = f"{DEFAULT_J6_BASE_URL}/task"


def resolve_j6_base_url(
    cli_value: str | None = None,
    *,
    environ: Mapping[str, str] | None = None,
) -> str:
    """Resolve CLI, environment and backwards-compatible Demo URL values."""
    environment = os.environ if environ is None else environ
    value = cli_value or environment.get(J6_BASE_URL_ENV) or DEFAULT_J6_BASE_URL
    if not isinstance(value, str) or not value.startswith("http://"):
        raise ValueError("J6 HIL base URL must be a non-empty http:// URL")
    return value.rstrip("/")


def resolve_hil_task_url(
    cli_value: str | None = None,
    *,
    environ: Mapping[str, str] | None = None,
) -> str:
    """Resolve the J6 HIL task endpoint from the configured base URL."""
    return f"{resolve_j6_base_url(cli_value, environ=environ)}/task"


def build_task_payload(msg: TaskCommand) -> dict:
    """Serialize one formal Voice TaskCommand without changing its fields."""
    valid_for_sec = (
        float(msg.valid_for.sec)
        + float(msg.valid_for.nanosec) / 1_000_000_000.0
    )
    return {
        "task_id": int(msg.task_id),
        "source": int(msg.source),
        "command_id": msg.command_id,
        "confidence": float(msg.confidence),
        "raw_text": msg.raw_text,
        "user_confirmed": bool(msg.user_confirmed),
        "valid_for_sec": valid_for_sec,
    }


def _parse_cli_args(args: list[str]) -> tuple[argparse.Namespace, list[str]]:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--j6-base-url")
    return parser.parse_known_args(args)


class VoiceHilHttpBridge(Node):

    def __init__(
        self,
        *,
        base_url: str | None = None,
        timeout_sec: float = DEFAULT_HTTP_TIMEOUT_SEC,
    ):
        super().__init__("cleannav_voice_hil_http_bridge")
        self._hil_task_url = resolve_hil_task_url(base_url)
        if timeout_sec <= 0.0:
            raise ValueError("timeout_sec must be > 0")
        self._http_timeout_sec = float(timeout_sec)

        qos = QoSProfile(
            history=QoSHistoryPolicy.KEEP_LAST,
            depth=10,
            reliability=QoSReliabilityPolicy.RELIABLE,
            durability=QoSDurabilityPolicy.VOLATILE,
        )

        self.create_subscription(
            TaskCommand,
            "/cleannav/hmi/task_command",
            self._on_task_command,
            qos,
        )

        self.get_logger().info(
            "VOICE_HIL_HTTP_BRIDGE_READY "
            f"url={self._hil_task_url} "
            "mode=COMPETITION_HIL_ONLY"
        )

    def _on_task_command(self, msg: TaskCommand) -> None:
        if msg.source != TaskCommand.SOURCE_VOICE:
            return

        payload = build_task_payload(msg)

        request = urllib.request.Request(
            self._hil_task_url,
            data=json.dumps(
                payload,
                ensure_ascii=False,
            ).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(
                request,
                timeout=self._http_timeout_sec,
            ) as response:
                status = int(response.status)
                body = response.read().decode("utf-8")
                if not 200 <= status < 300:
                    raise RuntimeError(f"J6 HIL returned HTTP {status}")

                self.get_logger().info(
                    "HIL_HTTP_TASK_SENT "
                    f"task_id={msg.task_id} "
                    f"source={msg.source} "
                    f"command_id={msg.command_id} "
                    f"status={status} "
                    f"response={body}"
                )

        except (
            urllib.error.URLError,
            urllib.error.HTTPError,
            TimeoutError,
            RuntimeError,
        ) as exc:
            self.get_logger().error(
                "HIL_HTTP_TASK_FAILED "
                f"task_id={msg.task_id} "
                f"command_id={msg.command_id} "
                f"error={exc}"
            )


def main(args=None):
    cli_args = list(sys.argv[1:] if args is None else args)
    parsed_args, ros_args = _parse_cli_args(cli_args)
    rclpy.init(args=ros_args)
    node = VoiceHilHttpBridge(base_url=parsed_args.j6_base_url)

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()


__all__ = [
    "DEFAULT_J6_BASE_URL",
    "DEFAULT_HTTP_TIMEOUT_SEC",
    "HIL_TASK_URL",
    "J6_BASE_URL_ENV",
    "VoiceHilHttpBridge",
    "build_task_payload",
    "resolve_hil_task_url",
    "resolve_j6_base_url",
    "main",
]
