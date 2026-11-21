import 'package:vibration/vibration.dart';

/// Haptics for the latching play button.
///
/// Calls the vibrator directly. Capability probes + short timeouts were
/// cancelling the vibration before it ran on some Android OEMs (Oppo/etc.).
class PlayButtonHaptics {
  const PlayButtonHaptics._();

  /// Press-in (start playing): short, moderate pulse.
  static Future<void> pressIn() async {
    try {
      await Vibration.vibrate(duration: 28, amplitude: 140);
    } on Object {
      try {
        await Vibration.vibrate(duration: 28);
      } on Object {
        // Best-effort only.
      }
    }
  }

  /// Release (pause): lighter, shorter tick.
  static Future<void> release() async {
    try {
      await Vibration.vibrate(duration: 16, amplitude: 70);
    } on Object {
      try {
        await Vibration.vibrate(duration: 16);
      } on Object {
        // Best-effort only.
      }
    }
  }
}
