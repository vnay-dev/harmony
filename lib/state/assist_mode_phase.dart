/// Configurable timings for Assist Mode discrete rounds.
class AssistTimingConfig {
  const AssistTimingConfig({
    this.referencePlayDuration = const Duration(seconds: 5),
    this.settlingDuration = const Duration(milliseconds: 600),
    this.listenDuration = const Duration(seconds: 6),
    this.transitionDuration = const Duration(seconds: 2),
  });

  /// How long a Stage 2 reference tone plays before singing.
  final Duration referencePlayDuration;

  /// Silence after stopping reference audio before mic analysis starts.
  final Duration settlingDuration;

  /// How long the user should sing while Harmony listens.
  final Duration listenDuration;

  /// Brief pause after listening before the next reference plays.
  final Duration transitionDuration;
}

/// Which Assist Mode stage is active.
enum AssistStage {
  /// Stage 1: capture a comfortable starting note from the user's voice.
  findingStart,

  /// Stage 2: guided Lower Sa → Pa → Upper Sa range check.
  exploringRange,
}

/// Stage 2 search posture while looking for one comfortable Shruti.
enum AssistShrutiSearchMode {
  /// Testing the Stage 1 starting candidate.
  initial,

  /// At least one comfortable found; climb until Upper Sa is strained.
  climbing,

  /// Lower Sa was too low; find the first fully comfortable Shruti upward.
  seekingHigher,

  /// Upper Sa was too high with no prior comfortable; find first fit downward.
  seekingLower,
}

/// Presentation phases for Assist Mode V2 discrete rounds.
enum AssistUiPhase {
  /// Pre-session introduction.
  intro,

  /// Reference tone is playing; pitch analysis is off (Stage 2).
  playingReference,

  /// Settling before mic analysis.
  preparingToListen,

  /// User should sing; pitch analysis is on.
  listening,

  /// Listening ended; computing next step (no analysis).
  processing,

  /// Friendly pause before the next play phase.
  showingTransition,

  /// Legacy Stage 1 verify phase (unused in voice-only discovery).
  verifying,

  /// Not enough stable singing; ask to try again.
  retry,

  /// Stage 1 starting candidate found; introducing Stage 2.
  startingPointFound,

  /// Legacy unused phase (kept out of new flow).
  awaitingComfort,

  /// Lower Sa matched; waiting for audibility Yes / Too low.
  awaitingLowerAudibility,

  /// Upper Sa matched; waiting for Comfortable / Strained.
  awaitingUpperComfort,

  /// Introducing the next Shruti to test.
  exploringNextShruti,

  /// Climbing stopped at a strained Upper Sa; last comfortable is ready.
  rangeBoundaryReached,

  /// No comfortable Shruti found within supported bounds.
  rangeUnresolved,

  /// Stage 2 finished (boundary acknowledged or top of range).
  completed,
}
