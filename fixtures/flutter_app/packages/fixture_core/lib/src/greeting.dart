import 'package:json_annotation/json_annotation.dart';

part 'greeting.g.dart';

/// A value with generated JSON conversion, so the fixture's codegen has output to compare.
@JsonSerializable()
final class Greeting {
  /// Creates a greeting.
  const Greeting({required this.text});

  /// Reads a greeting from JSON.
  factory Greeting.fromJson(Map<String, Object?> json) => _$GreetingFromJson(json);

  /// The words.
  final String text;

  /// Writes the greeting as JSON.
  Map<String, Object?> toJson() => _$GreetingToJson(this);
}
