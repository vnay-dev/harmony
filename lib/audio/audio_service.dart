/// Handles tanpura drone playback.
///
/// Keeps audio logic separate from the Flutter UI. Playback against real
/// recordings will be implemented later — this class defines the service
/// boundary for V1 (play and pause).
class AudioService {
  bool _isPlaying = false;

  /// Whether the drone is currently playing.
  bool get isPlaying => _isPlaying;

  /// Starts drone playback.
  ///
  /// Not implemented yet. Will load and loop tanpura recordings.
  Future<void> play() async {
    throw UnimplementedError('Audio playback is not implemented yet.');
  }

  /// Pauses drone playback.
  ///
  /// Not implemented yet.
  Future<void> pause() async {
    throw UnimplementedError('Audio pause is not implemented yet.');
  }

  /// Releases audio resources.
  Future<void> dispose() async {
    _isPlaying = false;
  }
}
