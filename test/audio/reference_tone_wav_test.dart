import 'dart:typed_data';

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

    test('harmonic balance stays focused from low Sa through high Sa', () {
      // C3, G3, C4, and B4 cover the soft, middle, and brightest phone-speaker cases.
      final notes = <double>[
        frequencyHzForPitch(Pitch.c, octave: 3),
        frequencyHzForPitch(Pitch.g, octave: 3),
        frequencyHzForPitch(Pitch.c, octave: 4),
        frequencyHzForPitch(Pitch.b, octave: 4),
      ];

      for (final hz in notes) {
        final wav = buildReferenceToneWav(
          frequencyHz: hz,
          duration: const Duration(milliseconds: 900),
        );
        final energies = estimateHarmonicEnergies(wav, fundamentalHz: hz);
        expect(energies, isNotNull, reason: 'hz=$hz');
        final fundamental = energies![1]!;
        final second = energies[2]! / fundamental;
        final third = energies[3]! / fundamental;
        final fourth = energies[4]! / fundamental;

        expect(fundamental, greaterThan(0), reason: 'hz=$hz');
        // Octave adds body, still well under the fundamental.
        expect(second, inInclusiveRange(0.06, 0.16), reason: 'hz=$hz');
        // 3rd/4th are the phone-speaker definition, kept quiet enough to stay warm.
        expect(third, inInclusiveRange(0.008, 0.04), reason: 'hz=$hz');
        expect(fourth, inInclusiveRange(0.001, 0.012), reason: 'hz=$hz');
        expect(fourth, lessThan(third), reason: 'hz=$hz');
        expect(third, lessThan(second), reason: 'hz=$hz');
      }
    });

    test('attack and release stay silent and the sustain does not clip', () {
      final wav = buildReferenceToneWav(
        frequencyHz: 196,
        duration: const Duration(milliseconds: 500),
      );
      final data = ByteData.sublistView(wav);
      final sampleCount = data.getUint32(40, Endian.little) ~/ 2;
      final first = data.getInt16(44, Endian.little);
      final last = data.getInt16(44 + (sampleCount - 1) * 2, Endian.little);
      expect(first.abs(), lessThan(200));
      expect(last.abs(), lessThan(800));

      var peak = 0;
      for (var i = 0; i < sampleCount; i++) {
        final sample = data.getInt16(44 + i * 2, Endian.little).abs();
        if (sample > peak) {
          peak = sample;
        }
      }
      expect(peak, greaterThan(8000));
      expect(peak, lessThan(32000));
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
