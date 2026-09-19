import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/tanpura_playback_pitch.dart';

/// Discrete targets in the Assist Mode Stage 2 range exercise.
enum AssistRangePoint {
  /// Lower Sa of the candidate Shruti.
  lowerSa,

  /// Pa (perfect fifth) above Lower Sa.
  pa,

  /// Upper Sa — one octave above Lower Sa.
  upperSa,
}

/// Lower Sa → Pa → Upper Sa frequencies for a Stage 1 candidate Shruti.
///
/// Uses the same equal-tempered helpers as the rest of Assist Mode. Default
/// Lower Sa octave matches Harmony tanpura samples (octave 3).
class AssistRangeTargets {
  AssistRangeTargets(this.sa, {this.saOctave = 3})
    : assert(saOctave >= 0 && saOctave <= 7);

  /// Candidate Shruti (Stage 1 result), pitch class only.
  final Pitch sa;

  /// Scientific octave for Lower Sa (Upper Sa is [saOctave] + 1).
  final int saOctave;

  /// Perfect fifth above [sa].
  Pitch get paPitch => TanpuraPlaybackPitch.paForSa(sa);

  double get lowerSaHz => frequencyHzForPitch(sa, octave: saOctave);

  double get paHz => frequencyHzForPitch(paPitch, octave: saOctave);

  double get upperSaHz => frequencyHzForPitch(sa, octave: saOctave + 1);

  /// Target frequency for [point].
  double frequencyHzFor(AssistRangePoint point) {
    switch (point) {
      case AssistRangePoint.lowerSa:
        return lowerSaHz;
      case AssistRangePoint.pa:
        return paHz;
      case AssistRangePoint.upperSa:
        return upperSaHz;
    }
  }

  /// Pitch class used to pick the Tanpura reference sample for [point].
  ///
  /// Upper Sa reuses the Sa sample (assets are pitch-class keyed, not octave).
  Pitch playbackPitchFor(AssistRangePoint point) {
    switch (point) {
      case AssistRangePoint.lowerSa:
      case AssistRangePoint.upperSa:
        return sa;
      case AssistRangePoint.pa:
        return paPitch;
    }
  }

  /// Short non-technical label for UI cues.
  static String labelFor(AssistRangePoint point) {
    switch (point) {
      case AssistRangePoint.lowerSa:
        return 'Lower Sa';
      case AssistRangePoint.pa:
        return 'Pa';
      case AssistRangePoint.upperSa:
        return 'Upper Sa';
    }
  }

  /// Next point after a successful match, or `null` when Upper Sa is done.
  static AssistRangePoint? nextAfter(AssistRangePoint point) {
    switch (point) {
      case AssistRangePoint.lowerSa:
        return AssistRangePoint.pa;
      case AssistRangePoint.pa:
        return AssistRangePoint.upperSa;
      case AssistRangePoint.upperSa:
        return null;
    }
  }

  /// Normalized guide position for [point] (0 = low, 1 = high).
  double guidePositionFor(AssistRangePoint point) {
    return guidePositionForHz(frequencyHzFor(point)) ?? 0.0;
  }

  /// Maps a live frequency onto the Lower Sa → Upper Sa guide (0–1).
  ///
  /// Uses a logarithmic (cents) scale so the visual tracks musical distance.
  /// Returns `null` for invalid frequencies.
  double? guidePositionForHz(double frequencyHz) {
    if (frequencyHz <= 0 ||
        frequencyHz.isNaN ||
        frequencyHz.isInfinite) {
      return null;
    }

    final fromLow = centsBetweenFrequencies(frequencyHz, lowerSaHz);
    final span = centsBetweenFrequencies(upperSaHz, lowerSaHz);
    if (fromLow == null || span == null || span.abs() < 1) {
      return null;
    }
    return (fromLow / span).clamp(0.0, 1.0);
  }
}
