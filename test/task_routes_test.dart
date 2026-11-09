import 'package:cleannav_mobile/models/task_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Navigation V1 exposes only the five authorized operations', () {
    expect(tasks.map((task) => task.id), [41, 4, 6, 7, 43]);
    expect(
        tasks.any((task) => {30, 31, 32, 33, 42}.contains(task.id)), isFalse);
    expect(taskById(41).key, 'GOTO_REGION');
    expect(taskById(43).key, 'RETURN_CHARGER');
  });
}
