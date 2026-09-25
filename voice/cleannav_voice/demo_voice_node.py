"""DEMO-ONLY microphone -> SenseVoice -> VoiceBridge runner.

This module intentionally bypasses OfflineAsrPipeline because the selected
SenseVoice backend does not expose a calibrated confidence value.

IMPORTANT:
- This file is for the competition demo only.
- Production OfflineAsrPipeline remains fail-closed.
- Synthetic confidence is created only after an exact production intent match.
- VoiceBridgeCore, VoicePolicy and TaskCommandFactory remain authoritative.
"""

from __future__ import annotations

from array import array
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from ament_index_python.packages import get_package_share_directory
import rclpy
import sherpa_onnx

from .models import RecognizedUtterance
from .voice_bridge_core import VoiceBridgeCore
from .voice_bridge_node import VoiceBridgeNode


DEMO_SYNTHETIC_CONFIDENCE = 0.95

DEFAULT_AUDIO_DEVICE = 'RDPSource'
DEFAULT_CAPTURE_SECONDS = 5.0
DEFAULT_WARMUP_SECONDS = 1.2

DEFAULT_MODEL_DIR = (
    Path.home()
    / '.cache'
    / 'cleannav-voice'
    / 'models'
    / 'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09'
)


class DemoSenseVoiceRecognizer:
    """Keep one SenseVoice recognizer resident for the entire demo."""

    def __init__(self, model_dir: Path) -> None:
        self._model_dir = model_dir

        model = model_dir / 'model.int8.onnx'
        tokens = model_dir / 'tokens.txt'

        if not model.is_file():
            raise FileNotFoundError(f'SenseVoice model not found: {model}')

        if not tokens.is_file():
            raise FileNotFoundError(f'SenseVoice tokens not found: {tokens}')

        print()
        print('Loading SenseVoice model...')
        started = time.monotonic()

        self._recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
            model=str(model),
            tokens=str(tokens),
            num_threads=1,
            sample_rate=16000,
            feature_dim=80,
            decoding_method='greedy_search',
            debug=False,
            provider='cpu',
            language='zh',
            use_itn=False,
        )

        elapsed = time.monotonic() - started

        print(
            'SenseVoice ready '
            f'({elapsed:.3f} s model initialization)'
        )

    def transcribe(self, raw_pcm16: bytes) -> str:
        """Decode one mono 16-kHz signed PCM16 payload."""

        if not isinstance(raw_pcm16, bytes):
            raise TypeError('raw_pcm16 must be bytes')

        if not raw_pcm16:
            raise ValueError('captured audio is empty')

        if len(raw_pcm16) % 2 != 0:
            raise ValueError('PCM16 byte count must be even')

        pcm = array('h')
        pcm.frombytes(raw_pcm16)

        if sys.byteorder != 'little':
            pcm.byteswap()

        samples = [
            value / 32768.0
            for value in pcm
        ]

        stream = self._recognizer.create_stream()

        stream.accept_waveform(
            16000,
            samples,
        )

        started = time.monotonic()

        self._recognizer.decode_stream(stream)

        elapsed = time.monotonic() - started

        text = stream.result.text

        duration = len(pcm) / 16000.0

        rtf = (
            elapsed / duration
            if duration > 0.0
            else float('inf')
        )

        print(
            f'ASR decode={elapsed:.3f} s '
            f'audio={duration:.3f} s '
            f'RTF={rtf:.3f}'
        )

        return text


class DemoMicrophoneCapture:
    """Capture a short fixed demo utterance from PulseAudio."""

    def __init__(
        self,
        *,
        device: str = DEFAULT_AUDIO_DEVICE,
        capture_seconds: float = DEFAULT_CAPTURE_SECONDS,
        warmup_seconds: float = DEFAULT_WARMUP_SECONDS,
    ) -> None:

        parec = shutil.which('parec')

        if parec is None:
            raise RuntimeError('parec was not found in PATH')

        if capture_seconds <= 0.0:
            raise ValueError('capture_seconds must be > 0')

        if (
            warmup_seconds < 0.0
            or warmup_seconds >= capture_seconds
        ):
            raise ValueError(
                'warmup_seconds must satisfy '
                '0 <= warmup_seconds < capture_seconds'
            )

        self._parec = parec
        self._device = device
        self._capture_seconds = capture_seconds
        self._warmup_seconds = warmup_seconds

    def capture(self) -> bytes:
        """Capture one utterance while avoiding Pulse startup truncation."""

        fd, raw_name = tempfile.mkstemp(
            prefix='cleannav_voice_demo_',
            suffix='.raw',
        )

        os.close(fd)

        raw_path = Path(raw_name)

        command = [
            self._parec,
            '--record',
            f'--device={self._device}',
            '--rate=16000',
            '--channels=1',
            '--format=s16le',
            '--raw',
        ]

        process = None

        try:
            with raw_path.open('wb') as output:

                process = subprocess.Popen(
                    command,
                    stdout=output,
                    stderr=subprocess.PIPE,
                )

                time.sleep(self._warmup_seconds)

                if process.poll() is not None:
                    stderr = (
                        process.stderr.read().decode(
                            'utf-8',
                            errors='replace',
                        )
                        if process.stderr
                        else ''
                    )

                    raise RuntimeError(
                        'parec exited before speech capture: '
                        + stderr
                    )

                print()
                print('==============================================')
                print('现在说话')
                print('==============================================')
                print()

                remaining = (
                    self._capture_seconds
                    - self._warmup_seconds
                )

                time.sleep(remaining)

                if process.poll() is None:
                    process.terminate()

                try:
                    process.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=1.0)

            raw = raw_path.read_bytes()

        finally:

            if (
                process is not None
                and process.poll() is None
            ):
                process.kill()
                process.wait()

            raw_path.unlink(missing_ok=True)

        if not raw:
            raise RuntimeError('microphone capture returned no audio')

        if len(raw) % 2 != 0:
            raise RuntimeError(
                'microphone capture returned invalid PCM16 length'
            )

        duration = (
            len(raw)
            / 2
            / 16000.0
        )

        print(
            f'Captured {len(raw)} bytes '
            f'({duration:.3f} s PCM16)'
        )

        return raw


def build_production_core() -> VoiceBridgeCore:
    """Load the same production Voice map and Task Catalog as VoiceBridgeNode."""

    voice_share = Path(
        get_package_share_directory('cleannav_voice')
    )

    interfaces_share = Path(
        get_package_share_directory('cleannav_interfaces')
    )

    return VoiceBridgeCore.from_paths(
        voice_share / 'config' / 'voice_task_map.yaml',
        interfaces_share / 'config' / 'task_catalog.yaml',
        5000,
    )


def main(args=None) -> None:
    """Run the explicit interactive competition Demo Voice entry point."""

    rclpy.init(args=args)

    core = build_production_core()

    node = VoiceBridgeNode(
        core=core,
    )

    model_dir = Path(
        os.environ.get(
            'CLEANNAV_SENSEVOICE_MODEL_DIR',
            str(DEFAULT_MODEL_DIR),
        )
    )

    recognizer = DemoSenseVoiceRecognizer(
        model_dir,
    )

    microphone = DemoMicrophoneCapture()

    node.get_logger().warning(
        'DEMO ONLY: SenseVoice has no calibrated confidence. '
        f'Exact production intent matches will use synthetic confidence '
        f'{DEMO_SYNTHETIC_CONFIDENCE:.2f}.'
    )

    print()
    print('====================================================================================================')
    print('CLEANNAV VOICE DEMO')
    print('====================================================================================================')
    print()
    print('DEMO ONLY')
    print()
    print('流程：')
    print('  Enter')
    print('    -> 麦克风启动')
    print('    -> 出现“现在说话”')
    print('    -> SenseVoice')
    print('    -> production exact intent parser')
    print('    -> VoicePolicy')
    print('    -> /cleannav/hmi/task_command')
    print()
    print('输入 q 后 Enter 退出。')
    print()

    # Give DDS discovery a brief opportunity before the first command.
    time.sleep(0.5)

    try:

        while rclpy.ok():

            choice = input(
                '>>> 按 Enter 开始一次语音识别；输入 q 退出：'
            )

            if choice.strip().lower() in {
                'q',
                'quit',
                'exit',
            }:
                break

            try:
                raw_audio = microphone.capture()

                text = recognizer.transcribe(
                    raw_audio,
                )

            except Exception as exc:

                node.get_logger().error(
                    'demo audio/ASR failure: '
                    f'{type(exc).__name__}: {exc}'
                )

                continue

            normalized = core.parser.normalize(
                text,
            )

            intent = core.parser.parse(
                text,
            )

            print()
            print('----------------------------------------------')
            print(f'ASR_TEXT={text!r}')
            print(f'NORMALIZED={normalized!r}')

            if intent is None:

                print('INTENT=NONE')
                print('DEMO_ACTION=DROP')
                print(
                    'SYNTHETIC_CONFIDENCE_CREATED=NO'
                )
                print('----------------------------------------------')

                continue

            print(
                'INTENT_TASK_ID='
                + str(intent.task_id)
            )

            print(
                'SYNTHETIC_CONFIDENCE_CREATED=YES'
            )

            print(
                'DEMO_SYNTHETIC_CONFIDENCE='
                + str(DEMO_SYNTHETIC_CONFIDENCE)
            )

            utterance = RecognizedUtterance(
                utterance_id=(
                    'demo:'
                    + str(time.time_ns())
                ),
                text=text,
                confidence=DEMO_SYNTHETIC_CONFIDENCE,
                is_final=True,
            )

            result = node.process_utterance(
                utterance,
            )

            if result.accepted:

                print('VOICE_POLICY=ACCEPTED')
                print('TASKCOMMAND_PUBLISH=REQUESTED')

            else:

                reason = (
                    result.rejection.reason.value
                    if result.rejection
                    else 'UNKNOWN'
                )

                print(
                    'VOICE_POLICY=REJECTED:'
                    + reason
                )

                print(
                    'TASKCOMMAND_PUBLISH=NO'
                )

            print('----------------------------------------------')

            # No subscription callbacks are required, but this keeps the
            # ROS executor responsive around demo publication.
            rclpy.spin_once(
                node,
                timeout_sec=0.05,
            )

    except KeyboardInterrupt:
        pass

    finally:

        node.destroy_node()

        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
