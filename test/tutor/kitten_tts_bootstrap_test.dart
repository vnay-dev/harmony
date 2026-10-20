import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kittentts/kittentts.dart';

import 'package:harmony/tutor/kitten_tts_bootstrap.dart';
import 'package:harmony/tutor/kitten_tutor_voice.dart';

void main() {
  group('KittenTtsDefaults', () {
    test('locks the approved production voice-lab configuration', () {
      final config = KittenTtsDefaults.config();
      expect(config.model, 'micro');
      expect(config.defaultVoice, 'luna');
      expect(config.speed, 1.1);
      expect(config.analytics, isFalse);
      expect(KittenTtsDefaults.model, 'micro');
      expect(KittenTtsDefaults.voice, 'luna');
      expect(KittenTtsDefaults.speed, 1.1);
      expect(KittenTtsDefaults.sampleRateHz, 24000);
      // KittenTTS always encodes wavData() at this rate.
      expect(KittenTtsDefaults.sampleRateHz, outputSampleRate);
    });
  });

  group('KittenTtsBootstrap', () {
    test('reports progress, caches the synthesizer, and reaches ready', () async {
      final progressValues = <double>[];
      late KittenTtsBootstrap bootstrap;
      bootstrap = KittenTtsBootstrap(
        open:
            ({
              required KittenTTSConfig config,
              ProgressHandler? onProgress,
              bool forceRedownload = false,
            }) async {
              expect(config.model, 'micro');
              expect(config.defaultVoice, 'luna');
              expect(config.speed, 1.1);
              expect(config.analytics, isFalse);
              expect(forceRedownload, isFalse);
              // DownloadProgressStage / Asset are not exported by package:kittentts.
              onProgress?.call(0.25);
              expect(bootstrap.state, KittenTtsReadyState.loading);
              onProgress?.call(1);
              return _FakeSynthesizer();
            },
      );
      bootstrap.addListener(() {
        progressValues.add(bootstrap.progress);
      });

      final synthesizer = await bootstrap.ensureReady();
      expect(bootstrap.state, KittenTtsReadyState.ready);
      expect(bootstrap.isReady, isTrue);
      expect(bootstrap.progress, 1);
      expect(bootstrap.error, isNull);
      expect(identical(bootstrap.synthesizer, synthesizer), isTrue);
      expect(progressValues, contains(0.25));

      final second = await bootstrap.ensureReady();
      expect(identical(second, synthesizer), isTrue);

      bootstrap.dispose();
    });

    test('shares one in-flight ensureReady future', () async {
      var openCount = 0;
      final release = Completer<void>();
      final bootstrap = KittenTtsBootstrap(
        open:
            ({
              required KittenTTSConfig config,
              ProgressHandler? onProgress,
              bool forceRedownload = false,
            }) async {
              openCount += 1;
              await release.future;
              return _FakeSynthesizer();
            },
      );

      final first = bootstrap.ensureReady();
      final second = bootstrap.ensureReady();
      expect(openCount, 1);
      release.complete();
      expect(identical(await first, await second), isTrue);
      expect(openCount, 1);
      bootstrap.dispose();
    });

    test('failed open exposes error and retry recovers', () async {
      var openCount = 0;
      final bootstrap = KittenTtsBootstrap(
        open:
            ({
              required KittenTTSConfig config,
              ProgressHandler? onProgress,
              bool forceRedownload = false,
            }) async {
              openCount += 1;
              if (openCount == 1) {
                throw StateError('download failed');
              }
              onProgress?.call(1);
              return _FakeSynthesizer();
            },
      );

      await expectLater(bootstrap.ensureReady(), throwsStateError);
      expect(bootstrap.state, KittenTtsReadyState.failed);
      expect(bootstrap.error, isA<StateError>());
      expect(bootstrap.synthesizer, isNull);

      final synthesizer = await bootstrap.retry();
      expect(bootstrap.state, KittenTtsReadyState.ready);
      expect(bootstrap.isReady, isTrue);
      expect(bootstrap.error, isNull);
      expect(synthesizer, isA<_FakeSynthesizer>());
      expect(openCount, 2);
      bootstrap.dispose();
    });

    test('forceRedownload is forwarded on retry', () async {
      final forceFlags = <bool>[];
      final bootstrap = KittenTtsBootstrap(
        open:
            ({
              required KittenTTSConfig config,
              ProgressHandler? onProgress,
              bool forceRedownload = false,
            }) async {
              forceFlags.add(forceRedownload);
              return _FakeSynthesizer();
            },
      );

      await bootstrap.ensureReady();
      await bootstrap.retry(forceRedownload: true);
      expect(forceFlags, <bool>[false, true]);
      bootstrap.dispose();
    });

    test('dispose releases the synthesizer', () async {
      final fake = _FakeSynthesizer();
      final bootstrap = KittenTtsBootstrap(
        open:
            ({
              required KittenTTSConfig config,
              ProgressHandler? onProgress,
              bool forceRedownload = false,
            }) async {
              return fake;
            },
      );

      await bootstrap.ensureReady();
      bootstrap.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(fake.disposeCount, 1);
      expect(bootstrap.state, KittenTtsReadyState.idle);
      expect(bootstrap.synthesizer, isNull);
    });
  });
}

class _FakeSynthesizer implements KittenTutorSynthesizer {
  int disposeCount = 0;

  @override
  Future<KittenTutorAudio> synthesize(String text) async {
    return KittenTutorAudio(wavBytes: Uint8List(0));
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
