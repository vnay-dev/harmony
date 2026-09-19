/// Configurable timings for Assist Mode discrete rounds.
class AssistTimingConfig {
  const AssistTimingConfig({
    this.referencePlayDuration = const Duration(seconds: 5),
    this.settlingDuration = const Duration(milliseconds: 600),
    this.listenDuration = const Duration(seconds: 6),
    this.transitionDuration = const Duration(seconds: 2),
  });

  /// How long the tanpura plays before singing.
  final Duration referencePlayDuration;

  /// Silence after stopping tanpura before mic analysis starts.
  final Duration settlingDuration;

  /// How long the user should sing while Harmony listens.
  final Duration listenDuration;

  /// Brief pause after listening before the next reference plays.
  final Duration transitionDuration;
}

/// Which Assist Mode stage is active.
enum AssistStage {
  /// Stage 1: find the user's natural starting Shruti.
  findingStart,

  /// Stage 2: explore how high they can comfortably match.
  exploringRange,
}

/// Presentation phases for Assist Mode V2 discrete rounds.
enum AssistUiPhase {
  /// Pre-session introduction.
  intro,

  /// Tanpura is playing; pitch analysis is off.
  playingReference,

  /// Tanpura stopped; settling before mic analysis.
  preparingToListen,

  /// User should sing; pitch analysis is on.
  listening,

  /// Listening ended; computing next reference (no analysis).
  processing,

  /// Friendly pause before the next play phase.
  showingTransition,

  /// Candidate reference is close; confirming with another listen cycle.
  verifying,

  /// Not enough stable singing; ask to try the round again.
  retry,

  /// Stage 1 starting Shruti found; introducing Stage 2.
  startingPointFound,

  /// Stage 2: target matched; waiting for Comfortable / Not comfortable.
  awaitingComfort,

  /// Comfortable Shruti recommendation ready.
  completed,
}
