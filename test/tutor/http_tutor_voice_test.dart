import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:harmony/tutor/asset_tutor_voice.dart';
import 'package:harmony/tutor/http_tutor_voice.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_dialogue_timing.dart';

const _wavBytes = <int>[
  0x52, 0x49, 0x46, 0x46, // RIFF
  0x08, 0x00, 0x00, 0x00,
  0x57, 0x41, 0x56, 0x45, // WAVE
  0x00, 0x00, 0x00, 0x00,
];

void main() {
  group('HttpTutorVoice', () {
    late HttpServer server;
    late Directory tempDirectory;
    late List<Map<String, Object?>> requests;
    late _RecordingTransport transport;
    late HttpTutorVoice voice;
    late Future<void> Function(HttpRequest request) respond;

    setUp(() async {
      requests = <Map<String, Object?>>[];
      respond = _wavResponse;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add(<String, Object?>{
          'method': request.method,
          'path': request.uri.path,
          'contentType': request.headers.contentType?.mimeType,
          'accept': request.headers.value(HttpHeaders.acceptHeader),
          'json': body.isEmpty ? null : jsonDecode(body),
        });
        await respond(request);
      });
      tempDirectory = await Directory.systemTemp.createTemp(
        'harmony_tts_test_',
      );
      transport = _RecordingTransport();
      voice = HttpTutorVoice(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/speak'),
        clips: JustAudioTutorClipPlayer(transport: transport),
        tempDirectory: tempDirectory,
        requestTimeout: const Duration(seconds: 2),
      );
    });

    tearDown(() async {
      await voice.dispose();
      await server.close(force: true);
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('default endpoint is the local laptop TTS server', () {
      expect(
        HttpTutorVoice.defaultEndpoint,
        Uri.parse('http://192.168.1.37:8000/speak'),
      );
    });

    test('posts spoken text and plays the returned wav', () async {
      var started = false;
      final speak = voice.speak(
        '  Hello there  ',
        onStarted: () => started = true,
      );

      await _waitUntil(() => transport.loadedFiles.isNotEmpty);
      expect(started, isTrue);
      expect(requests, hasLength(1));
      expect(requests.single['method'], 'POST');
      expect(requests.single['path'], '/speak');
      expect(requests.single['contentType'], 'application/json');
      expect(requests.single['accept'], 'audio/wav');
      expect(requests.single['json'], <String, Object?>{'text': 'Hello there'});

      final played = File(transport.loadedFiles.single);
      expect(played.existsSync(), isTrue);
      expect(played.readAsBytesSync(), _wavBytes);
      expect(transport.loaded, isEmpty);
      expect(transport.stopCount, 0);

      transport.finish();
      await speak;
      expect(played.existsSync(), isFalse);
      expect(tempDirectory.listSync(), isEmpty);
    });

    test(
      'onStarted waits until playback and reports the loaded duration',
      () async {
        final release = Completer<void>();
        respond = (request) async {
          await release.future;
          await _wavResponse(request);
        };
        const loaded = Duration(milliseconds: 3200);
        transport.loadedDuration = loaded;

        var started = false;
        final speak = voice.speak(
          'Hello there friend',
          onStarted: () => started = true,
        );
        await _waitUntil(() => requests.isNotEmpty);
        expect(started, isFalse);
        expect(voice.playbackDuration, isNull);

        release.complete();
        await _waitUntil(() => started);
        expect(voice.playbackDuration, loaded);
        expect(
          voice.playbackDuration,
          isNot(TutorDialogueTiming.durationFor('Hello there friend')),
        );
        expect(transport.loadedFiles, hasLength(1));

        transport.finish();
        await speak;
      },
    );

    test('onStarted fires once when the first clip is about to play', () async {
      var startedCount = 0;
      final speak = voice.playAssets(const <String>[
        'S01',
        'S02',
      ], onStarted: () => startedCount++);

      await _waitUntil(() => transport.loadedFiles.length == 1);
      expect(startedCount, 1);
      expect(requests.single['json'], <String, Object?>{
        'text': TutorDialogues.s01.text,
      });

      transport.finish();
      await _waitUntil(() => transport.loadedFiles.length == 2);
      expect(startedCount, 1);
      expect(requests[1]['json'], <String, Object?>{
        'text': TutorDialogues.s02.text,
      });

      transport.finish();
      await speak;
      expect(tempDirectory.listSync(), isEmpty);
    });

    test('empty text and unknown ids do not call the server', () async {
      var started = 0;
      await voice.speak('   ', onStarted: () => started++);
      await voice.playAssets(const <String>[
        '',
        'S00',
      ], onStarted: () => started++);

      expect(started, 2);
      expect(requests, isEmpty);
      expect(transport.loadedFiles, isEmpty);
    });

    test(
      'http errors finish without playing and still reveal the line',
      () async {
        respond = (request) async {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"error":"down"}');
          await request.response.close();
        };

        var started = false;
        await voice.speak('Hello', onStarted: () => started = true);

        expect(started, isTrue);
        expect(voice.playbackDuration, isNull);
        expect(transport.loadedFiles, isEmpty);
        expect(tempDirectory.listSync(), isEmpty);
      },
    );

    test('network failure finishes without playing', () async {
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = probe.port;
      await probe.close(force: true);

      await voice.dispose();
      transport = _RecordingTransport();
      voice = HttpTutorVoice(
        endpoint: Uri.parse('http://127.0.0.1:$closedPort/speak'),
        clips: JustAudioTutorClipPlayer(transport: transport),
        tempDirectory: tempDirectory,
        requestTimeout: const Duration(milliseconds: 500),
      );

      var started = false;
      await voice.speak('Hello', onStarted: () => started = true);

      expect(started, isTrue);
      expect(transport.loadedFiles, isEmpty);
    });

    test('stop during the request drops playback', () async {
      final received = Completer<void>();
      final release = Completer<void>();
      respond = (request) async {
        if (!received.isCompleted) {
          received.complete();
        }
        await release.future;
        await _wavResponse(request);
      };

      var started = false;
      final speak = voice.speak('Hello', onStarted: () => started = true);
      await received.future.timeout(const Duration(seconds: 2));
      await voice.stop();
      release.complete();
      await speak;

      expect(started, isFalse);
      expect(voice.isTextOnly, isFalse);
      expect(transport.loadedFiles, isEmpty);
      expect(tempDirectory.listSync(), isEmpty);

      transport.completePlaysImmediately = true;
      await voice.speak('After stop');
      expect(requests, hasLength(2));
      expect(voice.isTextOnly, isFalse);
    });

    test(
      'the first HTTP failure switches to text-only for later lines',
      () async {
        respond = (request) async {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"error":"down"}');
          await request.response.close();
        };

        var started = false;
        await voice.speak('Hello', onStarted: () => started = true);
        expect(started, isTrue);
        expect(voice.isTextOnly, isTrue);
        expect(transport.loadedFiles, isEmpty);

        final attempts = requests.length;
        started = false;
        await voice.speak('Next line', onStarted: () => started = true);
        expect(started, isTrue);
        expect(requests, hasLength(attempts));
        expect(transport.loadedFiles, isEmpty);
      },
    );

    test(
      'a playback failure switches to text-only without another request',
      () async {
        transport.failPlay = true;
        await voice.speak('Hello');
        expect(voice.isTextOnly, isTrue);
        expect(transport.loadedFiles, isNotEmpty);

        final attempts = requests.length;
        await voice.speak('Next line');
        expect(requests, hasLength(attempts));
      },
    );

    test('a later line interrupts the current wav', () async {
      final first = voice.speak('First line');
      await _waitUntil(() => transport.loadedFiles.length == 1);
      final firstFile = transport.loadedFiles.single;

      final second = voice.speak('Second line');
      await _waitUntil(() => transport.loadedFiles.length == 2);
      expect(File(firstFile).existsSync(), isFalse);
      expect(requests.map((request) => request['json']), <Object?>[
        <String, Object?>{'text': 'First line'},
        <String, Object?>{'text': 'Second line'},
      ]);

      transport.finish();
      await first;
      await second;
      expect(tempDirectory.listSync(), isEmpty);
    });

    test('dispose stops playback and ignores later speech', () async {
      final speak = voice.speak('Hello');
      await _waitUntil(() => transport.loadedFiles.isNotEmpty);
      await voice.dispose();
      await speak;

      var started = false;
      await voice.speak('Again', onStarted: () => started = true);
      expect(started, isFalse);
      expect(requests, hasLength(1));
    });
  });
}

Future<void> _wavResponse(HttpRequest request) async {
  request.response.headers.contentType = ContentType('audio', 'wav');
  request.response.add(_wavBytes);
  await request.response.close();
}

Future<void> _waitUntil(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for tutor playback');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _RecordingTransport implements TutorClipTransport {
  final List<String> loaded = <String>[];
  final List<String> loadedFiles = <String>[];
  int stopCount = 0;
  ProcessingState _state = ProcessingState.idle;
  bool _playing = false;
  final StreamController<ProcessingState> _states =
      StreamController<ProcessingState>.broadcast();
  Completer<void>? _playDone;

  void finish() {
    final pending = _playDone;
    _playDone = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  @override
  bool get isIdle => _state == ProcessingState.idle;

  @override
  bool get isPlaying => _playing;

  @override
  ProcessingState get processingState => _state;

  @override
  Stream<ProcessingState> get processingStateStream => _states.stream;

  /// Length reported after [loadFile], as just_audio would.
  Duration? loadedDuration;

  @override
  Duration? get duration => loadedDuration;

  @override
  Future<void> pause() async {
    _playing = false;
    _state = ProcessingState.ready;
  }

  @override
  Future<void> load(String assetPath, {bool loop = false}) async {
    loaded.add(assetPath);
    _state = ProcessingState.ready;
    _states.add(_state);
  }

  @override
  Future<void> loadFile(String filePath, {bool loop = false}) async {
    loadedFiles.add(filePath);
    _state = ProcessingState.ready;
    _states.add(_state);
  }

  bool failPlay = false;
  bool completePlaysImmediately = false;

  @override
  Future<void> play() async {
    if (failPlay) {
      throw StateError('playback failed');
    }
    _playing = true;
    if (completePlaysImmediately) {
      _state = ProcessingState.completed;
      return;
    }
    final pending = Completer<void>();
    _playDone = pending;
    await pending.future;
    _state = ProcessingState.completed;
    if (!_states.isClosed) {
      _states.add(ProcessingState.completed);
    }
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _playing = false;
    _state = ProcessingState.idle;
    finish();
  }

  @override
  Future<void> dispose() => stop();
}
