import 'package:harmony/models/pitch.dart';

/// Asset paths used by the app.
class AudioAssets {
  const AudioAssets._();

  /// Pitch-specific Pa tanpura samples keyed by Sa.
  ///
  /// Sharp note filenames use `sharp` instead of `#` because `#` breaks
  /// Flutter asset loading (treated as a URI fragment).
  static const Map<Pitch, String> tanpuraSamplesByPitch = {
    Pitch.c: 'assets/audio/pa/tanpura_c3.m4a',
    Pitch.cSharp: 'assets/audio/pa/tanpura_csharp3.m4a',
    Pitch.d: 'assets/audio/pa/tanpura_d3.m4a',
    Pitch.dSharp: 'assets/audio/pa/tanpura_dsharp3.m4a',
    Pitch.e: 'assets/audio/pa/tanpura_e3.m4a',
    Pitch.f: 'assets/audio/pa/tanpura_f3.m4a',
    Pitch.fSharp: 'assets/audio/pa/tanpura_fsharp3.m4a',
    Pitch.g: 'assets/audio/pa/tanpura_g3.m4a',
    Pitch.gSharp: 'assets/audio/pa/tanpura_gsharp3.m4a',
    Pitch.a: 'assets/audio/pa/tanpura_a3.m4a',
    Pitch.aSharp: 'assets/audio/pa/tanpura_asharp3.m4a',
    Pitch.b: 'assets/audio/pa/tanpura_b3.m4a',
  };

  /// Sample path for [pitch], or `null` if no recording is available yet.
  static String? sampleFor(Pitch pitch) => tanpuraSamplesByPitch[pitch];

  /// Whether a tanpura sample exists for [pitch].
  static bool hasSample(Pitch pitch) =>
      tanpuraSamplesByPitch.containsKey(pitch);
}
