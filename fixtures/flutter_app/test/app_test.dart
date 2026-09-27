import 'package:fixture_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders', (tester) async {
    await tester.pumpWidget(const FixtureApp());
    expect(find.text('fixture'), findsOneWidget);
  });
}
