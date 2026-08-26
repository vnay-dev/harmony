import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'package:harmony/audio/audio_assets.dart';
import 'package:harmony/audio/audio_service.dart';

/// [AudioService] backed by `just_audio` for looping tanpura playback.
class JustAudioService implements AudioService {
  JustAudioService({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  bool _isLoaded = false;

  @override
  bool get isPlaying => _player.playing;

  @override
  Future<void> load() async {
    try {
      await _player.setAsset(AudioAssets.tanpuraSample);
      await _player.setLoopMode(LoopMode.one);
      _isLoaded = true;
    } catch (error, stackTrace) {
      _isLoaded = false;
      Error.throwWithStackTrace(
        AudioServiceException('Failed to load the tanpura sample.', error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> play() async {
    try {
      if (!_isLoaded) {
        await load();
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
    _isLoaded = false;
    await _player.dispose();
  }
}
