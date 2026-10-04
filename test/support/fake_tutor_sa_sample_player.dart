import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'package:harmony/tutor/asset_tutor_voice.dart';
import 'package:harmony/tutor/tutor_sa_sample_player.dart';

/// Controllable [TutorClipTransport] for Hear Sa unit tests.
class FakeTutorSaClipTransport implements TutorClipTransport {
  final List<String> loaded = <String>[];
  final List<String> loadedFiles = <String>[];
  final List<bool> loadedLoop = <bool>[];
  int playCount = 0;
  int pauseCount = 0;
  int stopCount = 0;
  ProcessingState _state = ProcessingState.idle;
  final StreamController<ProcessingState> _states =
      StreamController<ProcessingState>.broadcast();

  @override
  bool get isIdle => _state == ProcessingState.idle;

  @override
  bool get isPlaying =>
      _state != ProcessingState.idle && _state != ProcessingState.completed;

  @override
  ProcessingState get processingState => _state;

  @override
  Stream<ProcessingState> get processingStateStream => _states.stream;

  void _setState(ProcessingState state) {
    _state = state;
    _states.add(state);
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
    _setState(ProcessingState.ready);
  }

  @override
  Future<void> load(String assetPath, {bool loop = false}) async {
    loaded.add(assetPath);
    loadedLoop.add(loop);
    _setState(ProcessingState.ready);
  }

  @override
  Future<void> loadFile(String filePath, {bool loop = false}) async {
    loadedFiles.add(filePath);
    loadedLoop.add(loop);
    _setState(ProcessingState.ready);
  }

  @override
  Future<void> play() async {
    playCount += 1;
    _setState(ProcessingState.ready);
  }

  /// Emits completed without implying the sample player should stop.
  void finish() {
    _setState(ProcessingState.completed);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _setState(ProcessingState.idle);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _states.close();
  }
}

/// Convenience builder used by TutorSession tests.
TutorSaSamplePlayer buildFakeSaSamplePlayer({
  FakeTutorSaClipTransport? transport,
}) {
  final activeTransport = transport ?? FakeTutorSaClipTransport();
  return TutorSaSamplePlayer(
    transport: activeTransport,
    buildWav: (_) => Uint8List.fromList(const <int>[1, 2, 3, 4]),
    writeTempFile: (bytes, {Directory? directory}) async {
      return File('${directory?.path ?? 'test'}/sa_example.wav');
    },
  );
}
