import 'package:cleannav_mobile/screens/overview_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speed text hides a signed zero after two-decimal rounding', () {
    expect(formatOverviewSpeedMps(-0.004), '0.00');
    expect(formatOverviewSpeedMps(0), '0.00');
    expect(formatOverviewSpeedMps(0.004), '0.00');
    expect(formatOverviewSpeedMps(-0.006), '-0.01');
    expect(formatOverviewSpeedMps(0.2), '0.20');
  });
}
