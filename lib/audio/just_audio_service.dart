import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'package:harmony/audio/audio_service.dart';

/// [AudioService] backed by `just_audio` for looping tanpura sample playback.
class JustAudioService implements AudioService {
  JustAudioService({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  String? _currentAsset;

  @override
  bool get isPlaying => _player.playing;

  @override
  String? get currentAsset => _currentAsset;

  @override
  Future<void> load(String assetPath) async {
    if (_currentAsset == assetPath) {
      return;
    }

    final wasPlaying = _player.playing;

    try {
      await _player.setAsset(assetPath);
      await _player.setLoopMode(LoopMode.one);
      _currentAsset = assetPath;
      if (wasPlaying) {
        // Resume after the sample swap; do not await play() (see [play]).
        unawaited(_player.play());
      }
    } catch (error, stackTrace) {
      _currentAsset = null;
      Error.throwWithStackTrace(
        AudioServiceException('Failed to load the tanpura sample.', error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> play() async {
    try {
      if (_currentAsset == null) {
        throw AudioServiceException('No tanpura sample is loaded.');
      }
      // just_audio's play() Future completes when playback ends or is paused,
      // not when it starts. With looping, awaiting it would hang forever and
      // the UI would never leave the busy/play state.
      unawaited(_player.play());
    } catch (error, stackTrace) {
      if (error is AudioServiceException) {
        rethrow;
      }
      Error.throwWithStackTrace(
        AudioServiceException('Failed to play the tanpura sample.', error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AudioServiceException('Failed to pause playback.', error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> dispose() async {
    _currentAsset = null;
    await _player.dispose();
  }
}
