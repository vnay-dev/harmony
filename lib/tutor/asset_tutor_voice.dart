import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'package:harmony/tutor/tutor_audio_catalog.dart';
import 'package:harmony/tutor/tutor_voice.dart';

/// Plays one bundled clip and completes when it ends or is stopped.
abstract class TutorClipPlayer {
  Future<void> playToEnd(String assetPath);

  Future<void> stop();

  Future<void> dispose();
}

/// Low-level tutor playback. Consecutive clips replace the source in place.
abstract class TutorClipTransport {
  bool get isIdle;

  ProcessingState get processingState;

  Stream<ProcessingState> get processingStateStream;

  /// Keeps the native player alive while clearing the playing flag.
  Future<void> pause();

  /// Loads [assetPath] from the start without disposing the player.
  Future<void> load(String assetPath);

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
  ProcessingState get processingState => _player.processingState;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> load(String assetPath) async {
    await _player.setAsset(assetPath, initialPosition: Duration.zero);
    await _player.setLoopMode(LoopMode.off);
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
/// sentences. [stop] still tears playback down immediately.
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

  @override
  Future<void> playToEnd(String assetPath) async {
    final token = ++_token;
    if (_disposed) {
      return;
    }

    final finished = Completer<void>();
    _finished = finished;
    StreamSubscription<ProcessingState>? subscription;

    try {
      if (!_transport.isIdle) {
        await _transport.pause();
        if (!_isCurrent(token)) {
          return;
        }
      }

      await _transport.load(assetPath);
      if (!_isCurrent(token)) {
        return;
      }

      // skip(1) drops the replayed current state so a previous clip's
      // completed event cannot finish this one before it plays.
      subscription = _transport.processingStateStream.skip(1).listen((state) {
        if (state == ProcessingState.completed) {
          _finishWaiting();
        }
      });

      final playFuture = _transport.play();
      unawaited(
        playFuture
            .then<void>((_) {
              if (!_isCurrent(token) ||
                  _transport.processingState == ProcessingState.completed) {
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
/// [speak] accepts the script line the session already uses, or an asset id
/// such as `S01`. The id-to-file mapping lives in [TutorAudioCatalog].
class AssetTutorVoice implements TutorVoice {
  AssetTutorVoice({TutorClipPlayer? clips})
    : _clips = clips ?? JustAudioTutorClipPlayer();

  final TutorClipPlayer _clips;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _pending = Future<void>.value();

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  Future<void> speak(String text) {
    if (_disposed) {
      return Future<void>.value();
    }
    final generation = ++_generation;
    final result = _pending.then((_) => _playLine(text, generation));
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> _playLine(String text, int generation) async {
    if (!_isCurrent(generation)) {
      return;
    }
    final assetIds = TutorAudioCatalog.assetIdsForSpokenLine(text);
    for (final assetId in assetIds) {
      if (!_isCurrent(generation)) {
        return;
      }
      await _clips.playToEnd(TutorAudioCatalog.assetPath(assetId));
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _clips.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation++;
    await _clips.stop();
    await _pending.catchError((Object _) {});
    await _clips.dispose();
  }
}
