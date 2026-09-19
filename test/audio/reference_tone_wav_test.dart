import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/audio/reference_tone_wav.dart';
import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/assist_range_targets.dart';
import 'package:harmony/pitch/frequency_to_note.dart';

void main() {
  group('C range reference frequencies', () {
    final targets = AssistRangeTargets(Pitch.c);

    test('Lower C / Lower Sa is approximately 130.81 Hz', () {
      expect(targets.lowerSaHz, closeTo(130.81, 0.02));
      expect(
        targets.frequencyHzFor(AssistRangePoint.lowerSa),
        frequencyHzForPitch(Pitch.c, octave: 3),
      );
    });

    test('G / Pa is approximately 196.00 Hz', () {
      expect(targets.paHz, closeTo(196.00, 0.02));
      expect(
        targets.frequencyHzFor(AssistRangePoint.pa),
        frequencyHzForPitch(Pitch.g, octave: 3),
      );
    });

    test('Upper C / Upper Sa is approximately 261.63 Hz', () {
      expect(targets.upperSaHz, closeTo(261.63, 0.02));
      expect(
        targets.frequencyHzFor(AssistRangePoint.upperSa),
        frequencyHzForPitch(Pitch.c, octave: 4),
      );
    });
  });

  group('buildReferenceToneWav', () {
    test('different target frequencies produce different WAV payloads', () {
      final lower = buildReferenceToneWav(frequencyHz: 130.81);
      final pa = buildReferenceToneWav(frequencyHz: 196.00);
      final upper = buildReferenceToneWav(frequencyHz: 261.63);

      expect(lower, isNot(equals(pa)));
      expect(pa, isNot(equals(upper)));
      expect(lower, isNot(equals(upper)));
    });

    test('WAV fundamentals track the requested frequency', () {
      for (final hz in <double>[130.81, 196.00, 261.63]) {
        final wav = buildReferenceToneWav(
          frequencyHz: hz,
          duration: const Duration(milliseconds: 800),
        );
        final estimated = estimateWavFundamentalHz(wav);
        expect(estimated, isNotNull);
        // Zero-crossing estimate is coarse; stay within a semitone (~6%).
        expect(estimated!, closeTo(hz, hz * 0.06));
      }
    });

    test('identical frequency requests are deterministic', () {
      final a = buildReferenceToneWav(frequencyHz: 196.00);
      final b = buildReferenceToneWav(frequencyHz: 196.00);
      expect(a, equals(b));
    });

    test('WAV headers are valid PCM mono 16-bit 44100', () {
      final wav = buildReferenceToneWav(frequencyHz: 130.81);
      final info = inspectReferenceToneWav(wav);
      expect(info.isValid, isTrue, reason: info.summary);
      expect(info.audioFormat, 1);
      expect(info.channels, 1);
      expect(info.sampleRate, 44100);
      expect(info.bitsPerSample, 16);
      expect(info.dataId, 'data');
      expect(info.riffId, 'RIFF');
      expect(info.waveId, 'WAVE');
    });
  });
}
