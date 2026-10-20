import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kittentts/kittentts.dart';

import 'package:harmony/tutor/kitten_tutor_voice.dart';

/// Approved production KittenTTS settings for Harmony tutor speech.
///
/// Source of truth from the Harmony voice-lab experiments:
/// Kitten TTS, Micro model, Luna voice, 1.1× speed, analytics off,
/// on-device WAV at [sampleRateHz] (24 kHz) after the initial model download.
abstract final class KittenTtsDefaults {
  static const String model = 'micro';
  static const String voice = 'luna';
  static const double speed = 1.1;

  /// KittenTTS output sample rate. Matches package `outputSampleRate`.
  static const int sampleRateHz = 24000;

  /// Micro + Luna + 1.1× with analytics off. Used by every production path.
  static KittenTTSConfig config({
    String? storageDirectory,
    KittenTTSModelFiles? modelFiles,
  }) {
    return KittenTTSConfig(
      model: model,
      defaultVoice: voice,
      speed: speed,
      analytics: false,
      storageDirectory: storageDirectory,
      modelFiles: modelFiles,
    );
  }
}

/// Opens a [KittenTutorSynthesizer] for [KittenTtsBootstrap].
///
/// Production uses [KittenTtsBootstrap.openSdk]. Tests inject a fake so no
/// model is downloaded.
typedef KittenTtsOpener =
    Future<KittenTutorSynthesizer> Function({
      required KittenTTSConfig config,
      ProgressHandler? onProgress,
      bool forceRedownload,
    });

/// Wraps a live [KittenTTS] instance for [KittenTutorVoice].
class KittenSdkSynthesizer implements KittenTutorSynthesizer {
  KittenSdkSynthesizer(
    this._tts, {
    this.voice = KittenTtsDefaults.voice,
    this.speed = KittenTtsDefaults.speed,
  });

  final KittenTTS _tts;
  final String voice;
  final double speed;

  @override
  Future<KittenTutorAudio> synthesize(String text) async {
    final result = await _tts.generate(text, voice: voice, speed: speed);
    // wavData() is 16-bit PCM WAV at KittenTTS outputSampleRate (24 kHz).
    final ms = (result.duration * 1000).round();
    return KittenTutorAudio(
      wavBytes: result.wavData(),
      duration: ms > 0 ? Duration(milliseconds: ms) : null,
    );
  }

  @override
  Future<void> dispose() => _tts.dispose();
}

/// Ready-state for first-run model download / cache load.
enum KittenTtsReadyState {
  /// [ensureReady] has not been called, or resources were disposed.
  idle,

  /// Download or ONNX session setup is in progress.
  loading,

  /// [synthesizer] is ready for [KittenTutorVoice].
  ready,

  /// Last [ensureReady] / [retry] failed; call [retry].
  failed,
}

/// Downloads and initializes Kitten Micro, reporting progress and allowing retry.
///
/// Caches model files through the KittenTTS SDK. Later [ensureReady] calls reuse
/// the cache. Does not speak audio — hand [synthesizer] to [KittenTutorVoice].
///
/// Assist Mode uses this by default before starting the tutor session (unless
/// HTTP tutor voice is selected).
class KittenTtsBootstrap extends ChangeNotifier {
  KittenTtsBootstrap({KittenTTSConfig? config, KittenTtsOpener? open})
    : _config = config ?? KittenTtsDefaults.config(),
      _open = open ?? openSdk;

  final KittenTTSConfig _config;
  final KittenTtsOpener _open;

  KittenTtsReadyState _state = KittenTtsReadyState.idle;
  double _progress = 0;
  DownloadProgressInfo? _progressInfo;
  Object? _error;
  KittenTutorSynthesizer? _synthesizer;
  Future<KittenTutorSynthesizer>? _inFlight;
  bool _disposed = false;

  KittenTTSConfig get config => _config;

  KittenTtsReadyState get state => _state;

  /// Setup progress from `0` to `1` while [state] is [KittenTtsReadyState.loading].
  double get progress => _progress;

  /// Latest KittenTTS progress details, when the opener reported them.
  DownloadProgressInfo? get progressInfo => _progressInfo;

  /// Failure from the last attempt, when [state] is [KittenTtsReadyState.failed].
  Object? get error => _error;

  /// Ready synthesizer, or null until [ensureReady] succeeds.
  KittenTutorSynthesizer? get synthesizer => _synthesizer;

  bool get isReady =>
      _state == KittenTtsReadyState.ready && _synthesizer != null;

  /// Production opener: [KittenTTS.create] with analytics already disabled in
  /// [config].
  static Future<KittenTutorSynthesizer> openSdk({
    required KittenTTSConfig config,
    ProgressHandler? onProgress,
    bool forceRedownload = false,
  }) async {
    final tts = await KittenTTS.create(
      config: config,
      onProgress: onProgress,
      forceRedownload: forceRedownload,
    );
    return KittenSdkSynthesizer(
      tts,
      voice: config.defaultVoice,
      speed: config.speed,
    );
  }

  /// Initializes the model (download if needed) and returns a synthesizer.
  ///
  /// Concurrent callers share one in-flight future. When already ready, returns
  /// the cached synthesizer unless [forceRedownload] is true.
  Future<KittenTutorSynthesizer> ensureReady({bool forceRedownload = false}) {
    if (_disposed) {
      return Future<KittenTutorSynthesizer>.error(
        StateError('KittenTtsBootstrap is disposed.'),
      );
    }
    if (!forceRedownload && _synthesizer != null && isReady) {
      return Future<KittenTutorSynthesizer>.value(_synthesizer!);
    }
    final existing = _inFlight;
    if (existing != null && !forceRedownload) {
      return existing;
    }

    final future = _openReady(forceRedownload: forceRedownload);
    _inFlight = future;
    return future;
  }

  /// Retries after [KittenTtsReadyState.failed].
  ///
  /// Uses a normal create (cache preserved). Pass [forceRedownload] to clear and
  /// fetch model files again.
  Future<KittenTutorSynthesizer> retry({bool forceRedownload = false}) {
    return ensureReady(forceRedownload: forceRedownload);
  }

  Future<KittenTutorSynthesizer> _openReady({
    required bool forceRedownload,
  }) async {
    _state = KittenTtsReadyState.loading;
    _progress = 0;
    _progressInfo = null;
    _error = null;
    _emit();

    final previous = _synthesizer;
    _synthesizer = null;
    if (previous != null) {
      try {
        await previous.dispose();
      } catch (_) {
        // Replace the old engine even if dispose fails.
      }
    }

    try {
      final synthesizer = await _open(
        config: _config,
        onProgress: (progress, [info]) {
          if (_disposed || _state != KittenTtsReadyState.loading) {
            return;
          }
          _progress = progress.clamp(0, 1);
          _progressInfo = info;
          _emit();
        },
        forceRedownload: forceRedownload,
      );
      if (_disposed) {
        await synthesizer.dispose();
        throw StateError('KittenTtsBootstrap is disposed.');
      }
      _synthesizer = synthesizer;
      _state = KittenTtsReadyState.ready;
      _progress = 1;
      _error = null;
      _emit();
      return synthesizer;
    } catch (error) {
      if (!_disposed) {
        _state = KittenTtsReadyState.failed;
        _error = error;
        _progress = 0;
        _emit();
      }
      rethrow;
    } finally {
      _inFlight = null;
    }
  }

  void _emit() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _inFlight = null;
    final synthesizer = _synthesizer;
    _synthesizer = null;
    _state = KittenTtsReadyState.idle;
    unawaited(synthesizer?.dispose() ?? Future<void>.value());
    super.dispose();
  }
}
