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
}
