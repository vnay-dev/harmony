/// Plays a short musical reference tone at a target frequency.
///
/// Frequency is the source of truth — callers pass Hz (e.g. Lower Sa / Pa /
/// Upper Sa), not pitch-class asset keys. Stage 1 Tanpura playback stays on
/// [AudioService] and is independent of this generator.
abstract class ReferenceSoundGenerator {
  /// Whether a reference tone is currently audible.
  bool get isPlaying;

  /// Last frequency requested via [playReference], if any.
  double? get currentFrequencyHz;

  /// Generates and plays a reference tone at [frequencyHz].
  ///
  /// Implementations should replace any currently playing reference. Playback
  /// must be stoppable via [stop] so Assist Mode can silence the speaker
  /// before microphone analysis begins.
  Future<void> playReference(
    double frequencyHz, {
    Duration duration = const Duration(seconds: 5),
  });

  /// Stops any active reference tone immediately.
  Future<void> stop();

  /// Releases resources.
  Future<void> dispose();
}
