import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/nearest_supported_shruti.dart';

void main() {
  test('220 Hz maps to A', () {
    final result = nearestSupportedShruti(220);
    expect(result, isNotNull);
    expect(result!.pitch, Pitch.a);
    expect(result.frequencyHz, closeTo(frequencyHzForPitch(Pitch.a), 0.01));
  });

  test('164.81 Hz maps to E', () {
    final result = nearestSupportedShruti(164.81);
    expect(result, isNotNull);
    expect(result!.pitch, Pitch.e);
    expect(result.frequencyHz, closeTo(frequencyHzForPitch(Pitch.e), 0.01));
  });

  test('196 Hz maps to G', () {
    final result = nearestSupportedShruti(196);
    expect(result, isNotNull);
    expect(result!.pitch, Pitch.g);
    expect(result.frequencyHz, closeTo(frequencyHzForPitch(Pitch.g), 0.01));
  });

  test('130.81 Hz maps to C', () {
    final result = nearestSupportedShruti(130.81);
    expect(result, isNotNull);
    expect(result!.pitch, Pitch.c);
    expect(result.frequencyHz, closeTo(frequencyHzForPitch(Pitch.c), 0.01));
  });

  test('frequencies slightly above/below each target select the nearest', () {
    final aHz = frequencyHzForPitch(Pitch.a);
    final slightlySharp = aHz * math.pow(2, 30 / 1200).toDouble();
    final slightlyFlat = aHz * math.pow(2, -30 / 1200).toDouble();

    expect(nearestSupportedShruti(slightlySharp)?.pitch, Pitch.a);
    expect(nearestSupportedShruti(slightlyFlat)?.pitch, Pitch.a);

    final eHz = frequencyHzForPitch(Pitch.e);
    expect(
      nearestSupportedShruti(eHz * math.pow(2, 40 / 1200).toDouble())?.pitch,
      Pitch.e,
    );
    expect(
      nearestSupportedShruti(eHz * math.pow(2, -40 / 1200).toDouble())?.pitch,
      Pitch.e,
    );
  });

  test('one octave above a candidate maps to the same pitch class', () {
    final a3 = frequencyHzForPitch(Pitch.a);
    final a4 = a3 * 2;
    final a2 = a3 / 2;

    expect(nearestSupportedShruti(a4)?.pitch, Pitch.a);
    expect(nearestSupportedShruti(a4)?.frequencyHz, closeTo(a3, 0.01));

    expect(nearestSupportedShruti(a2)?.pitch, Pitch.a);
    expect(nearestSupportedShruti(a2)?.frequencyHz, closeTo(a3, 0.01));

    final c3 = frequencyHzForPitch(Pitch.c);
    expect(nearestSupportedShruti(c3 * 2)?.pitch, Pitch.c);
    expect(nearestSupportedShruti(c3 * 4)?.pitch, Pitch.c);
  });

  test('invalid, zero, and negative frequencies return null', () {
    expect(nearestSupportedShruti(0), isNull);
    expect(nearestSupportedShruti(-1), isNull);
    expect(nearestSupportedShruti(-220), isNull);
    expect(nearestSupportedShruti(double.nan), isNull);
    expect(nearestSupportedShruti(double.infinity), isNull);
    expect(nearestSupportedShruti(double.negativeInfinity), isNull);
  });
}
