import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'package:harmony/tutor/tutor_audio_catalog.dart';
import 'package:harmony/tutor/tutor_voice.dart';

/// Plays one bundled clip and completes when it ends or is stopped.
abstract class TutorClipPlayer {
  Future<void> playToEnd(String assetPath, {void Function()? onStarted});

  /// Cancels in-flight [playToEnd] and silences output without disposing the
  /// native player (so the next [playToEnd] can replace the source in place).
  Future<void> interrupt();

  Future<void> stop();

  Future<void> dispose();
}

/// Low-level tutor playback. Consecutive clips replace the source in place.
abstract class TutorClipTransport {
  bool get isIdle;

  /// Whether just_audio currently reports [AudioPlayer.playing].
  ///
  /// Remains true after a clip reaches [ProcessingState.completed] until
  /// [pause] or [stop] — callers must clear it before the next [play].
  bool get isPlaying;

  ProcessingState get processingState;

  Stream<ProcessingState> get processingStateStream;

  /// Keeps the native player alive while clearing the playing flag.
  Future<void> pause();

  /// Loads [assetPath] from the start without disposing the player.
  ///
  /// When [loop] is true, the player repeats the clip until paused or stopped.
  Future<void> load(String assetPath, {bool loop = false});

  /// Loads a local file path (e.g. a generated reference-tone WAV).
  Future<void> loadFile(String filePath, {bool loop = false});

  Future<void> play();

  Future<void> stop();

  Future<void> dispose();
}

/// [TutorClipTransport] backed by one long-lived `just_audio` player.
class JustAudioTutorClipTransport implements TutorClipTransport {
  JustAudioTutorClipTransport({AudioPlayer? player})
    : _player = player ?? AudioPlayer(handleInterruptions: false);

  final AudioPlayer _player;

  @override
  bool get isIdle => _player.processingState == ProcessingState.idle;

  @override
  bool get isPlaying => _player.playing;

  @override
  ProcessingState get processingState => _player.processingState;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> load(String assetPath, {bool loop = false}) async {
    await _player.setAsset(assetPath, initialPosition: Duration.zero);
    await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
  }

  @override
  Future<void> loadFile(String filePath, {bool loop = false}) async {
    await _player.setFilePath(filePath, initialPosition: Duration.zero);
    await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    await _player.stop();
    await _player.dispose();
  }
}

/// [TutorClipPlayer] backed by `just_audio`.
///
/// A finished clip stays loaded. The next clip pauses and replaces the source
/// instead of stopping the native player, which is what produced a pop between
/// sentences and could Release/Init ExoPlayer between short lines.
/// [stop] still tears playback down immediately for cancel / dispose.
class JustAudioTutorClipPlayer implements TutorClipPlayer {
  JustAudioTutorClipPlayer({AudioPlayer? player, TutorClipTransport? transport})
    : _transport = transport ?? JustAudioTutorClipTransport(player: player);

  final TutorClipTransport _transport;
  int _token = 0;
  bool _disposed = false;
  Completer<void>? _finished;

  bool _isCurrent(int token) => !_disposed && token == _token;

  void _finishWaiting() {
    final pending = _finished;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  Future<void> _clearPlayingFlag() async {
    // just_audio keeps playing=true after natural completion. play() then
    // returns immediately without starting the next clip.
    if (_transport.isPlaying || !_transport.isIdle) {
      await _transport.pause();
    }
  }

  @override
  Future<void> playToEnd(String assetPath, {void Function()? onStarted}) async {
    final token = ++_token;
    if (_disposed) {
      return;
    }

    final finished = Completer<void>();
    _finished = finished;
    StreamSubscription<ProcessingState>? subscription;

    try {
      await _clearPlayingFlag();
      if (!_isCurrent(token)) {
        return;
      }

      await _transport.load(assetPath);
      if (!_isCurrent(token)) {
        return;
      }

      // Only treat completed as end-of-clip after we have left completed from
      // a prior source (ready/buffering/loading). Avoids a stale completed
      // finishing this clip before it audibly starts.
      var armed = false;
      subscription = _transport.processingStateStream.listen((state) {
        if (!_isCurrent(token)) {
          return;
        }
        if (state == ProcessingState.ready ||
            state == ProcessingState.buffering ||
            state == ProcessingState.loading) {
          armed = true;
          return;
        }
        if (armed && state == ProcessingState.completed) {
          _finishWaiting();
        }
      });

      // Load usually leaves the player ready before play(); arm explicitly.
      if (_transport.processingState == ProcessingState.ready ||
          _transport.processingState == ProcessingState.buffering ||
          _transport.processingState == ProcessingState.loading) {
        armed = true;
      }

      onStarted?.call();

      final playFuture = _transport.play();
      unawaited(
        playFuture
            .then<void>((_) {
              // play() completes when playback ends, pauses, or stops — not
              // when it starts. Finish only when this token is still current.
              if (_isCurrent(token)) {
                _finishWaiting();
              }
            })
            .catchError((Object error, StackTrace stackTrace) {
              if (finished.isCompleted) {
                return;
              }
              if (_isCurrent(token)) {
                finished.completeError(error, stackTrace);
              } else {
                finished.complete();
              }
            }),
      );

      if (!_isCurrent(token)) {
        _finishWaiting();
      }
      await finished.future;
    } catch (error) {
      if (!_isCurrent(token)) {
        return;
      }
      rethrow;
    } finally {
      await subscription?.cancel();
      if (identical(_finished, finished)) {
        _finished = null;
      }
    }
  }

  @override
  Future<void> interrupt() async {
    _token++;
    _finishWaiting();
    if (_disposed) {
      return;
    }
    // Pause keeps the ExoPlayer instance warm. Hard stop() Releases it and the
    // next short clip can be swallowed during Init on some devices.
    await _clearPlayingFlag();
  }

  @override
  Future<void> stop() async {
    _token++;
    _finishWaiting();
    if (_disposed) {
      return;
    }
    await _transport.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _token++;
    _finishWaiting();
    await _transport.dispose();
  }
}

/// Plays the pre-generated tutor recordings.
///
/// Prefer [playAssets] with ids from a resolved [TutorDialogue]. [speak] remains
/// for completion lines and tests that still pass script text.
class AssetTutorVoice implements TutorVoice {
  AssetTutorVoice({TutorClipPlayer? clips})
    : _clips = clips ?? JustAudioTutorClipPlayer();

  final TutorClipPlayer _clips;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _pending = Future<void>.value();

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  static void _log(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
      developer.log(message, name: tag);
    }
  }

  @override
  Future<void> speak(String text, {void Function()? onStarted}) {
    if (_disposed) {
      return Future<void>.value();
    }
    final assetIds = TutorAudioCatalog.assetIdsForSpokenLine(text);
    return playAssets(assetIds, onStarted: onStarted);
  }

  @override
  Future<void> playAssets(List<String> assetIds, {void Function()? onStarted}) {
    if (_disposed) {
      return Future<void>.value();
    }
    final generation = ++_generation;
    // Soft-interrupt the current clip (pause + cancel wait). Do not hard-stop:
    // stop() Releases ExoPlayer and the next load pays Init cost; on device that
    // race has silenced a short clip while its transcript was already on screen.
    final interrupted = _clips.interrupt();
    final result =
        Future.wait<void>([
          _pending.catchError((Object _) {}),
          interrupted,
        ]).then((_) async {
          if (!_isCurrent(generation)) {
            return;
          }
          await _playAssets(assetIds, generation, onStarted: onStarted);
        });
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> _playAssets(
    List<String> assetIds,
    int generation, {
    void Function()? onStarted,
  }) async {
    if (!_isCurrent(generation)) {
      return;
    }
    if (assetIds.isEmpty) {
      onStarted?.call();
      return;
    }
    var started = false;
    for (final assetId in assetIds) {
      if (!_isCurrent(generation)) {
        return;
      }
      final path = TutorAudioCatalog.assetPath(assetId);
      _log('TUTOR', 'id=$assetId audio=$assetId.mp3 path=$path');
      await _clips.playToEnd(
        path,
        onStarted: started
            ? null
            : () {
                started = true;
                onStarted?.call();
              },
      );
    }
    if (!started) {
      onStarted?.call();
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    // Drop queued play requests so a cancelled dialogue cannot start later.
    _pending = Future<void>.value();
    await _clips.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation++;
    _pending = Future<void>.value();
    await _clips.stop();
    await _clips.dispose();
  }
}
