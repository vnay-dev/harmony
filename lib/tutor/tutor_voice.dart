/// Speaks tutor lines aloud.
///
/// Production uses on-device KittenTTS (or optional HTTP TTS). Tests inject a
/// fake so speech sequence is deterministic.
abstract class TutorVoice {
  /// Speaks [text] and completes when playback finishes or is cancelled.
  ///
  /// Prefer [playAssets] when the caller already resolved a [TutorDialogue] so
  /// transcript text and audio ids cannot diverge.
  ///
  /// [onStarted] fires when audible playback is about to begin (after load),
  /// so the UI can show the matching transcript in sync with the voice.
  ///
  /// When [synchronizesTranscript] is true, [playbackDuration] is the loaded
  /// clip length at that moment, or null when there is no audible clip.
  Future<void> speak(String text, {void Function()? onStarted});

  /// Speaks dialogue ids (for example `S70`) in order via synthesized audio.
  ///
  /// Completes when the last clip ends or playback is cancelled. Does not
  /// decide transcript text — the coordinator owns that from the same dialogue.
  ///
  /// [onStarted] fires once, when the first clip is loaded and about to play.
  Future<void> playAssets(List<String> assetIds, {void Function()? onStarted});

  /// True when the transcript should wait for [onStarted] and follow
  /// [playbackDuration] instead of a text-length estimate.
  ///
  /// Kitten and HTTP playback set this so the typewriter starts with the
  /// generated audio, not when the line is chosen.
  bool get synchronizesTranscript;

  /// Loaded clip length, valid inside [onStarted]. Null for text-only speech.
  Duration? get playbackDuration;

  /// Stops any in-progress utterance and drops queued playback.
  Future<void> stop();

  /// Releases native resources.
  Future<void> dispose();
}

/// No-op voice for environments where speech is unavailable.
class SilentTutorVoice implements TutorVoice {
  @override
  bool get synchronizesTranscript => false;

  @override
  Duration? get playbackDuration => null;

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
