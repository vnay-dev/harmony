import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';

void main() {
  test('maps common singing frequencies to nearest notes', () {
    expect(noteFromFrequency(261.63), Pitch.c); // C4
    expect(noteFromFrequency(277.18), Pitch.cSharp); // C#4
    expect(noteFromFrequency(146.83), Pitch.d); // D3
    expect(noteFromFrequency(196.0), Pitch.g); // G3
    expect(noteFromFrequency(440.0), Pitch.a); // A4
    expect(noteFromFrequency(493.88), Pitch.b); // B4
  });

  test('rounds to the nearest note', () {
    expect(noteFromFrequency(148.0), Pitch.d);
    expect(noteFromFrequency(155.0), Pitch.dSharp);
  });

  test('returns null for invalid frequencies', () {
    expect(noteFromFrequency(0), isNull);
    expect(noteFromFrequency(-10), isNull);
    expect(noteFromFrequency(double.nan), isNull);
  });

  test('centsBetweenFrequencies is zero for identical pitches', () {
    expect(centsBetweenFrequencies(440, 440), closeTo(0, 1e-9));
  });

  test('centsBetweenFrequencies measures semitone and direction', () {
    // One equal-tempered semitone above A4.
    expect(centsBetweenFrequencies(466.16, 440), closeTo(100, 0.1));
    expect(centsBetweenFrequencies(415.30, 440), closeTo(-100, 0.1));
  });

  test('centsBetweenFrequencies returns null for invalid inputs', () {
    expect(centsBetweenFrequencies(0, 440), isNull);
    expect(centsBetweenFrequencies(440, -1), isNull);
    expect(centsBetweenFrequencies(double.nan, 440), isNull);
  });

  test('frequencyHzForPitch matches common octave-3 Sa targets', () {
    expect(frequencyHzForPitch(Pitch.c), closeTo(130.81, 0.05));
    expect(frequencyHzForPitch(Pitch.d), closeTo(146.83, 0.05));
    expect(frequencyHzForPitch(Pitch.a, octave: 4), closeTo(440.0, 0.01));
  });
}
