/// Contract for drone playback.
///
/// Implementations can be replaced later (for example to add pitch shifting
/// or multi-note Sa/Pa/Ma playback) without changing the UI layer.
abstract class AudioService {
  /// Whether the drone is currently playing.
  bool get isPlaying;

  /// Loads the tanpura sample and prepares it for looping playback.
  Future<void> load();

  /// Starts (or resumes) looping playback.
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
