import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/tutor/tutor_sa_sample_player.dart';

import '../support/fake_tutor_sa_sample_player.dart';

void main() {
  group('TutorSaSamplePlayer', () {
    late FakeTutorSaClipTransport transport;
    late TutorSaSamplePlayer player;
    var changed = 0;
    var wavBuilds = 0;
    final builtHz = <double>[];

    setUp(() {
      transport = FakeTutorSaClipTransport();
      changed = 0;
      wavBuilds = 0;
      builtHz.clear();
      player = TutorSaSamplePlayer(
        transport: transport,
        buildWav: (hz) {
          wavBuilds += 1;
          builtHz.add(hz);
          return Uint8List.fromList(const <int>[1, 2, 3, 4]);
        },
        writeTempFile: (bytes, {Directory? directory}) async {
          return File('test/sa_example.wav');
        },
        onChanged: () => changed += 1,
      );
    });

    tearDown(() async {
      await player.dispose();
    });

    test('plays a synthesized looping Sa reference tone', () async {
      await player.toggle();
      expect(player.isPlaying, isTrue);
      expect(wavBuilds, 1);
      expect(builtHz.single, frequencyHzForPitch(Pitch.g));
      expect(transport.loadedFiles, <String>['test/sa_example.wav']);
      expect(transport.loaded, isEmpty);
      expect(transport.loadedLoop, <bool>[true]);
      expect(transport.playCount, 1);
      expect(changed, 1);

      await player.toggle();
      expect(player.isPlaying, isFalse);
      expect(transport.pauseCount, 1);
      expect(changed, 2);
    });

    test('keeps playing when the finite clip reaches its end while looping', () async {
      await player.play();
      expect(player.isPlaying, isTrue);
      transport.finish();
      await Future<void>.delayed(Duration.zero);
      expect(player.isPlaying, isTrue);
    });

    test('stop clears playback without leaving a playing state', () async {
      await player.play();
      await player.stop();
      expect(player.isPlaying, isFalse);
      expect(transport.stopCount, 1);
    });

    test('can play again after pause without rebuilding the source', () async {
      await player.play();
      await player.pause();
      await player.play();
      expect(player.isPlaying, isTrue);
      expect(transport.playCount, 2);
      expect(wavBuilds, 1);
      expect(transport.loadedFiles.length, 1);
      expect(transport.loadedLoop.single, isTrue);
    });

    test('prepareNextPitch switches pitch without playing', () async {
      expect(player.pitch, Pitch.g);
      await player.prepareNextPitch();
      expect(player.pitch, Pitch.gSharp);
      expect(player.isPlaying, isFalse);
      expect(builtHz.last, frequencyHzForPitch(Pitch.gSharp));
      expect(transport.playCount, 0);
      expect(transport.loadedFiles, isNotEmpty);

      await player.play();
      expect(player.isPlaying, isTrue);
      expect(transport.playCount, 1);
    });
  });
}
