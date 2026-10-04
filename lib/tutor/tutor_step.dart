/// High-level conversational steps in a tutor session.
///
/// The underlying Assist search engine keeps its own phases; this enum is the
/// voice/UI-facing narrative layer.
enum TutorStep {
  welcome,

  /// Spoken once after welcome, before the starting-note exercise.
  orientation,
  discoverStartingNote,
  startingNoteCaptured,
  startingNoteFailure,
  testLower,
  askLowerAudibility,
  testMiddle,
  askMiddleComfort,
  testUpper,
  askUpperComfort,
  exploreNextShruti,

  /// Stage 2 recovery: offer a nearby sound after assisted practice.
  offerDifferentSound,
  complete,
  unresolved,
  stopped,
}

/// Bottom CTA the tutor is waiting on (Stage 1 readiness / Stage 2 play).
enum TutorPrimaryAction {
  none,
  letsBegin,
  imReadyToListen,
  imReadyForNextStep,
  letsTryAgain,

  /// Stage 2: user confirms before the first Lower Sa reference plays.
  playTheSound,
}

/// Visual state of the persistent tutor presence circle.
enum TutorPresenceState { idle, speaking, listening, success }

/// Visual phase of the Stage 1 "Listen to an example" control.
enum TutorExampleControlPhase {
  /// Idle / playing — normal label and play/pause icon.
  idle,

  /// Preparing a different synthesized reference tone.
  loading,

  /// Brief affirmation that the new tone is ready (not auto-played).
  loaded,
}

/// How much help the tutor gives after repeated struggle.
enum TutorTeachingLevel {
  /// First attempt — listen / sing instructions only.
  standard,

  /// First struggle — reassure and demonstrate again.
  retryOnce,

  /// Second struggle — guided sing-along.
  guided,

  /// Third struggle — simplify to humming along.
  humAlong,
}

/// User-facing place in Tutor Mode.
///
/// Derived from the existing tutor step and Assist engine. It does not
/// decide pitches or advance the search.
enum TutorJourneyStage { listenToVoice, exploreRange, findShruti }

/// How one [TutorJourneyStage] is drawn in the journey indicator.
enum TutorJourneyMark { complete, current, upcoming }
