@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Run by the fixture's `gate-extra` recipe (`flutter test --platform chrome`); the VM run skips it.
void main() {
  test('runs in a browser', () => expect(kIsWeb, isTrue));
}
