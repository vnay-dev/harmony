/// Configurable pauses for the voice-first tutor.
///
/// Keeps instruction pacing calm without scattering delays in the UI.
class TutorTimingConfig {
  const TutorTimingConfig({
    this.sentencePause = const Duration(milliseconds: 850),
    this.shortTransitionPause = const Duration(milliseconds: 500),
    this.speechToReferencePause = const Duration(milliseconds: 650),
    this.referenceToSpeechPause = const Duration(milliseconds: 650),
    this.afterSpeechBeforeListenPause = const Duration(milliseconds: 500),
    this.speechResponseListenDuration = const Duration(seconds: 5),
    this.exampleReadyAffirmationDuration = const Duration(milliseconds: 1400),
  });

  /// Instant timing for deterministic unit tests.
  const TutorTimingConfig.instant()
    : sentencePause = Duration.zero,
      shortTransitionPause = Duration.zero,
      speechToReferencePause = Duration.zero,
      referenceToSpeechPause = Duration.zero,
      afterSpeechBeforeListenPause = Duration.zero,
      speechResponseListenDuration = const Duration(milliseconds: 1),
      exampleReadyAffirmationDuration = const Duration(milliseconds: 1);

  /// Pause between consecutive spoken sentences.
  final Duration sentencePause;

  /// Brief pause for short transitions between instructions.
  final Duration shortTransitionPause;

  /// Pause after tutor speech before reference audio starts.
  final Duration speechToReferencePause;

  /// Pause after reference audio stops before the next spoken line.
  final Duration referenceToSpeechPause;

  /// Pause after a spoken handoff before mic listening begins.
  final Duration afterSpeechBeforeListenPause;

  /// How long to listen for a spoken Yes/No or comfort answer.
  final Duration speechResponseListenDuration;

  /// How long "New sound loaded" stays on the example button.
  final Duration exampleReadyAffirmationDuration;
}
