import 'package:harmony/tutor/tutor_speech_recognizer.dart';

/// Deterministic STT fake for tutor tests.
class FakeTutorSpeechRecognizer implements TutorSpeechRecognizer {
  FakeTutorSpeechRecognizer({this.available = true});

  bool available;
  final List<String> queue = <String>[];
  int listenCount = 0;
  int stopCount = 0;
  int _generation = 0;

  /// When set, [listen] waits before returning the queued transcript.
  Future<void>? listenHold;

  void enqueue(String transcript) => queue.add(transcript);

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<String?> listen({
    required Duration timeout,
    void Function(String partial)? onPartial,
  }) async {
    final generation = _generation;
    listenCount += 1;
    final hold = listenHold;
    if (hold != null) {
      await hold;
    }
    if (generation != _generation || queue.isEmpty) {
      return null;
    }
    final next = queue.removeAt(0);
    onPartial?.call(next);
    return next;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _generation += 1;
  }

  @override
  Future<void> dispose() async {}
}
