import 'package:harmony/audio/audio_service.dart';

/// In-memory [AudioService] for tests.
class FakeAudioService implements AudioService {
  bool loaded = false;
  bool failLoad = false;
  bool failPlay = false;
  bool failPause = false;
  int loadCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;

  bool _isPlaying = false;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Future<void> load() async {
    loadCount += 1;
    if (failLoad) {
      throw AudioServiceException('Failed to load the tanpura sample.');
    }
    loaded = true;
  }

  @override
  Future<void> play() async {
    playCount += 1;
    if (failPlay) {
      throw AudioServiceException('Failed to play the tanpura sample.');
    }
    if (!loaded) {
      await load();
    }
    _isPlaying = true;
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
    if (failPause) {
      throw AudioServiceException('Failed to pause playback.');
    }
    _isPlaying = false;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    _isPlaying = false;
  }
}
