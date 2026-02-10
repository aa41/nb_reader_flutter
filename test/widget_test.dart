import 'package:flutter_test/flutter_test.dart';

import 'package:nbreader/main.dart';

void main() {
  testWidgets('Phase6TestApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const Phase6TestApp());
    await tester.pump();
    expect(find.text('Phase 6: 翻页动画'), findsOneWidget);
  });
}
