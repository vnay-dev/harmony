import 'package:audio_session/audio_session.dart';

/// Configures the shared audio session for Assist Mode and drone playback.
///
/// Assist Mode V2 stops tanpura before pitch analysis, but still uses a
/// play-and-record session so transitions between playback and mic capture
/// do not tear down the audio route. Acoustic echo cancellation is not exposed
/// by the microphone capture path and is not relied on — stopping playback
/// before listening is the primary feedback protection.
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
