import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/assist_range_targets.dart';
import 'package:harmony/pitch/frequency_to_note.dart';

void main() {
  group('AssistRangeTargets for C#', () {
    final targets = AssistRangeTargets(Pitch.cSharp);

    test('Lower Sa is C# at the sample octave', () {
      expect(targets.lowerSaHz, frequencyHzForPitch(Pitch.cSharp, octave: 3));
      expect(targets.playbackPitchFor(AssistRangePoint.lowerSa), Pitch.cSharp);
    });

    test('Pa is a perfect fifth above Sa (G#)', () {
      expect(targets.paPitch, Pitch.gSharp);
      expect(targets.paHz, frequencyHzForPitch(Pitch.gSharp, octave: 3));
      expect(targets.playbackPitchFor(AssistRangePoint.pa), Pitch.gSharp);
      expect(targets.paHz, greaterThan(targets.lowerSaHz));
    });

    test('Upper Sa is one octave above Lower Sa', () {
      expect(targets.upperSaHz, frequencyHzForPitch(Pitch.cSharp, octave: 4));
      expect(
        targets.upperSaHz / targets.lowerSaHz,
        closeTo(2.0, 0.0001),
      );
      expect(targets.playbackPitchFor(AssistRangePoint.upperSa), Pitch.cSharp);
    });

    test('progression is Lower Sa → Pa → Upper Sa', () {
      expect(
        AssistRangeTargets.nextAfter(AssistRangePoint.lowerSa),
        AssistRangePoint.pa,
      );
      expect(
        AssistRangeTargets.nextAfter(AssistRangePoint.pa),
        AssistRangePoint.upperSa,
      );
      expect(AssistRangeTargets.nextAfter(AssistRangePoint.upperSa), isNull);
    });

    test('guide positions are discrete LOW / MID / HIGH', () {
      expect(targets.guidePositionFor(AssistRangePoint.lowerSa), 0.0);
      expect(targets.guidePositionFor(AssistRangePoint.pa), 0.5);
      expect(targets.guidePositionFor(AssistRangePoint.upperSa), 1.0);
    });
  });

  group('AssistRangeTargets Pa octave wrap', () {
    test('G Sa uses D4 for Pa so guide Mid is above Lower Sa', () {
      final targets = AssistRangeTargets(Pitch.g);
      expect(targets.paPitch, Pitch.d);
      expect(targets.paHz, frequencyHzForPitch(Pitch.d, octave: 4));
      expect(targets.paHz, greaterThan(targets.lowerSaHz));
      expect(targets.guidePositionFor(AssistRangePoint.pa), 0.5);
      expect(
        targets.guidePositionForHz(targets.paHz),
        closeTo(700 / 1200, 0.001),
      );
    });

    test('every Sa has Pa Hz above Lower Sa and below Upper Sa', () {
      for (final sa in Pitch.values) {
        final targets = AssistRangeTargets(sa);
        expect(
          targets.paHz,
          greaterThan(targets.lowerSaHz),
          reason: 'Pa below Lower Sa for ${sa.label}',
        );
        expect(
          targets.paHz,
          lessThan(targets.upperSaHz),
          reason: 'Pa above Upper Sa for ${sa.label}',
        );
        expect(targets.guidePositionFor(AssistRangePoint.lowerSa), 0.0);
        expect(targets.guidePositionFor(AssistRangePoint.pa), 0.5);
        expect(targets.guidePositionFor(AssistRangePoint.upperSa), 1.0);
      }
    });
  });
}
