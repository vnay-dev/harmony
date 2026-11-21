import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:harmony/tutor/asset_tutor_voice.dart';
import 'package:harmony/tutor/kitten_tutor_voice.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_dialogue_timing.dart';

const _wavBytes = <int>[
  0x52, 0x49, 0x46, 0x46, // RIFF
  0x08, 0x00, 0x00, 0x00,
  0x57, 0x41, 0x56, 0x45, // WAVE
  0x00, 0x00, 0x00, 0x00,
];

void main() {
  group('KittenTutorVoice', () {
    late Directory tempDirectory;
    late _FakeSynthesizer synthesizer;
    late _RecordingTransport transport;
    late KittenTutorVoice voice;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'harmony_kitten_voice_test_',
      );
      synthesizer = _FakeSynthesizer();
      transport = _RecordingTransport();
      voice = KittenTutorVoice(
        synthesizer: synthesizer,
        clips: JustAudioTutorClipPlayer(transport: transport),
        tempDirectory: tempDirectory,
      );
    });

    tearDown(() async {
      await voice.dispose();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('synchronizes the transcript like HTTP playback', () {
      expect(voice.synchronizesTranscript, isTrue);
    });

    test('synthesizes spoken text and plays the returned wav', () async {
      var started = false;
      final speak = voice.speak(
        '  Hello there  ',
        onStarted: () => started = true,
      );

      await _waitUntil(() => transport.loadedFiles.isNotEmpty);
      expect(started, isTrue);
      expect(synthesizer.texts, <String>['Hello there']);

      final played = File(transport.loadedFiles.single);
      expect(played.existsSync(), isTrue);
      expect(played.readAsBytesSync(), _wavBytes);
      expect(transport.loaded, isEmpty);

      transport.finish();
      await speak;
      expect(played.existsSync(), isFalse);
      expect(tempDirectory.listSync(), isEmpty);
    });

    test('normalizes title-case Try before synthesis (not T-R-Y)', () async {
      final speak = voice.speak(TutorDialogues.s66.text);
      // Wait until playback is armed so finish() can complete the clip.
      await _waitUntil(() => transport.loadedFiles.isNotEmpty);
      expect(
        synthesizer.texts.single,
        'try humming any comfortable, steady sound, like Sa.',
      );
      expect(synthesizer.texts.single, isNot(contains('Try')));
      transport.finish();
      await speak;
    });

    test(
      'modulates punctuation for Kitten prosody without rewriting wording',
      () async {
        final speak = voice.speak(
          'Beautiful.You can stop there!!! Ready…Next,step?',
        );
        await _waitUntil(() => transport.loadedFiles.isNotEmpty);
        expect(
          synthesizer.texts.single,
          'Beautiful. You can stop there! Ready... Next, step?',
        );
        transport.finish();
        await speak;
      },
    );

    test(
      'preserves multi-sentence dialogue punctuation for synthesis',
      () async {
        final speak = voice.playAssets(const <String>['S74']);
        await _waitUntil(() => transport.loadedFiles.isNotEmpty);
        expect(synthesizer.texts.single, TutorDialogues.s74.text);
        expect(synthesizer.texts.single, contains('. '));
        expect(synthesizer.texts.single, contains(','));
        transport.finish();
        await speak;
      },
    );

    test(
      'onStarted waits until playback and reports the loaded duration',
      () async {
        final release = Completer<void>();
        synthesizer.gate = release.future;
        const loaded = Duration(milliseconds: 3200);
        transport.loadedDuration = loaded;

        var started = false;
        final speak = voice.speak(
          'Hello there friend',
          onStarted: () => started = true,
        );
        await _waitUntil(() => synthesizer.texts.isNotEmpty);
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
      expect(synthesizer.texts.single, TutorDialogues.s01.text);

      transport.finish();
      await _waitUntil(() => transport.loadedFiles.length == 2);
      expect(startedCount, 1);
      expect(synthesizer.texts[1], TutorDialogues.s02.text);

      transport.finish();
      await speak;
      expect(tempDirectory.listSync(), isEmpty);
    });

    test('empty text and unknown ids do not synthesize', () async {
      var started = 0;
      await voice.speak('   ', onStarted: () => started++);
      await voice.playAssets(const <String>[
        '',
        'S00',
      ], onStarted: () => started++);

      expect(started, 2);
      expect(synthesizer.texts, isEmpty);
      expect(transport.loadedFiles, isEmpty);
    });

    test(
      'synthesis errors finish without playing and still reveal the line',
      () async {
        synthesizer.error = StateError('engine down');

        var started = false;
        await voice.speak('Hello', onStarted: () => started = true);

        expect(started, isTrue);
        expect(voice.playbackDuration, isNull);
        expect(transport.loadedFiles, isEmpty);
        expect(tempDirectory.listSync(), isEmpty);
        expect(voice.isTextOnly, isTrue);
      },
    );

    test('stop during synthesis drops playback', () async {
      final release = Completer<void>();
      synthesizer.gate = release.future;

      var started = false;
      final speak = voice.speak('Hello', onStarted: () => started = true);
      await _waitUntil(() => synthesizer.texts.isNotEmpty);
      await voice.stop();
      release.complete();
      await speak;

      expect(started, isFalse);
      expect(voice.isTextOnly, isFalse);
      expect(transport.loadedFiles, isEmpty);
      expect(tempDirectory.listSync(), isEmpty);

      transport.completePlaysImmediately = true;
      await voice.speak('After stop');
      expect(synthesizer.texts, <String>['Hello', 'After stop']);
      expect(voice.isTextOnly, isFalse);
    });

    test(
      'the first synthesis failure switches to text-only for later lines',
      () async {
        synthesizer.error = StateError('engine down');

        var started = false;
        await voice.speak('Hello', onStarted: () => started = true);
        expect(started, isTrue);
        expect(voice.isTextOnly, isTrue);
        expect(transport.loadedFiles, isEmpty);

        final attempts = synthesizer.texts.length;
        synthesizer.error = null;
        started = false;
        await voice.speak('Next line', onStarted: () => started = true);
        expect(started, isTrue);
        expect(synthesizer.texts, hasLength(attempts));
        expect(transport.loadedFiles, isEmpty);
      },
    );

    test('a later line interrupts the current wav', () async {
      final first = voice.speak('First line');
      await _waitUntil(() => transport.loadedFiles.length == 1);
      final firstFile = transport.loadedFiles.single;

      final second = voice.speak('Second line');
      await _waitUntil(() => transport.loadedFiles.length == 2);
      expect(File(firstFile).existsSync(), isFalse);
      expect(synthesizer.texts, <String>['First line', 'Second line']);

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
      expect(synthesizer.texts, <String>['Hello']);
      expect(synthesizer.disposeCount, 1);
    });

    test(
      'does not dispose a shared synthesizer when ownsSynthesizer is false',
      () async {
        await voice.dispose();
        synthesizer = _FakeSynthesizer();
        voice = KittenTutorVoice(
          synthesizer: synthesizer,
          clips: JustAudioTutorClipPlayer(transport: transport),
          tempDirectory: tempDirectory,
          ownsSynthesizer: false,
        );

        await voice.dispose();
        expect(synthesizer.disposeCount, 0);
      },
    );
  });
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

class _FakeSynthesizer implements KittenTutorSynthesizer {
  final List<String> texts = <String>[];
  Future<void>? gate;
  Object? error;
  int disposeCount = 0;
  Uint8List wavBytes = Uint8List.fromList(_wavBytes);
  Duration? duration = const Duration(milliseconds: 1500);

  @override
  Future<KittenTutorAudio> synthesize(String text) async {
    texts.add(text);
    final wait = gate;
    if (wait != null) {
      await wait;
    }
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return KittenTutorAudio(wavBytes: wavBytes, duration: duration);
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
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
