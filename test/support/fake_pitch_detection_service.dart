import 'dart:async';

import 'package:harmony/pitch/pitch_detection_service.dart';

/// In-memory [PitchDetectionService] for tests.
class FakePitchDetectionService implements PitchDetectionService {
  final StreamController<PitchReading> _controller =
      StreamController<PitchReading>.broadcast();

  bool failStart = false;
  int startCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  bool _isListening = false;

  @override
  Stream<PitchReading> get readings => _controller.stream;

  @override
  bool get isListening => _isListening;

  void emit(PitchReading reading) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(reading);
  }

  @override
  Future<void> start() async {
    startCount += 1;
    if (failStart) {
      throw PitchDetectionException('Microphone permission was denied.');
    }
    _isListening = true;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _isListening = false;
    if (!_controller.isClosed) {
      _controller.add(PitchReading.none);
    }
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    _isListening = false;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
