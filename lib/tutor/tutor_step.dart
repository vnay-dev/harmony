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
  testUpper,
  askUpperComfort,
  exploreNextShruti,

  /// Stage 2 recovery: offer a nearby sound after assisted practice.
  offerDifferentSound,
  complete,
  unresolved,
  stopped,
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
