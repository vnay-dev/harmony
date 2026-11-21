import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Plays one clip and completes when it ends or is stopped.
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

  /// Length of the clip most recently loaded, when the player reported one.
  Duration? get duration;

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
  Duration? _duration;

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
  Duration? get duration => _duration ?? _player.duration;

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> load(String assetPath, {bool loop = false}) async {
    _duration = await _player.setAsset(
      assetPath,
      initialPosition: Duration.zero,
    );
    await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
  }

  @override
  Future<void> loadFile(String filePath, {bool loop = false}) async {
    _duration = await _player.setFilePath(
      filePath,
      initialPosition: Duration.zero,
    );
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

  /// Length of the file or asset loaded for the current clip.
  Duration? get duration => _transport.duration;

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
  Future<void> playToEnd(String assetPath, {void Function()? onStarted}) {
    return _playUntilEnd(
      () => _transport.load(assetPath),
      onStarted: onStarted,
    );
  }

  /// Plays a local file (for example a generated WAV) to completion.
  ///
  /// Uses the same pause, completion, and interrupt behavior as [playToEnd].
  Future<void> playFileToEnd(String filePath, {void Function()? onStarted}) {
    return _playUntilEnd(
      () => _transport.loadFile(filePath),
      onStarted: onStarted,
    );
  }

  Future<void> _playUntilEnd(
    Future<void> Function() load, {
    void Function()? onStarted,
  }) async {
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

      await load();
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
