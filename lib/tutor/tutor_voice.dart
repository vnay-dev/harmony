/// Speaks tutor lines aloud.
///
/// The app plays bundled recordings. Tests inject a recording fake so speech
/// sequence is deterministic.
abstract class TutorVoice {
  /// Speaks [text] and completes when playback finishes or is cancelled.
  ///
  /// Prefer [playAssets] when the caller already resolved a [TutorDialogue] so
  /// transcript text and audio ids cannot diverge.
  ///
  /// [onStarted] fires when audible playback is about to begin (after load),
  /// so the UI can show the matching transcript in sync with the voice.
  Future<void> speak(String text, {void Function()? onStarted});

  /// Plays bundled recording ids (for example `S70`) in order.
  ///
  /// Completes when the last clip ends or playback is cancelled. Does not
  /// decide transcript text — the coordinator owns that from the same dialogue.
  ///
  /// [onStarted] fires once, when the first clip is loaded and about to play.
  Future<void> playAssets(List<String> assetIds, {void Function()? onStarted});

  /// Stops any in-progress utterance and drops queued playback.
  Future<void> stop();

  /// Releases native resources.
  Future<void> dispose();
}

/// No-op voice for environments where speech is unavailable.
class SilentTutorVoice implements TutorVoice {
  @override
  Future<void> speak(String text, {void Function()? onStarted}) async {
    onStarted?.call();
  }

  @override
  Future<void> playAssets(
    List<String> assetIds, {
    void Function()? onStarted,
  }) async {
    onStarted?.call();
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
