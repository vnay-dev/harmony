/// High-level conversational steps in a tutor session.
///
/// The underlying Assist search engine keeps its own phases; this enum is the
/// voice/UI-facing narrative layer.
enum TutorStep {
  welcome,
  discoverStartingNote,
  startingNoteCaptured,
  startingNoteFailure,
  testLower,
  askLowerAudibility,
  testMiddle,
  testUpper,
  askUpperComfort,
  exploreNextShruti,
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
