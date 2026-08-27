import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/audio/audio_assets.dart';
import 'package:harmony/audio/audio_service.dart';
import 'package:harmony/models/pitch.dart';

import '../support/fake_audio_service.dart';

void main() {
  test('maps every Sa pitch to its Pa tanpura sample', () {
    expect(AudioAssets.tanpuraSamplesByPitch.length, Pitch.values.length);

    expect(AudioAssets.sampleFor(Pitch.c), 'assets/audio/pa/tanpura_c3.m4a');
    expect(
      AudioAssets.sampleFor(Pitch.cSharp),
      'assets/audio/pa/tanpura_csharp3.m4a',
    );
    expect(AudioAssets.sampleFor(Pitch.d), 'assets/audio/pa/tanpura_d3.m4a');
    expect(
      AudioAssets.sampleFor(Pitch.dSharp),
      'assets/audio/pa/tanpura_dsharp3.m4a',
    );
    expect(AudioAssets.sampleFor(Pitch.e), 'assets/audio/pa/tanpura_e3.m4a');
    expect(AudioAssets.sampleFor(Pitch.f), 'assets/audio/pa/tanpura_f3.m4a');
    expect(
      AudioAssets.sampleFor(Pitch.fSharp),
      'assets/audio/pa/tanpura_fsharp3.m4a',
    );
    expect(AudioAssets.sampleFor(Pitch.g), 'assets/audio/pa/tanpura_g3.m4a');
    expect(
      AudioAssets.sampleFor(Pitch.gSharp),
      'assets/audio/pa/tanpura_gsharp3.m4a',
    );
    expect(AudioAssets.sampleFor(Pitch.a), 'assets/audio/pa/tanpura_a3.m4a');
    expect(
      AudioAssets.sampleFor(Pitch.aSharp),
      'assets/audio/pa/tanpura_asharp3.m4a',
    );
    expect(AudioAssets.sampleFor(Pitch.b), 'assets/audio/pa/tanpura_b3.m4a');
  });

  test('every Sa pitch has a sample', () {
    for (final pitch in Pitch.values) {
      expect(AudioAssets.hasSample(pitch), isTrue, reason: pitch.label);
      expect(AudioAssets.sampleFor(pitch), isNotNull, reason: pitch.label);
    }
  });

  test('FakeAudioService starts idle', () {
    final service = FakeAudioService();

    expect(service.isPlaying, isFalse);
    expect(service.loaded, isFalse);
    expect(service.currentAsset, isNull);
  });

  test('FakeAudioService load then play', () async {
    final service = FakeAudioService();

    await service.load(AudioAssets.sampleFor(Pitch.c)!);
    await service.play();

    expect(service.loaded, isTrue);
    expect(service.currentAsset, 'assets/audio/pa/tanpura_c3.m4a');
    expect(service.isPlaying, isTrue);
  });

  test('FakeAudioService load skips duplicate asset', () async {
    final service = FakeAudioService();
    final asset = AudioAssets.sampleFor(Pitch.c)!;

    await service.load(asset);
    await service.load(asset);

    expect(service.loadCount, 2);
    expect(service.loadedAssets, [asset]);
  });

  test('FakeAudioService pause stops playback', () async {
    final service = FakeAudioService();
    await service.load(AudioAssets.sampleFor(Pitch.d)!);
    await service.play();

    await service.pause();

    expect(service.isPlaying, isFalse);
  });

  test('FakeAudioService load can fail', () async {
    final service = FakeAudioService()..failLoad = true;

    expect(
      () => service.load('assets/audio/pa/tanpura_c3.m4a'),
      throwsA(isA<AudioServiceException>()),
    );
  });
}
