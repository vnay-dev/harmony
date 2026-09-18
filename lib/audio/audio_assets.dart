import 'package:harmony/models/pitch.dart';

/// Asset paths used by the app.
class AudioAssets {
  const AudioAssets._();

  /// Pitch-specific tanpura samples keyed by Sa.
  ///
  /// Temporarily pointed at [assets/audio/pilot] for A/B testing against the
  /// older Pa set in [assets/audio/pa]. Pilot filenames use `cis` for sharps.
  /// Keep the `pa/` assets until the pilot set is confirmed.
  static const Map<Pitch, String> tanpuraSamplesByPitch = {
    Pitch.c: 'assets/audio/pilot/tanpura_C.mp3',
    Pitch.cSharp: 'assets/audio/pilot/tanpura_Ccis.mp3',
    Pitch.d: 'assets/audio/pilot/tanpura_D.mp3',
    Pitch.dSharp: 'assets/audio/pilot/tanpura_Dcis.mp3',
    Pitch.e: 'assets/audio/pilot/tanpura_E.mp3',
    Pitch.f: 'assets/audio/pilot/tanpura_F.mp3',
    Pitch.fSharp: 'assets/audio/pilot/tanpura_Fcis.mp3',
    Pitch.g: 'assets/audio/pilot/tanpura_G.mp3',
    Pitch.gSharp: 'assets/audio/pilot/tanpura_Gcis.mp3',
    Pitch.a: 'assets/audio/pilot/tanpura_A.mp3',
    Pitch.aSharp: 'assets/audio/pilot/tanpura_Acis.mp3',
    Pitch.b: 'assets/audio/pilot/tanpura_B.mp3',
  };

  /// Sample path for [pitch], or `null` if no recording is available yet.
  static String? sampleFor(Pitch pitch) => tanpuraSamplesByPitch[pitch];

  /// Whether a tanpura sample exists for [pitch].
  static bool hasSample(Pitch pitch) =>
      tanpuraSamplesByPitch.containsKey(pitch);
}
