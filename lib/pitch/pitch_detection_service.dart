import 'package:harmony/models/pitch.dart';

/// One pitch-detection reading from the microphone.
class PitchReading {
  const PitchReading({required this.hasPitch, this.frequencyHz, this.note});

  /// No reliable pitch detected (silence, noise, speech without clear F0).
  static const PitchReading none = PitchReading(hasPitch: false);

  final bool hasPitch;
  final double? frequencyHz;
  final Pitch? note;
}

/// Contract for live microphone pitch detection.
///
/// Keeps capture and detection replaceable without changing the UI.
abstract class PitchDetectionService {
  /// Live readings while listening. Emits [PitchReading.none] when no pitch.
  Stream<PitchReading> get readings;

  /// Whether the microphone is currently being captured.
  bool get isListening;

  /// Requests permission if needed, then starts listening.
  Future<void> start();

  /// Stops listening and releases the microphone.
  Future<void> stop();

  /// Releases resources.
  Future<void> dispose();
}

/// Thrown when microphone access or pitch detection fails.
class PitchDetectionException implements Exception {
  PitchDetectionException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'PitchDetectionException: $message';
}
