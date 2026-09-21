"""HTTP relay from the PC HMI gateway to the J6 HIL task ingress."""

from __future__ import annotations

from collections import OrderedDict
from copy import deepcopy
from dataclasses import dataclass
import json
from threading import Lock
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


SOURCE_APP = 2
DEFAULT_J6_BASE_URL = 'http://192.168.8.10:18081'


@dataclass(frozen=True)
class SubmissionResult:
    """HTTP response returned to the phone after J6 has replied."""

    status_code: int
    body: dict


class J6HilClient:
    """Small stdlib-only client for the already-running J6 HIL server."""

    def __init__(
        self,
        base_url: str = DEFAULT_J6_BASE_URL,
        *,
        timeout_sec: float = 2.5,
        opener: Callable = urlopen,
    ) -> None:
        self.base_url = str(base_url).rstrip('/')
        self.timeout_sec = float(timeout_sec)
        self._opener = opener

    def _json_request(
        self,
        path: str,
        *,
        method: str = 'GET',
        payload: dict | None = None,
    ) -> tuple[int, dict]:
        data = None
        headers = {'Accept': 'application/json'}
        if payload is not None:
            data = json.dumps(payload, ensure_ascii=False).encode('utf-8')
            headers['Content-Type'] = 'application/json; charset=utf-8'
        request = Request(
            f'{self.base_url}{path}',
            data=data,
            headers=headers,
            method=method,
        )
        with self._opener(request, timeout=self.timeout_sec) as response:
            raw = response.read()
            body = json.loads(raw.decode('utf-8')) if raw else {}
            if not isinstance(body, dict):
                raise ValueError('J6 response JSON must be an object')
            return int(response.status), body

    def health(self) -> dict:
        status, body = self._json_request('/health')
        if status != 200:
            raise RuntimeError(f'J6 /health returned HTTP {status}')
        return body

    def submit_task(self, payload: dict) -> tuple[int, dict]:
        return self._json_request('/task', method='POST', payload=payload)


class AppTaskRelay:
    """Force APP semantics and forward each command_id no more than once."""

    def __init__(
        self,
        client: J6HilClient,
        *,
        on_received: Callable[[dict], None] | None = None,
        on_forwarded: Callable[[dict, int], None] | None = None,
        max_records: int = 256,
    ) -> None:
        self._client = client
        self._on_received = on_received
        self._on_forwarded = on_forwarded
        self._max_records = max(1, int(max_records))
        self._lock = Lock()
        self._results: OrderedDict[
            str, tuple[tuple, SubmissionResult]
        ] = OrderedDict()

    @staticmethod
    def _fingerprint(command: dict) -> tuple:
        return (
            int(command['task_id']),
            float(command['valid_for_ms']),
            bool(command['user_confirmed']),
            str(command['endpoint']),
        )

    @staticmethod
    def _j6_payload(command: dict) -> dict:
        task_id = int(command['task_id'])
        return {
            'task_id': task_id,
            'source': SOURCE_APP,
            'command_id': command['command_id'],
            'confidence': 1.0,
            'raw_text': (
                '清扫最近的落叶'
                if task_id == 30
                else f'APP task {task_id}'
            ),
            'user_confirmed': bool(command['user_confirmed']),
            'valid_for_sec': float(command['valid_for_ms']) / 1000.0,
        }

    def submit(self, command: dict) -> SubmissionResult:
        """Wait for J6's response so phone success always means J6 HTTP 202."""
        command_id = str(command['command_id'])
        fingerprint = self._fingerprint(command)
        if self._on_received is not None:
            self._on_received(command)

        # Holding this lock across the short upstream call intentionally makes
        # concurrent duplicate requests idempotent without a worker protocol.
        with self._lock:
            previous = self._results.get(command_id)
            if previous is not None:
                previous_fingerprint, previous_result = previous
                if previous_fingerprint != fingerprint:
                    return SubmissionResult(409, {
                        'error': 'command_id already used with different data',
                        'command_id': command_id,
                    })
                self._results.move_to_end(command_id)
                return SubmissionResult(
                    previous_result.status_code,
                    {**deepcopy(previous_result.body), 'duplicate': True},
                )

            payload = self._j6_payload(command)
            try:
                status, upstream_body = self._client.submit_task(payload)
                if status == 202:
                    result = SubmissionResult(202, {
                        'submitted': True,
                        'accepted_for_delivery': True,
                        'task_id': payload['task_id'],
                        'source': SOURCE_APP,
                        'command_id': command_id,
                        'message': 'accepted by J6 Mission Manager',
                    })
                else:
                    result = SubmissionResult(502, {
                        'error': 'J6 task ingress rejected the request',
                        'upstream_status': status,
                        'upstream': upstream_body,
                    })
            except HTTPError as exc:
                result = SubmissionResult(502, {
                    'error': 'J6 task ingress returned an HTTP error',
                    'upstream_status': int(exc.code),
                })
            except (URLError, TimeoutError, OSError) as exc:
                result = SubmissionResult(503, {
                    'error': 'J6 Mission Manager is unavailable',
                    'detail': str(
                        exc.reason if isinstance(exc, URLError) else exc
                    ),
                })
            except (ValueError, RuntimeError, json.JSONDecodeError) as exc:
                result = SubmissionResult(502, {
                    'error': 'J6 returned an invalid response',
                    'detail': str(exc),
                })

            self._results[command_id] = (fingerprint, result)
            while len(self._results) > self._max_records:
                self._results.popitem(last=False)
            if self._on_forwarded is not None:
                self._on_forwarded(payload, result.status_code)
            return result


__all__ = [
    'AppTaskRelay',
    'DEFAULT_J6_BASE_URL',
    'J6HilClient',
    'SOURCE_APP',
    'SubmissionResult',
]
