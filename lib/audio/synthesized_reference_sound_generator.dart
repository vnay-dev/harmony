import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'package:harmony/audio/audio_service.dart';
import 'package:harmony/audio/reference_sound_generator.dart';
import 'package:harmony/audio/reference_tone_temp_file.dart';
import 'package:harmony/audio/reference_tone_wav.dart';

/// Stage 2 reference tones synthesized in-memory and played via `just_audio`.
///
/// WAV bytes are written to a temporary local file and loaded with
/// [AudioPlayer.setFilePath]. This avoids Android cleartext-HTTP rejection of
/// just_audio's in-memory [StreamAudioSource] proxy.
///
/// Does not touch Stage 1 Tanpura assets or [AudioService].
class SynthesizedReferenceSoundGenerator implements ReferenceSoundGenerator {
  SynthesizedReferenceSoundGenerator({
    AudioPlayer? player,
    Directory? tempDirectory,
  }) : _player = player ?? AudioPlayer(handleInterruptions: false),
       _tempDirectory = tempDirectory;

  final AudioPlayer _player;
  final Directory? _tempDirectory;
  double? _currentFrequencyHz;
  bool _isPlaying = false;
  bool _isDisposed = false;
  File? _activeTempFile;

  @override
  bool get isPlaying => _isPlaying && _player.playing;

  @override
  double? get currentFrequencyHz => _currentFrequencyHz;

  @override
  Future<void> playReference(
    double frequencyHz, {
    Duration duration = const Duration(seconds: 5),
  }) async {
    if (_isDisposed) {
      throw AudioServiceException('Reference sound generator is disposed.');
    }
    if (frequencyHz <= 0 || !frequencyHz.isFinite) {
      throw AudioServiceException('Reference frequency must be positive.');
    }

    _diag('targetHz=${frequencyHz.toStringAsFixed(2)}');
    _diag('durationMs=${duration.inMilliseconds}');
    _diag('sourceStrategy=tempFile+setFilePath');

    var step = 'init';
    try {
      step = 'stopPrevious';
      _diag('step=$step');
      await _player.stop();
      await _deleteActiveTempFile();
      _diag('stopPrevious=success');

      step = 'wavGenerate';
      _diag('step=$step');
      _diag('wavGenerate=start');
      final wav = buildReferenceToneWav(
        frequencyHz: frequencyHz,
        duration: duration,
      );
      _diag('wavBytes=${wav.length}');
      final header = inspectReferenceToneWav(wav);
      _diag('wavHeader=${header.summary}');
      _diag('wavHeaderValid=${header.isValid}');

      step = 'writeTempFile';
      _diag('step=$step');
      final tempFile = await writeReferenceToneTempFile(
        wav,
        directory: _tempDirectory,
      );
      _activeTempFile = tempFile;
      final exists = await tempFile.exists();
      final fileLength = exists ? await tempFile.length() : -1;
      _diag('tempPath=${tempFile.path}');
      _diag('tempExists=$exists');
      _diag('tempLength=$fileLength');
      if (!exists || fileLength != wav.length) {
        throw AudioServiceException(
          'Failed to write the reference tone temp file.',
        );
      }
      _diag('writeTempFile=success');

      step = 'setFilePath';
      _diag('step=$step');
      await _player.setFilePath(tempFile.path);
      _diag('setFilePath=success');
      _diag(
        'playerAfterSetFilePath playing=${_player.playing} '
        'processingState=${_player.processingState} '
        'duration=${_player.duration}',
      );

      step = 'setLoopMode';
      _diag('step=$step');
      await _player.setLoopMode(LoopMode.off);
      _diag('setLoopMode=success');

      _currentFrequencyHz = frequencyHz;
      _isPlaying = true;

      step = 'play';
      _diag('step=$step');
      // just_audio's play() Future completes when playback ends; do not await
      // so Assist Mode can own the play window timing.
      unawaited(
        _player.play().then((_) {
          _diag('playFuture=completed');
        }).catchError((Object error, StackTrace stackTrace) {
          _diagError(
            step: 'playFuture',
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
      _diag('play=success');
      _diag(
        'playerAfterPlay playing=${_player.playing} '
        'processingState=${_player.processingState}',
      );
    } catch (error, stackTrace) {
      _isPlaying = false;
      _currentFrequencyHz = null;
      await _deleteActiveTempFile();
      _diagError(step: step, error: error, stackTrace: stackTrace);
      if (error is AudioServiceException) {
        rethrow;
      }
      Error.throwWithStackTrace(
        AudioServiceException('Failed to play the reference tone.', error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_isDisposed) {
      return;
    }
    try {
      _diag('stop=start');
      await _player.stop();
      _diag('stop=success');
    } catch (error, stackTrace) {
      _diagError(step: 'stop', error: error, stackTrace: stackTrace);
      try {
        await _player.pause();
        _diag('stopFallbackPause=success');
      } catch (pauseError, pauseStack) {
        _diagError(
          step: 'stopFallbackPause',
          error: pauseError,
          stackTrace: pauseStack,
        );
      }
    } finally {
      _isPlaying = false;
      await _deleteActiveTempFile();
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _isPlaying = false;
    _currentFrequencyHz = null;
    try {
      await _player.stop();
    } catch (_) {}
    await _player.dispose();
    await _deleteActiveTempFile();
  }

  Future<void> _deleteActiveTempFile() async {
    final file = _activeTempFile;
    _activeTempFile = null;
    if (file == null) {
      return;
    }
    _diag('tempCleanup path=${file.path}');
    await deleteReferenceToneTempFile(file);
    _diag('tempCleanup=done');
  }

  void _diag(String message) {
    debugPrint('ReferenceToneDiag $message');
  }

  void _diagError({
    required String step,
    required Object error,
    required StackTrace stackTrace,
  }) {
    _diag('ERROR step=$step');
    _diag('errorType=${error.runtimeType}');
    _diag('error=$error');
    if (error is AudioServiceException && error.cause != null) {
      _diag('causeType=${error.cause.runtimeType}');
      _diag('cause=${error.cause}');
    }
    _diag('stack=$stackTrace');
  }
}
