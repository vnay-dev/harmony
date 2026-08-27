import 'package:harmony/audio/audio_service.dart';

/// In-memory [AudioService] for tests.
class FakeAudioService implements AudioService {
  bool failLoad = false;
  bool failPlay = false;
  bool failPause = false;
  int loadCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;
  final List<String> loadedAssets = <String>[];

  bool _isPlaying = false;
  String? _currentAsset;

  @override
  bool get isPlaying => _isPlaying;

  @override
  String? get currentAsset => _currentAsset;

  bool get loaded => _currentAsset != null;

  @override
  Future<void> load(String assetPath) async {
    loadCount += 1;
    if (failLoad) {
      throw AudioServiceException('Failed to load the tanpura sample.');
    }
    if (_currentAsset == assetPath) {
      return;
    }
    _currentAsset = assetPath;
    loadedAssets.add(assetPath);
  }

  @override
  Future<void> play() async {
    playCount += 1;
    if (failPlay) {
      throw AudioServiceException('Failed to play the tanpura sample.');
    }
    if (_currentAsset == null) {
      throw AudioServiceException('No tanpura sample is loaded.');
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
    _currentAsset = null;
  }
}
