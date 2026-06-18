import 'package:flutter_test/flutter_test.dart';
import 'package:field_worker_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FieldWorkerApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
