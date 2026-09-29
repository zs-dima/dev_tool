import 'package:fixture_core/fixture_core.dart';
import 'package:test/test.dart';

void main() {
  test('a greeting survives a JSON round trip', () {
    const greeting = Greeting(text: 'hello');
    expect(Greeting.fromJson(greeting.toJson()).text, 'hello');
  });
}
