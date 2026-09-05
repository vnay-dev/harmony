import 'dart:async';
import 'dart:typed_data';

import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:record/record.dart';

import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';

/// Microphone pitch detection using PCM capture + the YIN algorithm.
///
/// Uses the `record` package for a raw PCM16 stream and `pitch_detector_dart`
/// (TarsosDSP YIN port) for fundamental-frequency estimation.
///
/// Always analyses the most recent audio window. Stale backlog is discarded so
/// detection latency cannot grow without bound when analysis briefly falls
/// behind the microphone stream.
class MicPitchDetectionService implements PitchDetectionService {
  MicPitchDetectionService({
    AudioRecorder? recorder,
    PitchDetector? detector,
    this.sampleRate = 22050,
    this.bufferSize = 1024,
    this.minProbability = 0.8,
  }) : _recorder = recorder ?? AudioRecorder(),
       _detector =
           detector ??
           PitchDetector(
             audioSampleRate: sampleRate.toDouble(),
             bufferSize: bufferSize,
           );

  /// Capture rate. 22050 Hz keeps ~46 ms windows with a smaller YIN workload
  /// than 44100/2048.
  final int sampleRate;

  /// Analysis window in samples (~46 ms at [sampleRate]).
  final int bufferSize;

  /// Minimum YIN probability required to accept a reading.
  final double minProbability;

  final AudioRecorder _recorder;
  final PitchDetector _detector;

  final StreamController<PitchReading> _readingsController =
      StreamController<PitchReading>.broadcast();
  final BytesBuilder _pcmBuffer = BytesBuilder(copy: false);

  StreamSubscription<Uint8List>? _audioSubscription;
  bool _isListening = false;
  bool _isDetecting = false;
  bool _isDisposed = false;

  int get _bytesPerBuffer => bufferSize * 2; // PCM16 = 2 bytes per sample

  /// Keep at most two windows while a detection is in flight.
  int get _maxBufferedBytes => _bytesPerBuffer * 2;

  @override
  Stream<PitchReading> get readings => _readingsController.stream;

  @override
  bool get isListening => _isListening;

  @override
  Future<void> start() async {
    if (_isDisposed) {
      throw PitchDetectionException('Pitch detection has been disposed.');
    }
    if (_isListening) {
      return;
    }

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        throw PitchDetectionException('Microphone permission was denied.');
      }

      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
      );

      _pcmBuffer.clear();
      _isListening = true;
      _audioSubscription = stream.listen(
        _onAudioChunk,
        onError: (Object error, StackTrace stackTrace) {
          if (!_readingsController.isClosed) {
            _readingsController.addError(
              PitchDetectionException('Microphone stream failed.', error),
              stackTrace,
            );
          }
        },
      );
    } on PitchDetectionException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        PitchDetectionException('Failed to start listening.', error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> stop() async {
    if (!_isListening) {
      return;
    }

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _pcmBuffer.clear();
    _isListening = false;

    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {
      // Best-effort stop; listening state is already cleared.
    }

    if (!_readingsController.isClosed) {
      _readingsController.add(PitchReading.none);
    }
  }

  void _onAudioChunk(Uint8List chunk) {
    if (!_isListening || _isDisposed) {
      return;
    }

    _pcmBuffer.add(chunk);
    _trimStaleAudio();
    _pumpDetection();
  }

  /// Drops older samples so the buffer never holds minutes of lagged audio.
  void _trimStaleAudio() {
    if (_pcmBuffer.length <= _maxBufferedBytes) {
      return;
    }

    final bytes = _pcmBuffer.takeBytes();
    _pcmBuffer.add(bytes.sublist(bytes.length - _maxBufferedBytes));
  }

  /// Starts detection on the latest full window when the detector is idle.
  void _pumpDetection() {
    if (!_isListening || _isDisposed || _isDetecting) {
      return;
    }
    if (_pcmBuffer.length < _bytesPerBuffer) {
      return;
    }

    final bytes = _pcmBuffer.takeBytes();
    final windowStart = bytes.length - _bytesPerBuffer;
    // Copy so the async detector owns a stable snapshot of the latest audio.
    final window = Uint8List.fromList(bytes.sublist(windowStart));
    unawaited(_detectPitch(window));
  }

  Future<void> _detectPitch(Uint8List pcmWindow) async {
    _isDetecting = true;
    try {
      final result = await _detector.getPitchFromIntBuffer(pcmWindow);
      if (_readingsController.isClosed || !_isListening) {
        return;
      }

      final isReliable =
          result.pitched &&
          result.probability >= minProbability &&
          result.pitch > 0;

      if (!isReliable) {
        _readingsController.add(PitchReading.none);
        return;
      }

      _readingsController.add(
        PitchReading(
          hasPitch: true,
          frequencyHz: result.pitch,
          note: noteFromFrequency(result.pitch),
        ),
      );
    } catch (error, stackTrace) {
      if (!_readingsController.isClosed) {
        _readingsController.addError(
          PitchDetectionException('Failed to detect pitch.', error),
          stackTrace,
        );
      }
    } finally {
      _isDetecting = false;
      // Immediately continue with whatever arrived during analysis.
      _pumpDetection();
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await stop();
    await _recorder.dispose();
    await _readingsController.close();
  }
}
