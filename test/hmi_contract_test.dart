import 'package:cleannav_mobile/models/vehicle_state.dart';
import 'package:cleannav_mobile/services/http_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTP task payload uses generic user_confirmed', () {
    final payload = buildHttpTaskPayload(
      taskId: 7,
      commandId: 'reset-1',
      timestampMs: 123,
      userConfirmed: true,
    );

    expect(payload['user_confirmed'], isTrue);
    expect(payload.containsKey('safety_confirmed'), isFalse);
  });

  test('missing localization_ok is unsafe by default', () {
    final state = VehicleState.fromJson({
      'robot': {'system_state': 'SYSTEM_READY'},
      'task': {'state': 'IDLE'},
    }, ConnectionKind.network);

    expect(state.localizationOk, isFalse);
  });

  test('canonical RobotStatus and TaskStatus fields are parsed', () {
    final state = VehicleState.fromJson({
      'robot': {
        'system_state': 'SYSTEM_BUSY',
        'localization_ok': true,
        'linear_velocity_mps': 0.25,
        'emergency_stop': false,
      },
      'task': {
        'task_id': 30,
        'state': 'NAVIGATING',
        'progress': 0.4,
        'message': 'running',
      },
    }, ConnectionKind.network);

    expect(state.localizationOk, isTrue);
    expect(state.speed, 0.25);
    expect(state.task?.id, 30);
    expect(state.progress, 0.4);
  });
}
