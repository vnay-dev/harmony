import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';

void main() {
  test('Pitch exposes all 12 Sa options in order', () {
    expect(Pitch.values.map((pitch) => pitch.label).toList(), [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ]);
  });

  test('each pitch has the Shruti picker swara', () {
    expect(Pitch.values.map((pitch) => pitch.swara).toList(), [
      'Sa',
      're (k)',
      'Re',
      'ga (k)',
      'Ga',
      'Ma',
      'Ma (t)',
      'Pa',
      'dha (k)',
      'Dha',
      'ni (k)',
      'Ni',
    ]);
  });

  test('default Sa is C', () {
    expect(Pitch.defaultPitch, Pitch.c);
    expect(Pitch.defaultPitch.label, 'C');
  });

  test('next and previous step through the 12 pitches and wrap', () {
    expect(Pitch.c.next, Pitch.cSharp);
    expect(Pitch.c.previous, Pitch.b);
    expect(Pitch.b.next, Pitch.c);
    expect(Pitch.g.previous, Pitch.fSharp);
  });
}
