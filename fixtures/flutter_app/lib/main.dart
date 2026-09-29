import 'package:fixture_core/fixture_core.dart';
import 'package:flutter/material.dart';

void main() => runApp(const FixtureApp());

/// The app the fixture CI job analyzes and tests.
class FixtureApp extends StatelessWidget {
  /// Creates the app.
  const FixtureApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(child: Text(const Greeting(text: 'fixture').text)),
    ),
  );
}
