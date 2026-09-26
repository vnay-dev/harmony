import 'dart:math' as math;
import 'dart:typed_data';

/// Microphone energy from the same PCM window the pitch detector already uses.
///
/// This is not a second capture pipeline. Silence stays near 0 so the UI can
/// stay still until the user actually makes a sound.
class VoiceActivity {
  const VoiceActivity._();

  /// RMS below this is treated as silence, even if YIN reports a pitch.
  ///
  /// Quiet digital silence and room hiss must not become a sung match.
  static const minVoicedRms = 0.012;

  /// Full-scale RMS that maps to activity level 1.
  static const _fullScaleRms = 0.12;

  static double rmsFromPcm16(Uint8List pcm) {
    if (pcm.length < 2) {
      return 0;
    }
    final data = ByteData.sublistView(pcm);
    final samples = pcm.length ~/ 2;
    var sum = 0.0;
    for (var i = 0; i < samples; i++) {
      final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
      sum += sample * sample;
    }
    return math.sqrt(sum / samples);
  }

  /// 0 is silence. 1 is a strong sung or spoken sound.
  static double levelFromPcm16(Uint8List pcm) {
    final rms = rmsFromPcm16(pcm);
    if (rms <= 0) {
      return 0;
    }
    return (rms / _fullScaleRms).clamp(0.0, 1.0);
  }

  static bool hasVoiceEnergy(Uint8List pcm) {
    return rmsFromPcm16(pcm) >= minVoicedRms;
  }
}
