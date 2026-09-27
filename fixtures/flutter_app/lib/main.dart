import 'package:flutter/material.dart';

void main() => runApp(const FixtureApp());

/// The app the fixture CI jobs analyze and test.
class FixtureApp extends StatelessWidget {
  /// Creates the app.
  const FixtureApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('fixture'))),
  );
}
