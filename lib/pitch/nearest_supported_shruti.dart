import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/reference_pitch_adjuster.dart';

/// A supported Sa pitch chosen as the best match for a detected voice frequency.
///
/// This is an initial candidate to test — not a confirmed Shruti.
class SupportedShrutiCandidate {
  const SupportedShrutiCandidate({
    required this.pitch,
    required this.frequencyHz,
  });

  /// One of Harmony's 12 supported Sa pitch classes (C–B).
  final Pitch pitch;

  /// Canonical equal-tempered frequency for [pitch] at the Sa sample octave.
  final double frequencyHz;
}

/// Maps a stable detected voice frequency to the nearest supported Sa.
///
/// Compares octave-folded cents distance against each candidate's canonical
/// frequency from [frequencyHzForPitch]. Returns `null` for non-positive or
/// non-finite frequencies.
SupportedShrutiCandidate? nearestSupportedShruti(
  double detectedVoiceFrequencyHz,
) {
  if (detectedVoiceFrequencyHz <= 0 ||
      detectedVoiceFrequencyHz.isNaN ||
      detectedVoiceFrequencyHz.isInfinite) {
    return null;
  }

  Pitch? bestPitch;
  double? bestFrequencyHz;
  double? bestAbsCents;

  for (final pitch in Pitch.values) {
    final candidateHz = frequencyHzForPitch(pitch);
    final folded = foldFrequencyTowardReference(
      detectedVoiceFrequencyHz,
      candidateHz,
    );
    final cents = centsBetweenFrequencies(folded, candidateHz);
    if (cents == null) {
      continue;
    }

    final absCents = cents.abs();
    if (bestAbsCents == null || absCents < bestAbsCents) {
      bestAbsCents = absCents;
      bestPitch = pitch;
      bestFrequencyHz = candidateHz;
    }
  }

  if (bestPitch == null || bestFrequencyHz == null) {
    return null;
  }

  return SupportedShrutiCandidate(
    pitch: bestPitch,
    frequencyHz: bestFrequencyHz,
  );
}
