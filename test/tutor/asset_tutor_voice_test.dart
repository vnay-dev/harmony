import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/tutor/asset_tutor_voice.dart';
import 'package:harmony/tutor/tutor_audio_catalog.dart';
import 'package:harmony/tutor/tutor_scripts.dart';

void main() {
  group('TutorAudioCatalog', () {
    test('maps current script lines onto S01-S53', () {
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.welcome[0]),
        <String>['S01'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.welcome[1]),
        <String>['S02'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.welcome[2]),
        <String>['S03'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.discoverIntro[0]),
        <String>['S04'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.discoverIntro[1]),
        <String>['S05'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.discoverIntro[2]),
        <String>['S06'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.countdown[0]),
        <String>['S07'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.countdown[1]),
        <String>['S08'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.countdown[2]),
        <String>['S09'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.listenComplete),
        <String>['S10'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.startingNoteSuccess.first,
        ),
        <String>['S11'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.startingNoteRetryOnce[0],
        ),
        <String>['S12'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.rangeRetryOnce),
        <String>['S12'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.startingNoteRetryOnce[1],
        ),
        <String>['S13'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.startingNoteGuided[0],
        ),
        <String>['S14'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.listenFirst),
        <String>['S15'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.nowTryThatSound),
        <String>['S16'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.makeEasier[0]),
        <String>['S17'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.makeEasier[1]),
        <String>['S18'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.letMeHelp[1]),
        <String>['S18'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.lowerSoundIntro),
        <String>['S20'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.middleSoundIntro),
        <String>['S21'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.upperSoundIntro),
        <String>['S22'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.exploreHigher),
        <String>['S23'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.exploreLower),
        <String>['S24'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.lowerAudibilityQuestion,
        ),
        <String>['S25'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.softAffirmation),
        <String>['S26'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.lowerNotClear),
        <String>['S27'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.unclearYesNo[0]),
        <String>['S28'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.unclearComfort[0]),
        <String>['S28'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.unclearYesNo[1]),
        <String>['S29'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.upperComfortQuestion,
        ),
        <String>['S30'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.upperNotComfortable,
        ),
        <String>['S31'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.unclearComfort[1]),
        <String>['S32'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.practiceTogether),
        <String>['S34'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.singAlongWithMe),
        <String>['S35'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.assistedCountdown[0],
        ),
        <String>['S36'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.assistedCountdown[1],
        ),
        <String>['S08'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.assistedCountdown[2],
        ),
        <String>['S09'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.practiceOnceMore),
        <String>['S37'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.tryOnYourOwn),
        <String>['S38'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.unresolved[0]),
        <String>['S52'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.unresolved[1]),
        <String>['S53'],
      );
    });

    test('splits completion into the celebration and the Shruti name', () {
      const names = <String>[
        'S40',
        'S41',
        'S42',
        'S43',
        'S44',
        'S45',
        'S46',
        'S47',
        'S48',
        'S49',
        'S50',
        'S51',
      ];
      final pitches = Pitch.values;
      expect(pitches, hasLength(names.length));
      for (var i = 0; i < pitches.length; i++) {
        expect(
          TutorAudioCatalog.assetIdsForSpokenLine(
            TutorScripts.completion(pitches[i].label),
          ),
          <String>['S39', names[i]],
          reason: pitches[i].label,
        );
      }
    });

    test('maps recovery lines onto S59-S63', () {
      expect(
        TutorScripts.offerDifferentSound,
        "That sound didn't feel quite right. Would you like to try a different one?",
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.makeThisEasier),
        <String>['S59'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.offerDifferentSound,
        ),
        <String>['S60'],
      );
      expect(
        TutorAudioCatalog.linesWithoutRecording,
        isNot(contains(TutorScripts.offerDifferentSound)),
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.tryThisSound),
        <String>['S61'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.stayWithThisSound),
        <String>['S62'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.stepBackToVoice),
        <String>['S63'],
      );
      expect(
        TutorAudioCatalog.linesWithoutRecording,
        isNot(contains(TutorScripts.makeThisEasier)),
      );
      expect(
        TutorAudioCatalog.linesWithoutRecording,
        isNot(contains(TutorScripts.tryThisSound)),
      );
      expect(
        TutorAudioCatalog.linesWithoutRecording,
        isNot(contains(TutorScripts.stayWithThisSound)),
      );
      expect(
        TutorAudioCatalog.linesWithoutRecording,
        isNot(contains(TutorScripts.stepBackToVoice)),
      );
      expect(TutorAudioCatalog.assetPath('S59'), 'assets/audio/tutor/S59.mp3');
      expect(TutorAudioCatalog.assetPath('S60'), 'assets/audio/tutor/S60.mp3');
      expect(TutorAudioCatalog.assetPath('S61'), 'assets/audio/tutor/S61.mp3');
      expect(TutorAudioCatalog.assetPath('S62'), 'assets/audio/tutor/S62.mp3');
      expect(TutorAudioCatalog.assetPath('S63'), 'assets/audio/tutor/S63.mp3');
    });

    test('maps an asset id and its bundled path', () {
      expect(TutorAudioCatalog.assetIdsForSpokenLine('S01'), <String>['S01']);
      expect(TutorAudioCatalog.assetPath('S01'), 'assets/audio/tutor/S01.mp3');
      expect(TutorAudioCatalog.assetPath('S53'), 'assets/audio/tutor/S53.mp3');
    });

    test('orientation lines are not bundled yet', () {
      expect(TutorAudioCatalog.orientationRecordingIds, <String>[
        'S54',
        'S55',
        'S56',
        'S57',
        'S58',
      ]);
      expect(TutorScripts.orientation, hasLength(5));
      for (var i = 0; i < TutorScripts.orientation.length; i++) {
        final line = TutorScripts.orientation[i];
        expect(TutorAudioCatalog.linesWithoutRecording, contains(line));
        expect(
          TutorAudioCatalog.assetIdsForSpokenLine(line),
          isEmpty,
          reason: TutorAudioCatalog.orientationRecordingIds[i],
        );
      }
    });

    test('lines without a recording produce no clips', () {
      for (final line in TutorAudioCatalog.linesWithoutRecording) {
        expect(
          TutorAudioCatalog.assetIdsForSpokenLine(line),
          isEmpty,
          reason: line,
        );
      }
      expect(TutorAudioCatalog.assetIdsForSpokenLine('   '), isEmpty);
    });

    test('rejects unknown speech and invalid ids', () {
      expect(
        () => TutorAudioCatalog.assetIdsForSpokenLine('Hello there'),
        throwsStateError,
      );
      expect(
        () => TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.completion('H'),
        ),
        throwsStateError,
      );
      expect(() => TutorAudioCatalog.assetPath('S00'), throwsArgumentError);
      expect(() => TutorAudioCatalog.assetPath('S54'), throwsArgumentError);
    });
  });

  group('AssetTutorVoice', () {
    late _FakeTutorClipPlayer clips;
    late AssetTutorVoice voice;

    setUp(() {
      clips = _FakeTutorClipPlayer();
      voice = AssetTutorVoice(clips: clips);
    });

    test('waits until the clip finishes', () async {
      var completed = false;
      final speak = voice
          .speak(TutorScripts.welcome.first)
          .whenComplete(() => completed = true);

      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(clips.played, <String>['assets/audio/tutor/S01.mp3']);

      clips.finishCurrent();
      await speak;
      expect(completed, isTrue);
    });

    test('plays completion clips in order', () async {
      final speak = voice.speak(TutorScripts.completion('C#'));

      await Future<void>.delayed(Duration.zero);
      expect(clips.played, <String>['assets/audio/tutor/S39.mp3']);

      clips.finishCurrent();
      await Future<void>.delayed(Duration.zero);
      expect(clips.played, <String>[
        'assets/audio/tutor/S39.mp3',
        'assets/audio/tutor/S41.mp3',
      ]);

      clips.finishCurrent();
      await speak;
    });

    test('stop cancels the current clip and does not start the next', () async {
      final speak = voice.speak(TutorScripts.completion('C'));
      await Future<void>.delayed(Duration.zero);
      expect(clips.played, <String>['assets/audio/tutor/S39.mp3']);

      await voice.stop();
      await speak;

      expect(clips.played, <String>['assets/audio/tutor/S39.mp3']);
      expect(clips.stopCount, greaterThan(0));
    });

    test('stop ends the current clip so a later line can play', () async {
      final first = voice.speak(TutorScripts.welcome.first);
      await Future<void>.delayed(Duration.zero);
      await voice.stop();
      await first;

      final second = voice.speak(TutorScripts.welcome[1]);
      await Future<void>.delayed(Duration.zero);
      expect(clips.played, <String>[
        'assets/audio/tutor/S01.mp3',
        'assets/audio/tutor/S02.mp3',
      ]);
      clips.finishCurrent();
      await second;
    });

    test('plays a bare asset id', () async {
      final speak = voice.speak('S19');
      await Future<void>.delayed(Duration.zero);
      expect(clips.played, <String>['assets/audio/tutor/S19.mp3']);
      clips.finishCurrent();
      await speak;
    });

    test('skips lines that have no recording', () async {
      await voice.speak(TutorScripts.letMeHelpYou);
      expect(clips.played, isEmpty);
    });

    test('dispose stops playback and releases the player', () async {
      final speak = voice.speak(TutorScripts.welcome.first);
      await Future<void>.delayed(Duration.zero);

      await voice.dispose();
      await speak;

      expect(clips.disposed, isTrue);
      expect(clips.stopCount, greaterThan(0));
      await voice.speak(TutorScripts.welcome[1]);
      expect(clips.played, <String>['assets/audio/tutor/S01.mp3']);
    });
  });

  group('JustAudioTutorClipPlayer transitions', () {
    late _RecordingTransport transport;
    late JustAudioTutorClipPlayer player;

    setUp(() {
      transport = _RecordingTransport();
      player = JustAudioTutorClipPlayer(transport: transport);
    });

    test('consecutive clips replace the source without stopping', () async {
      final first = player.playToEnd('assets/audio/tutor/S34.mp3');
      await Future<void>.delayed(Duration.zero);
      expect(transport.stopCount, 0);
      expect(transport.pauseCount, 0);
      expect(transport.loaded, <String>['assets/audio/tutor/S34.mp3']);

      transport.finish();
      await first;
      expect(transport.stopCount, 0);

      final second = player.playToEnd('assets/audio/tutor/S35.mp3');
      await Future<void>.delayed(Duration.zero);
      expect(transport.stopCount, 0);
      expect(transport.pauseCount, 1);
      expect(transport.loaded, <String>[
        'assets/audio/tutor/S34.mp3',
        'assets/audio/tutor/S35.mp3',
      ]);

      transport.finish();
      await second;
      expect(transport.stopCount, 0);
    });

    test('playing the same clip again does not stop the player', () async {
      final first = player.playToEnd('assets/audio/tutor/S35.mp3');
      await Future<void>.delayed(Duration.zero);
      transport.finish();
      await first;

      final second = player.playToEnd('assets/audio/tutor/S35.mp3');
      await Future<void>.delayed(Duration.zero);
      expect(transport.stopCount, 0);
      expect(transport.pauseCount, 1);
      expect(transport.loaded, <String>[
        'assets/audio/tutor/S35.mp3',
        'assets/audio/tutor/S35.mp3',
      ]);
      transport.finish();
      await second;
    });

    test('stop still cancels the clip in progress', () async {
      final playing = player.playToEnd('assets/audio/tutor/S34.mp3');
      await Future<void>.delayed(Duration.zero);
      await player.stop();
      await playing;
      expect(transport.stopCount, 1);

      final next = player.playToEnd('assets/audio/tutor/S35.mp3');
      await Future<void>.delayed(Duration.zero);
      expect(transport.loaded, contains('assets/audio/tutor/S35.mp3'));
      transport.finish();
      await next;
    });
  });
}

class _FakeTutorClipPlayer implements TutorClipPlayer {
  final List<String> played = <String>[];
  int stopCount = 0;
  bool disposed = false;
  Completer<void>? _pending;

  void finishCurrent() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  @override
  Future<void> playToEnd(String assetPath) async {
    if (disposed) {
      return;
    }
    played.add(assetPath);
    final pending = Completer<void>();
    _pending = pending;
    await pending.future;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    finishCurrent();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await stop();
  }
}

class _RecordingTransport implements TutorClipTransport {
  final List<String> loaded = <String>[];
  int pauseCount = 0;
  int stopCount = 0;
  ProcessingState _state = ProcessingState.idle;
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
  ProcessingState get processingState => _state;

  @override
  Stream<ProcessingState> get processingStateStream => _states.stream;

  @override
  Future<void> pause() async {
    pauseCount += 1;
    _state = ProcessingState.ready;
  }

  @override
  Future<void> load(String assetPath) async {
    loaded.add(assetPath);
    _state = ProcessingState.ready;
    _states.add(_state);
  }

  @override
  Future<void> play() async {
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
    _state = ProcessingState.idle;
    finish();
  }

  @override
  Future<void> dispose() => stop();
}
