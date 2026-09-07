import 'package:flutter_test/flutter_test.dart';

import 'package:cleannav_mobile/main.dart';

void main() {
  testWidgets(
    'CleanNav app renders its HMI shell',
    (WidgetTester tester) async {
      await tester.pumpWidget(const CleanNavApp());
      await tester.pump();

      expect(find.text('CleanNav'), findsOneWidget);
      expect(find.byType(CleanNavApp), findsOneWidget);
    },
  );
}
