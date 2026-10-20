import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:harmony/audio/reference_tone_temp_file.dart';
import 'package:harmony/tutor/asset_tutor_voice.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_voice.dart';

/// Speaks tutor lines by requesting WAV audio from a local HTTP TTS server.
///
/// The default endpoint is `http://192.168.1.37:8000/speak`. Each request is
/// `POST` JSON `{"text": "..."}`. The response body is written to a temporary
/// WAV and played through [JustAudioTutorClipPlayer.playFileToEnd].
///
/// Pass this voice explicitly for local prototyping. Production Assist Mode
/// defaults to on-device [KittenTutorVoice]; HTTP wins when both flags are set.
class HttpTutorVoice implements TutorVoice {
  HttpTutorVoice({
    Uri? endpoint,
    JustAudioTutorClipPlayer? clips,
    HttpClient? httpClient,
    Directory? tempDirectory,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _endpoint = endpoint ?? defaultEndpoint,
       _clips = clips ?? JustAudioTutorClipPlayer(),
       _client = httpClient ?? HttpClient(),
       _tempDirectory = tempDirectory {
    _client.connectionTimeout = requestTimeout;
    // The laptop TTS server is on the local network, not via an HTTP proxy.
    _client.findProxy = (_) => 'DIRECT';
  }

  /// Laptop TTS server used for local prototyping.
  static final Uri defaultEndpoint = Uri.parse(
    'http://192.168.1.37:8000/speak',
  );

  final Uri _endpoint;
  final JustAudioTutorClipPlayer _clips;
  final HttpClient _client;
  final Directory? _tempDirectory;
  final Duration requestTimeout;

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
      try {
        final bytes = await _postSpeak(text).timeout(requestTimeout);
        if (!_isCurrent(generation)) {
          return;
        }
        file = await writeReferenceToneTempFile(
          bytes,
          directory: _tempDirectory,
          prefix: 'harmony_tts_',
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
                      : null;
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

  Future<Uint8List> _postSpeak(String text) async {
    final payload = utf8.encode(jsonEncode(<String, String>{'text': text}));
    final request = await _client.postUrl(_endpoint);
    request.persistentConnection = false;
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'audio/wav');
    request.contentLength = payload.length;
    request.add(payload);

    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final mime = response.headers.contentType?.mimeType ?? '';
    final playable =
        mime.isEmpty ||
        mime.startsWith('audio/') ||
        mime == 'application/octet-stream';
    if (response.statusCode != HttpStatus.ok || !playable || bytes.isEmpty) {
      throw HttpException(
        'TTS request failed '
        '(${response.statusCode}, ${mime.isEmpty ? 'unknown type' : mime}, '
        '${bytes.length} bytes).',
        uri: _endpoint,
      );
    }
    return bytes;
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
    _client.close(force: true);
  }
}
