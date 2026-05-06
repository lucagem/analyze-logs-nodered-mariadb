import 'package:flutter_test/flutter_test.dart';

import 'package:log_analyzer/main.dart';

void main() {
  testWidgets('App boots without crashing', (tester) async {
    await tester.pumpWidget(const LogAnalyzerApp());
    await tester.pump();
    expect(find.text('Log Analyzer'), findsOneWidget);
  });
}
