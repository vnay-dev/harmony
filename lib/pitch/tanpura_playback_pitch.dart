import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';

/// Pitch content of Harmony's Sa-keyed Pa tanpura playback samples.
///
/// [AudioAssets] maps each Sa to a Pa recording. When that sample plays through
/// the device speaker, the microphone can pick it up and YIN may report Pa as
/// a confident F0 — which must not be treated as user singing.
class TanpuraPlaybackPitch {
  const TanpuraPlaybackPitch._();

  /// Perfect fifth (Pa) above [sa].
  static Pitch paForSa(Pitch sa) => Pitch.values[(sa.index + 7) % 12];

  /// Whether [frequencyHz] matches the Pa fundamental expected from the
  /// tanpura sample for [saPitch], within [toleranceCents], across nearby
  /// octaves of the shipped samples.
  static bool isNearPlaybackFundamental({
    required double frequencyHz,
    required Pitch saPitch,
    double toleranceCents = 50,
  }) {
    if (frequencyHz <= 0 ||
        frequencyHz.isNaN ||
        frequencyHz.isInfinite ||
        toleranceCents <= 0) {
      return false;
    }

    final pa = paForSa(saPitch);
    for (final octave in const <int>[2, 3, 4]) {
      final expectedHz = frequencyHzForPitch(pa, octave: octave);
      final cents = centsBetweenFrequencies(frequencyHz, expectedHz);
      if (cents != null && cents.abs() <= toleranceCents) {
        return true;
      }
    }
    return false;
  }
}
