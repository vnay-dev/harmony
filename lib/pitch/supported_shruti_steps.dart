import 'package:harmony/models/pitch.dart';

/// Next higher supported Sa pitch class, or `null` when [pitch] is already B.
Pitch? nextHigherSupportedShruti(Pitch pitch) {
  if (pitch.index >= Pitch.values.length - 1) {
    return null;
  }
  return Pitch.values[pitch.index + 1];
}
