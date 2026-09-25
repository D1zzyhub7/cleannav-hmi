import 'package:cleannav_mobile/models/task_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('competition task catalog contains only Task 30', () {
    expect(tasks.length, 1);
    expect(tasks.single.id, 30);
    expect(tasks.single.key, 'CLEAN_NEAREST_LEAF');
    expect(tasks.single.label, '清扫最近落叶');
    expect(tasks.any((task) => {31, 32, 33}.contains(task.id)), isFalse);
  });
}
