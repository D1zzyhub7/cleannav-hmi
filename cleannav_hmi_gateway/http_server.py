"""Small standard-library HTTP server for the CleanNav HMI contract."""

from __future__ import annotations

import json
import math
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread, current_thread
from urllib.parse import urlsplit

from .j6_hil_client import SubmissionResult


COMMAND_ID_PATTERN = re.compile(r'^[A-Za-z0-9._:-]+$')
MAX_BODY_BYTES = 16 * 1024
MAX_VALID_FOR_MS = 86_400_000


class HttpValidationError(ValueError):
    """Raised for a malformed HTTP transport request."""


def _confirmation_value(body: dict) -> bool:
    """Read canonical confirmation with a temporary legacy alias."""
    canonical = body.get('user_confirmed')
    legacy = body.get('safety_confirmed')
    if canonical is not None and type(canonical) is not bool:
        raise HttpValidationError('user_confirmed must be bool')
    if legacy is not None and type(legacy) is not bool:
        raise HttpValidationError('safety_confirmed must be bool')
    if canonical is not None and legacy is not None and canonical != legacy:
        raise HttpValidationError(
            'user_confirmed and safety_confirmed conflict')
    return canonical if canonical is not None else (legacy or False)


def validate_task_payload(body: object, *, reset: bool = False) -> dict:
    """Validate HTTP shape without applying Task Catalog policy."""
    if not isinstance(body, dict):
        raise HttpValidationError('JSON body must be an object')
    command_id = body.get('command_id')
    if (
        not isinstance(command_id, str)
        or not command_id
        or len(command_id) > 128
        or COMMAND_ID_PATTERN.fullmatch(command_id) is None
    ):
        raise HttpValidationError('command_id is invalid')

    if reset:
        task_id = 7
    else:
        task_id = body.get('task_id')
        if (
            isinstance(task_id, bool)
            or not isinstance(task_id, int)
            or not 0 <= task_id <= 65535
        ):
            raise HttpValidationError('task_id is invalid')

    valid_for_ms = body.get('valid_for_ms', 10_000)
    if (
        isinstance(valid_for_ms, bool)
        or not isinstance(valid_for_ms, (int, float))
        or not math.isfinite(float(valid_for_ms))
        or float(valid_for_ms) <= 0.0
        or float(valid_for_ms) > MAX_VALID_FOR_MS
    ):
        raise HttpValidationError('valid_for_ms is invalid')

    timestamp_ms = body.get('timestamp_ms')
    if timestamp_ms is not None and (
        isinstance(timestamp_ms, bool)
        or not isinstance(timestamp_ms, (int, float))
        or not math.isfinite(float(timestamp_ms))
    ):
        raise HttpValidationError('timestamp_ms is invalid')

    user_confirmed = _confirmation_value(body)
    if reset and not user_confirmed:
        raise HttpValidationError('emergency reset requires confirmation')
    return {
        'command_id': command_id,
        'task_id': task_id,
        'valid_for_ms': float(valid_for_ms),
        'user_confirmed': user_confirmed,
        'endpoint': '/api/emergency-reset' if reset else '/api/tasks',
    }


class _GatewayServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = False

    def __init__(self, address, handler, gateway):
        super().__init__(address, handler)
        self.gateway = gateway


class _RequestHandler(BaseHTTPRequestHandler):
    server: _GatewayServer

    def log_message(self, format, *args):
        """Avoid logging request headers that could contain credentials."""
        return

    def _authorized(self) -> bool:
        token = self.server.gateway.access_token
        if not token:
            return True
        return self.headers.get('Authorization') == f'Bearer {token}'

    def _json_response(self, status: int, body: dict) -> None:
        encoded = json.dumps(body, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        if not self._authorized():
            self._json_response(401, {'error': 'unauthorized'})
            return
        path = urlsplit(self.path).path
        if path == '/api/state':
            self._json_response(200, self.server.gateway.state_provider())
            return
        if path == '/api/map':
            provider = self.server.gateway.map_provider
            map_snapshot = provider() if provider is not None else None
            if map_snapshot is None:
                self._json_response(503, {
                    'ok': False,
                    'available': False,
                    'error': 'RTAB-Map OccupancyGrid is unavailable',
                })
                return
            self._json_response(200, map_snapshot)
            return
        self._json_response(404, {'error': 'not found'})

    def do_POST(self):
        if not self._authorized():
            self._json_response(401, {'error': 'unauthorized'})
            return
        path = urlsplit(self.path).path
        if path not in ('/api/tasks', '/api/emergency-reset'):
            self._json_response(404, {'error': 'not found'})
            return
        length = self.headers.get('Content-Length')
        try:
            size = int(length) if length is not None else -1
        except ValueError:
            size = -1
        if size < 0 or size > MAX_BODY_BYTES:
            self._json_response(400, {'error': 'request body is too large'})
            return
        try:
            body = json.loads(self.rfile.read(size).decode('utf-8'))
            command = validate_task_payload(
                body,
                reset=path == '/api/emergency-reset',
            )
        except (
            UnicodeDecodeError,
            json.JSONDecodeError,
            HttpValidationError,
        ) as exc:
            self._json_response(400, {'error': str(exc)})
            return
        result = self.server.gateway.submit_command(command)
        if isinstance(result, SubmissionResult):
            self._json_response(result.status_code, result.body)
            return
        if not result:
            self._json_response(503, {'error': 'command queue is full'})
            return
        self._json_response(202, {
            'submitted': True,
            'command_id': command['command_id'],
            'message': 'submitted to Mission Manager',
        })


class GatewayHttpServer:
    """Own a non-daemon HTTP thread and shut it down deterministically."""

    def __init__(
        self,
        host,
        port,
        access_token,
        submit_command,
        state_provider,
        map_provider=None,
    ):
        self.host = host
        self.port = int(port)
        self.access_token = access_token
        self.submit_command = submit_command
        self.state_provider = state_provider
        self.map_provider = map_provider
        self._server = None
        self._thread: Thread | None = None

    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def start(self) -> None:
        if self.running:
            return
        self._server = _GatewayServer(
            (self.host, self.port),
            _RequestHandler,
            self,
        )
        self._thread = Thread(
            target=self._server.serve_forever,
            name='cleannav-hmi-http',
            daemon=False,
        )
        self._thread.start()

    def shutdown(self) -> None:
        server, thread = self._server, self._thread
        self._server = None
        self._thread = None
        if server is not None:
            server.shutdown()
            server.server_close()
        if thread is not None and thread is not current_thread():
            thread.join(timeout=5.0)


__all__ = [
    'GatewayHttpServer',
    'HttpValidationError',
    'MAX_VALID_FOR_MS',
    'validate_task_payload',
]
