import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/audio/audio_assets.dart';
import 'package:harmony/models/pitch.dart';
import 'package:harmony/state/drone_controller.dart';

import '../support/fake_audio_service.dart';

void main() {
  late FakeAudioService audioService;
  late DroneController controller;

  setUp(() {
    audioService = FakeAudioService();
    controller = DroneController(audioService: audioService);
  });

  tearDown(() {
    controller.dispose();
  });

  test('starts with C selected and not playing', () {
    expect(controller.selectedPitch, Pitch.c);
    expect(controller.isPlaying, isFalse);
    expect(controller.errorMessage, isNull);
  });

  test('initialize loads the default C sample', () async {
    await controller.initialize();

    expect(audioService.loadCount, 1);
    expect(audioService.currentAsset, AudioAssets.sampleFor(Pitch.c));
    expect(controller.errorMessage, isNull);
    expect(controller.isBusy, isFalse);
  });

  test('initialize surfaces load errors', () async {
    audioService.failLoad = true;

    await controller.initialize();

    expect(controller.errorMessage, 'Failed to load the tanpura sample.');
    expect(controller.isPlaying, isFalse);
  });

  test('selectPitch while paused only updates selected state', () async {
    await controller.initialize();
    final loadCountBefore = audioService.loadCount;

    await controller.selectPitch(Pitch.d);

    expect(controller.selectedPitch, Pitch.d);
    expect(controller.isPlaying, isFalse);
    expect(audioService.loadCount, loadCountBefore);
    expect(audioService.playCount, 0);
  });

  test('selectPitch can change every Sa option', () async {
    await controller.initialize();

    for (final pitch in Pitch.values) {
      await controller.selectPitch(pitch);
      expect(controller.selectedPitch, pitch);
    }
  });

  test('selectPitch while playing switches to the matching sample', () async {
    await controller.initialize();
    await controller.togglePlayback();
    expect(controller.isPlaying, isTrue);

    final pauseCountBefore = audioService.pauseCount;

    await controller.selectPitch(Pitch.cSharp);

    expect(controller.isPlaying, isTrue);
    expect(controller.selectedPitch, Pitch.cSharp);
    expect(audioService.currentAsset, AudioAssets.sampleFor(Pitch.cSharp));
    expect(audioService.pauseCount, pauseCountBefore);
  });

  test('selectPitch while playing switches across available samples', () async {
    await controller.initialize();
    await controller.togglePlayback();

    for (final pitch in [Pitch.d, Pitch.g, Pitch.b, Pitch.c]) {
      await controller.selectPitch(pitch);
      expect(controller.isPlaying, isTrue);
      expect(audioService.currentAsset, AudioAssets.sampleFor(pitch));
    }
  });

  test('play loads the selected sample that was chosen while paused', () async {
    await controller.initialize();
    await controller.selectPitch(Pitch.aSharp);

    await controller.togglePlayback();

    expect(controller.isPlaying, isTrue);
    expect(audioService.currentAsset, AudioAssets.sampleFor(Pitch.aSharp));
  });

  test('togglePlayback plays then pauses', () async {
    await controller.initialize();

    await controller.togglePlayback();
    expect(controller.isPlaying, isTrue);
    expect(audioService.playCount, 1);

    await controller.togglePlayback();
    expect(controller.isPlaying, isFalse);
    expect(audioService.pauseCount, 1);
  });

  test('togglePlayback surfaces play errors', () async {
    await controller.initialize();
    audioService.failPlay = true;

    await controller.togglePlayback();

    expect(controller.errorMessage, 'Failed to play the tanpura sample.');
    expect(controller.isPlaying, isFalse);
  });
}
