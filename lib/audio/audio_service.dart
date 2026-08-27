/// Contract for drone playback.
///
/// Implementations can be replaced later (for example to add multi-note
/// Sa/Pa/Ma playback) without changing the UI layer.
abstract class AudioService {
  /// Whether the drone is currently playing.
  bool get isPlaying;

  /// Asset path currently loaded, if any.
  String? get currentAsset;

  /// Loads [assetPath] for looping playback.
  ///
  /// If playback is already active, continues with the new sample. No-ops when
  /// [assetPath] is already loaded.
  Future<void> load(String assetPath);

  /// Starts (or resumes) looping playback of the loaded sample.
  Future<void> play();

  /// Pauses playback.
  Future<void> pause();

  /// Releases audio resources.
  Future<void> dispose();
}

/// Thrown when audio loading or playback fails.
class AudioServiceException implements Exception {
  AudioServiceException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'AudioServiceException: $message';
}
