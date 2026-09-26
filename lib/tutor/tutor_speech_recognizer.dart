/// Minimal speech-to-text interface for tutor Yes/No and comfort answers.
///
/// Keeps STT behind a small surface so tests can inject fakes and production
/// can use a platform implementation without coupling TutorSession to a package.
abstract class TutorSpeechRecognizer {
  /// Whether recognition is available on this device.
  Future<bool> get isAvailable;

  /// Listens until a final transcript, [timeout], or [stop].
  ///
  /// Returns the best transcript, or `null` when nothing useful was heard.
  Future<String?> listen({
    required Duration timeout,
    void Function(String partial)? onPartial,
  });

  Future<void> stop();

  Future<void> dispose();
}

/// No-op recognizer used when STT is unavailable or in engine-only tests.
class SilentTutorSpeechRecognizer implements TutorSpeechRecognizer {
  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<String?> listen({
    required Duration timeout,
    void Function(String partial)? onPartial,
  }) async {
    return null;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
