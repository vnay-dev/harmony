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

  test('default Sa is C', () {
    expect(Pitch.defaultPitch, Pitch.c);
    expect(Pitch.defaultPitch.label, 'C');
  });
}
