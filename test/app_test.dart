import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('boots to the empty dashboard with add and scan actions', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();
    expect(find.text('No Husk servers yet'), findsOneWidget);
    expect(find.text('Add server'), findsOneWidget);
    expect(find.text('Scan network'), findsOneWidget);
  });
}
