import 'dart:math' as math;

import 'package:harmony/models/pitch.dart';

/// Converts a frequency in Hz to the nearest chromatic pitch class (C–B).
///
/// Uses equal temperament with A4 = 440 Hz. Returns `null` for non-positive
/// frequencies.
Pitch? noteFromFrequency(double frequencyHz) {
  if (frequencyHz <= 0 || frequencyHz.isNaN || frequencyHz.isInfinite) {
    return null;
  }

  final midi = 69 + (12 * (math.log(frequencyHz / 440) / math.ln2));
  final noteIndex = midi.round() % 12;
  final normalizedIndex = noteIndex < 0 ? noteIndex + 12 : noteIndex;
  return Pitch.values[normalizedIndex];
}

/// Equal-tempered frequency in Hz for [pitch] at [octave].
///
/// Uses A4 = 440 Hz. Octave numbering follows scientific pitch (C4 = middle C).
/// Harmony tanpura samples are tuned around octave 3.
double frequencyHzForPitch(Pitch pitch, {int octave = 3}) {
  final midi = (octave + 1) * 12 + pitch.index;
  return 440.0 * math.pow(2, (midi - 69) / 12);
}

/// Pitch distance from [referenceHz] to [frequencyHz] in cents.
///
/// Positive when [frequencyHz] is sharp of [referenceHz]. Returns `null` when
/// either frequency is non-positive or non-finite.
double? centsBetweenFrequencies(double frequencyHz, double referenceHz) {
  if (frequencyHz <= 0 ||
      referenceHz <= 0 ||
      frequencyHz.isNaN ||
      referenceHz.isNaN ||
      frequencyHz.isInfinite ||
      referenceHz.isInfinite) {
    return null;
  }

  return 1200 * (math.log(frequencyHz / referenceHz) / math.ln2);
}
