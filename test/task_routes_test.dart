import 'package:cleannav_mobile/models/task_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('冻结任务目录完整且 task_id 无重复', () {
    expect(tasks.map((task) => task.id).toList(), [1,2,3,4,5,6,7,10,20,30,31,32,33]);
    expect(tasks.map((task) => task.id).toSet().length, tasks.length);
  });

  test('主要任务拥有不同路线', () {
    final routeKinds = [5,10,20,30,31,32,33].map((id) => taskById(id).route).toSet();
    expect(routeKinds.length, 7);
  });

  test('每条路线都有足够轨迹点', () {
    for (final route in RouteKind.values) {
      expect(routePoints(route).length, greaterThanOrEqualTo(5));
    }
  });
}
