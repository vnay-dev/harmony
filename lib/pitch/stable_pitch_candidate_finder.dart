import 'package:flutter/foundation.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';

/// A sustained natural-note observation from a short capture window.
///
/// This is a candidate pitch the user settled on — not a confirmed Shruti.
class StablePitchCandidate {
  const StablePitchCandidate({
    required this.pitch,
    required this.frequencyHz,
    required this.stableSampleCount,
  });

  /// Chromatic pitch class the user most consistently held.
  final Pitch pitch;

  /// Representative F0 from stable voiced samples (internal / debug use).
  final double frequencyHz;

  /// How many stable voiced samples supported [pitch].
  final int stableSampleCount;
}

/// Finds the pitch a singer most consistently settled on during a short capture.
///
/// Answers only "what note did they hold?" — not "what is their Shruti?".
///
/// Ignores silence and invalid readings. Counts evidence only while
/// [PitchStabilityTracker] reports a settled pitch, so brief fluctuations and
/// dropouts do not dominate the result.
class StablePitchCandidateFinder {
  StablePitchCandidateFinder({
    PitchStabilityTracker? stabilityTracker,
    this.minStableSamples = 10,
  }) : assert(minStableSamples > 0),
       _stabilityTracker = stabilityTracker ?? PitchStabilityTracker();

  /// Minimum stable voiced samples required before a candidate is returned.
  final int minStableSamples;

  final PitchStabilityTracker _stabilityTracker;
  final Map<Pitch, int> _stableCounts = <Pitch, int>{};
  final Map<Pitch, List<double>> _stableFrequencies = <Pitch, List<double>>{};

  int _voicedAcceptedIntoTracker = 0;
  int _creditedStableSamples = 0;
  int _rejectedUnpitched = 0;
  int _rejectedNoNote = 0;
  int _rejectedTrackerNotStable = 0;
  int _rejectedNoteMismatchWhileStable = 0;

  /// Diagnostic: voiced frames that entered the stability tracker this window.
  int get debugVoicedAcceptedIntoTracker => _voicedAcceptedIntoTracker;

  /// Diagnostic: frames credited toward [_stableCounts] this window.
  int get debugCreditedStableSamples => _creditedStableSamples;

  /// Diagnostic: per-pitch credited counts (may be below [minStableSamples]).
  Map<Pitch, int> get debugStableCounts => Map<Pitch, int>.from(_stableCounts);

  /// Clears all capture evidence. Call when a new capture starts.
  void reset() {
    if (kDebugMode &&
        (_voicedAcceptedIntoTracker > 0 || _stableCounts.isNotEmpty)) {
      debugPrint(
        'AssistDiag finder.reset() clearing '
        'voicedIntoTracker=$_voicedAcceptedIntoTracker '
        'credited=$_creditedStableSamples '
        'counts=$_stableCounts',
      );
    }
    _stabilityTracker.reset();
    _stableCounts.clear();
    _stableFrequencies.clear();
    _voicedAcceptedIntoTracker = 0;
    _creditedStableSamples = 0;
    _rejectedUnpitched = 0;
    _rejectedNoNote = 0;
    _rejectedTrackerNotStable = 0;
    _rejectedNoteMismatchWhileStable = 0;
  }

  /// Feeds one reading from the live pitch pipeline.
  ///
  /// Silence / invalid / unvoiced frames are ignored so dropouts do not reset
  /// the underlying stability tracker by themselves.
  void add(PitchReading reading) {
    final frequency = reading.frequencyHz;
    if (!reading.hasPitch || frequency == null || frequency <= 0) {
      _rejectedUnpitched += 1;
      return;
    }

    final note = reading.note ?? noteFromFrequency(frequency);
    if (note == null) {
      _rejectedNoNote += 1;
      if (kDebugMode) {
        debugPrint(
          'AssistDiag rejectionReason=noteFromFrequency_returned_null '
          'hz=${frequency.toStringAsFixed(1)}',
        );
      }
      return;
    }

    _voicedAcceptedIntoTracker += 1;
    _stabilityTracker.add(note);

    if (!_stabilityTracker.isStable) {
      _rejectedTrackerNotStable += 1;
      if (kDebugMode && _voicedAcceptedIntoTracker <= 12) {
        debugPrint(
          'AssistDiag rejectionReason=tracker_not_yet_stable '
          'note=${note.label} hz=${frequency.toStringAsFixed(1)} '
          'voicedIntoTracker=$_voicedAcceptedIntoTracker '
          'needConsecutive=${_stabilityTracker.samplesToBecomeStable}',
        );
      }
      return;
    }

    final settled = _stabilityTracker.stablePitch;
    if (settled == null || note != settled) {
      _rejectedNoteMismatchWhileStable += 1;
      if (kDebugMode) {
        debugPrint(
          'AssistDiag rejectionReason=stable_note_mismatch '
          'note=${note.label} settled=${settled?.label ?? "null"} '
          'hz=${frequency.toStringAsFixed(1)}',
        );
      }
      return;
    }

    _stableCounts[settled] = (_stableCounts[settled] ?? 0) + 1;
    _stableFrequencies.putIfAbsent(settled, () => <double>[]).add(frequency);
    _creditedStableSamples += 1;

    if (kDebugMode) {
      final count = _stableCounts[settled]!;
      // Log first credits and then every 5th to avoid flooding.
      if (count <= 3 || count % 5 == 0 || count == minStableSamples) {
        debugPrint(
          'AssistDiag trackerStable=true settled=${settled.label} '
          'stableSampleCount=$count minStableSamples=$minStableSamples '
          'candidateHz=${frequency.toStringAsFixed(1)} '
          'candidateAccepted=${count >= minStableSamples}',
        );
      }
    }
  }

  /// Whether enough stable evidence exists for a confident candidate.
  bool get hasCandidate {
    return _bestPitch() != null;
  }

  /// Builds the candidate from accumulated stable evidence, or `null` if the
  /// capture does not justify a confident result.
  StablePitchCandidate? result() {
    final pitch = _bestPitch();
    if (pitch == null) {
      if (kDebugMode) {
        final bestEntry = _highestCountEntry();
        final bestCount = bestEntry?.value ?? 0;
        final bestPitch = bestEntry?.key;
        final reason = _voicedAcceptedIntoTracker == 0
            ? 'no_voiced_frames_reached_finder'
            : _creditedStableSamples == 0
            ? 'tracker_never_became_stable_or_no_credits'
            : 'stableSampleCount_below_minStableSamples '
                  '(best=${bestPitch?.label ?? "none"}:$bestCount '
                  '< minStableSamples=$minStableSamples)';
        debugPrint(
          'AssistDiag result=null rejectionReason=$reason '
          'voicedIntoTracker=$_voicedAcceptedIntoTracker '
          'creditedStableSamples=$_creditedStableSamples '
          'rejectedUnpitched=$_rejectedUnpitched '
          'rejectedTrackerNotStable=$_rejectedTrackerNotStable '
          'rejectedNoteMismatch=$_rejectedNoteMismatchWhileStable '
          'rejectedNoNote=$_rejectedNoNote '
          'counts=$_stableCounts '
          'trackerStable=${_stabilityTracker.isStable} '
          'trackerPitch=${_stabilityTracker.stablePitch?.label ?? "none"}',
        );
      }
      return null;
    }

    final frequencies = _stableFrequencies[pitch] ?? const <double>[];
    if (frequencies.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          'AssistDiag result=null '
          'rejectionReason=best_pitch_has_empty_frequency_list '
          'pitch=${pitch.label}',
        );
      }
      return null;
    }

    final candidate = StablePitchCandidate(
      pitch: pitch,
      frequencyHz: _median(frequencies),
      stableSampleCount: _stableCounts[pitch]!,
    );
    if (kDebugMode) {
      debugPrint(
        'AssistDiag result=ok pitch=${candidate.pitch.label} '
        'candidateHz=${candidate.frequencyHz.toStringAsFixed(1)} '
        'stableSampleCount=${candidate.stableSampleCount}',
      );
    }
    return candidate;
  }

  Pitch? _bestPitch() {
    Pitch? best;
    var bestCount = 0;

    _stableCounts.forEach((pitch, count) {
      if (count < minStableSamples) {
        return;
      }
      if (count > bestCount) {
        best = pitch;
        bestCount = count;
      }
    });

    return best;
  }

  MapEntry<Pitch, int>? _highestCountEntry() {
    MapEntry<Pitch, int>? best;
    _stableCounts.forEach((pitch, count) {
      if (best == null || count > best!.value) {
        best = MapEntry<Pitch, int>(pitch, count);
      }
    });
    return best;
  }

  double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }
    return (sorted[middle - 1] + sorted[middle]) / 2.0;
  }
}
