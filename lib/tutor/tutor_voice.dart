/// Speaks tutor lines aloud.
///
/// The app plays bundled recordings. Tests inject a recording fake so speech
/// sequence is deterministic.
abstract class TutorVoice {
  /// Speaks [text] and completes when playback finishes or is cancelled.
  ///
  /// [text] is the script line the session already uses. A recording-backed
  /// implementation may also accept an asset id such as `S01`.
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
