import 'package:harmony/audio/audio_service.dart';
import 'package:harmony/audio/reference_sound_generator.dart';

/// In-memory [ReferenceSoundGenerator] for tests.
class FakeReferenceSoundGenerator implements ReferenceSoundGenerator {
  bool failPlay = false;
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  final List<double> playedFrequencies = <double>[];
  final List<Duration> playedDurations = <Duration>[];

  bool _isPlaying = false;
  double? _currentFrequencyHz;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double? get currentFrequencyHz => _currentFrequencyHz;

  @override
  Future<void> playReference(
    double frequencyHz, {
    Duration duration = const Duration(seconds: 5),
  }) async {
    playCount += 1;
    if (failPlay) {
      throw AudioServiceException('Failed to play the reference tone.');
    }
    _currentFrequencyHz = frequencyHz;
    _isPlaying = true;
    playedFrequencies.add(frequencyHz);
    playedDurations.add(duration);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _isPlaying = false;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    _isPlaying = false;
    _currentFrequencyHz = null;
  }
}
