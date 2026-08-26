import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/audio/audio_assets.dart';
import 'package:harmony/audio/audio_service.dart';

import '../support/fake_audio_service.dart';

void main() {
  test('AudioAssets points at the bundled tanpura sample', () {
    expect(
      AudioAssets.tanpuraSample,
      'assets/audio/Tanpura_sample_C_pitch.m4a',
    );
  });

  test('FakeAudioService starts idle', () {
    final service = FakeAudioService();

    expect(service.isPlaying, isFalse);
    expect(service.loaded, isFalse);
  });

  test('FakeAudioService play loads then plays', () async {
    final service = FakeAudioService();

    await service.play();

    expect(service.loaded, isTrue);
    expect(service.isPlaying, isTrue);
  });

  test('FakeAudioService pause stops playback', () async {
    final service = FakeAudioService();
    await service.play();

    await service.pause();

    expect(service.isPlaying, isFalse);
  });

  test('FakeAudioService load can fail', () async {
    final service = FakeAudioService()..failLoad = true;

    expect(service.load, throwsA(isA<AudioServiceException>()));
  });
}
