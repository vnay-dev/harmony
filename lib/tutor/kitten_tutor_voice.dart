import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:harmony/audio/reference_tone_temp_file.dart';
import 'package:harmony/tutor/asset_tutor_voice.dart';
import 'package:harmony/tutor/kitten_speech_text.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_voice.dart';

/// WAV bytes plus optional duration from an on-device TTS engine.
class KittenTutorAudio {
  const KittenTutorAudio({required this.wavBytes, this.duration});

  final Uint8List wavBytes;

  /// Engine-reported length. Playback may still prefer the loaded clip length.
  final Duration? duration;
}

/// Produces tutor speech audio. Production uses [KittenSdkSynthesizer].
///
/// Tests inject a fake so unit tests never download or load a real model.
abstract class KittenTutorSynthesizer {
  Future<KittenTutorAudio> synthesize(String text);

  Future<void> dispose();
}

/// Speaks tutor lines with on-device KittenTTS audio.
///
/// Production uses Micro + Luna at 1.1× (see [KittenTtsDefaults]). Dialogue
/// ids resolve to catalog text; synthesized 24 kHz WAV bytes play through
/// [JustAudioTutorClipPlayer]. [synchronizesTranscript] stays true so the
/// typewriter waits for [onStarted] / [playbackDuration].
///
/// Pass a ready [KittenTutorSynthesizer] from [KittenTtsBootstrap]. This voice
/// does not download the model itself.
class KittenTutorVoice implements TutorVoice {
  KittenTutorVoice({
    required KittenTutorSynthesizer synthesizer,
    JustAudioTutorClipPlayer? clips,
    Directory? tempDirectory,
    this.ownsSynthesizer = true,
    this.generationTimeout = const Duration(seconds: 60),
  }) : _synthesizer = synthesizer,
       _clips = clips ?? JustAudioTutorClipPlayer(),
       _tempDirectory = tempDirectory;

  final KittenTutorSynthesizer _synthesizer;
  final JustAudioTutorClipPlayer _clips;
  final Directory? _tempDirectory;

  /// When true, [dispose] also disposes [_synthesizer].
  final bool ownsSynthesizer;

  /// Cap on a single synthesis call before falling back to text-only.
  final Duration generationTimeout;

  int _generation = 0;
  bool _disposed = false;
  bool _textOnly = false;
  Duration? _playbackDuration;
  Future<void> _pending = Future<void>.value();

  /// True after the first generation or playback failure in this session.
  bool get isTextOnly => _textOnly;

  @override
  bool get synchronizesTranscript => true;

  /// Loaded WAV length once playback begins. Null while generating, after a
  /// failure, and in text-only mode.
  @override
  Duration? get playbackDuration => _playbackDuration;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('[TUTOR TTS] $message');
      developer.log(message, name: 'TUTOR TTS');
    }
  }

  @override
  Future<void> speak(String text, {void Function()? onStarted}) {
    if (_disposed) {
      return Future<void>.value();
    }
    _playbackDuration = null;
    if (_textOnly) {
      onStarted?.call();
      return Future<void>.value();
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      onStarted?.call();
      return Future<void>.value();
    }
    return _enqueue(<String>[trimmed], onStarted: onStarted);
  }

  @override
  Future<void> playAssets(List<String> assetIds, {void Function()? onStarted}) {
    if (_disposed) {
      return Future<void>.value();
    }
    _playbackDuration = null;
    if (_textOnly) {
      onStarted?.call();
      return Future<void>.value();
    }
    final texts = <String>[];
    for (final assetId in assetIds) {
      final text = TutorDialogues.byId(assetId.trim())?.text.trim() ?? '';
      if (text.isNotEmpty) {
        texts.add(text);
      }
    }
    if (texts.isEmpty) {
      onStarted?.call();
      return Future<void>.value();
    }
    return _enqueue(texts, onStarted: onStarted);
  }

  Future<void> _enqueue(List<String> texts, {void Function()? onStarted}) {
    final generation = ++_generation;
    final interrupted = _clips.interrupt();
    final result =
        Future.wait<void>([
          _pending.catchError((Object _) {}),
          interrupted,
        ]).then((_) async {
          if (!_isCurrent(generation)) {
            return;
          }
          await _playTexts(texts, generation, onStarted: onStarted);
        });
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> _playTexts(
    List<String> texts,
    int generation, {
    void Function()? onStarted,
  }) async {
    if (!_isCurrent(generation)) {
      return;
    }
    var started = false;
    for (final text in texts) {
      if (!_isCurrent(generation)) {
        return;
      }
      if (_textOnly) {
        break;
      }
      File? file;
      Duration? synthesizedDuration;
      try {
        // Normalize before synthesis so fakes and the SDK see the same input.
        final speechText = normalizeKittenSpeechText(text);
        final audio = await _synthesizer
            .synthesize(speechText)
            .timeout(generationTimeout);
        if (!_isCurrent(generation)) {
          return;
        }
        if (audio.wavBytes.isEmpty) {
          throw StateError('KittenTTS returned empty WAV bytes.');
        }
        synthesizedDuration = audio.duration;
        file = await writeReferenceToneTempFile(
          audio.wavBytes,
          directory: _tempDirectory,
          prefix: 'harmony_kitten_',
        );
        if (!_isCurrent(generation)) {
          return;
        }
        await _clips.playFileToEnd(
          file.path,
          onStarted: started
              ? null
              : () {
                  started = true;
                  final loaded = _clips.duration;
                  _playbackDuration = loaded != null && loaded > Duration.zero
                      ? loaded
                      : (synthesizedDuration != null &&
                                synthesizedDuration > Duration.zero
                            ? synthesizedDuration
                            : null);
                  onStarted?.call();
                },
        );
      } catch (error) {
        if (!_disposed) {
          _textOnly = true;
        }
        _log('$error');
      } finally {
        await deleteReferenceToneTempFile(file);
      }
    }
    if (_isCurrent(generation) && !started) {
      onStarted?.call();
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
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
    if (ownsSynthesizer) {
      await _synthesizer.dispose();
    }
  }
}
