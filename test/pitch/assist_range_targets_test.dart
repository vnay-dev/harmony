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

    test('guide positions rise from low to high', () {
      expect(targets.guidePositionFor(AssistRangePoint.lowerSa), 0.0);
      expect(
        targets.guidePositionFor(AssistRangePoint.pa),
        closeTo(700 / 1200, 0.001),
      );
      expect(targets.guidePositionFor(AssistRangePoint.upperSa), 1.0);
    });
  });
}
