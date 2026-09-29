import 'package:fixture_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the greeting from the workspace member', (tester) async {
    await tester.pumpWidget(const FixtureApp());
    expect(find.text('fixture'), findsOneWidget);
  });
}
