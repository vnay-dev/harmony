import 'package:audio_session/audio_session.dart';

/// Configures the shared audio session for Assist Mode and drone playback.
///
/// Assist Mode V2 stops tanpura before pitch analysis, but still uses a
/// play-and-record session so transitions between playback and mic capture
/// do not tear down the audio route.
///
/// The reference tone is played by a separate `just_audio` player. The
/// microphone is a raw PCM capture from `record`. Those paths do not share an
/// echo-cancellation reference, so a frequency heard while the tone is playing
/// cannot be attributed to the singer. Assisted singing must not treat that
/// frequency as the user's match.
const bool assistedUserVocalIsolationAvailable = false;

/// Assist Mode V2 stops tanpura before pitch analysis, but still uses a
/// play-and-record session so transitions between playback and mic capture
/// do not tear down the audio route. Acoustic echo cancellation is not
/// available for the separate reference player, so stopping playback before
/// normal listening is the feedback protection.
Future<void> ensurePlayAndRecordAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(
    AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.mixWithOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,
    ),
  );
  await session.setActive(true);
}

/// Drops playback focus so the platform speech recognizer can open the mic.
///
/// Failures are ignored: unit tests have no platform audio session.
Future<void> suspendAudioSessionForSpeechRecognition() async {
  try {
    final session = await AudioSession.instance;
    await session.setActive(false);
  } catch (_) {}
}
