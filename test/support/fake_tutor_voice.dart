import 'package:harmony/tutor/tutor_voice.dart';

/// Records spoken lines for deterministic tutor tests.
class FakeTutorVoice implements TutorVoice {
  final List<String> spoken = <String>[];
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    final hook = onSpeak;
    if (hook != null) {
      await hook(text);
    }
  }

  /// Optional gate so tests can stop mid-utterance.
  Future<void> Function(String text)? onSpeak;

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
