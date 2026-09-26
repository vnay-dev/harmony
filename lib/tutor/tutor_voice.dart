/// Speaks tutor lines aloud. Implementations may use platform TTS.
///
/// Tests inject a recording fake so speech sequence is deterministic.
abstract class TutorVoice {
  /// Speaks [text] and completes when utterance finishes (or is cancelled).
  Future<void> speak(String text);

  /// Stops any in-progress utterance.
  Future<void> stop();

  /// Releases native resources.
  Future<void> dispose();
}

/// No-op voice for environments where speech is unavailable.
class SilentTutorVoice implements TutorVoice {
  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
