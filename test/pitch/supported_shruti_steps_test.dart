import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/supported_shruti_steps.dart';

void main() {
  test('nextHigherSupportedShruti advances one chromatic step', () {
    expect(nextHigherSupportedShruti(Pitch.c), Pitch.cSharp);
    expect(nextHigherSupportedShruti(Pitch.cSharp), Pitch.d);
    expect(nextHigherSupportedShruti(Pitch.aSharp), Pitch.b);
  });

  test('nextHigherSupportedShruti returns null at B', () {
    expect(nextHigherSupportedShruti(Pitch.b), isNull);
  });
}
