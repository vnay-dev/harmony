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
