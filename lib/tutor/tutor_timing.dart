/// Configurable pauses for the voice-first tutor.
///
/// Speech gaps and screen holds default to zero. Listening for a spoken
/// answer and the example-button confirmation stay timed.
class TutorTimingConfig {
  const TutorTimingConfig({
    this.sentencePause = Duration.zero,
    this.shortTransitionPause = Duration.zero,
    this.speechToReferencePause = Duration.zero,
    this.referenceToSpeechPause = Duration.zero,
    this.afterSpeechBeforeListenPause = Duration.zero,
    this.speechResponseListenDuration = const Duration(seconds: 5),
    this.exampleReadyAffirmationDuration = const Duration(milliseconds: 1400),
    this.paceTranscript = true,
  });

  /// Instant timing for deterministic unit tests.
  const TutorTimingConfig.instant()
    : sentencePause = Duration.zero,
      shortTransitionPause = Duration.zero,
      speechToReferencePause = Duration.zero,
      referenceToSpeechPause = Duration.zero,
      afterSpeechBeforeListenPause = Duration.zero,
      speechResponseListenDuration = const Duration(milliseconds: 1),
      exampleReadyAffirmationDuration = const Duration(milliseconds: 1),
      paceTranscript = false;

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

  /// When true, speech holds the line until its transcript has finished
  /// printing. A synchronizing voice uses the loaded clip length; otherwise
  /// the wait is the text estimate. Playback does not add a further wait.
  final bool paceTranscript;
}
