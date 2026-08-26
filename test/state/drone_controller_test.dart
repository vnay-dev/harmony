import 'package:flutter_test/flutter_test.dart';

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

  test('initialize loads the audio sample', () async {
    await controller.initialize();

    expect(audioService.loadCount, 1);
    expect(audioService.loaded, isTrue);
    expect(controller.errorMessage, isNull);
    expect(controller.isBusy, isFalse);
  });

  test('initialize surfaces load errors', () async {
    audioService.failLoad = true;

    await controller.initialize();

    expect(controller.errorMessage, 'Failed to load the tanpura sample.');
    expect(controller.isPlaying, isFalse);
  });

  test('selectPitch updates the selected Sa', () {
    controller.selectPitch(Pitch.g);

    expect(controller.selectedPitch, Pitch.g);
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
    audioService.failPlay = true;

    await controller.togglePlayback();

    expect(controller.errorMessage, 'Failed to play the tanpura sample.');
    expect(controller.isPlaying, isFalse);
  });
}
