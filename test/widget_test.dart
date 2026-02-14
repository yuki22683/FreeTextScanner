import 'package:flutter_test/flutter_test.dart';
import 'package:free_text_scanner/main.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(const FreeTextScannerApp());
    expect(find.text('Text Scanner'), findsOneWidget);
  });
}
