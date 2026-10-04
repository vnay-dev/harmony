import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/tutor/asset_tutor_voice.dart';
import 'package:harmony/tutor/tutor_audio_catalog.dart';
import 'package:harmony/tutor/tutor_scripts.dart';

void main() {
  group('TutorAudioCatalog', () {
    test('maps current script lines onto Stage 1 and legacy ids', () {
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.welcome[0]),
        <String>['S64'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.firstStepListen),
        <String>['S65'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.firstStepInstruction,
        ),
        <String>['S66'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.stage1Success),
        <String>['S67'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.readyForNextStep),
        <String>['S68'],
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
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.countdownFirst[0],
        ),
        <String>['S75'],
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
        <String>['S72'],
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
        <String>['S70'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.startingNoteGuided[1],
        ),
        <String>['S61'],
      );
      expect(TutorScripts.startingNoteGuided, hasLength(2));
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.listenFirst),
        <String>['S15'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.lowerSoundListenPrompt,
        ),
        <String>['S74'],
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
          TutorScripts.assistedSingAlongPrompt,
        ),
        <String>['S76'],
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

    test('maps Stage 1 failure spoken lines onto S70, S61', () {
      expect(TutorScripts.startingNoteGuided, <String>[
        "That's okay. Let's make this a little easier.",
        "Listen to the sound again, then sing it when you're ready.",
      ]);
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.startingNoteGuided[0],
        ),
        <String>['S70'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.startingNoteGuided[1],
        ),
        <String>['S61'],
      );
      expect(TutorAudioCatalog.assetPath('S70'), 'assets/audio/tutor/S70.mp3');
      expect(TutorAudioCatalog.assetPath('S61'), 'assets/audio/tutor/S61.mp3');
      for (final id in <String>['S70', 'S61']) {
        expect(
          File(TutorAudioCatalog.assetPath(id)).existsSync(),
          isTrue,
          reason: '$id must be bundled on disk',
        );
      }
      // Guard: a prior S61.mp3 was the retired "Lovely. Let's try this one."
      // clip (35988 bytes / ~2.18s). Listen-again must stay the longer take.
      final s61Bytes = File(TutorAudioCatalog.assetPath('S61')).lengthSync();
      expect(s61Bytes, isNot(35988));
      expect(s61Bytes, greaterThan(50000));
      expect(
        TutorScripts.startingNoteGuided,
        isNot(contains("That's okay. Let's try again.")),
      );
      expect(
        TutorScripts.startingNoteGuided,
        isNot(contains(TutorScripts.offerDifferentSound)),
      );
    });

    test('maps Stage 2 opening onto S72 and not retired Stage 1 ids', () {
      expect(
        TutorScripts.startingNoteSuccess.first,
        "Now that I understand your voice, let's find your singing range.",
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.startingNoteSuccess.first,
        ),
        <String>['S72'],
      );
      expect(TutorAudioCatalog.assetPath('S72'), 'assets/audio/tutor/S72.mp3');
      expect(File(TutorAudioCatalog.assetPath('S72')).existsSync(), isTrue);
      expect(
        File(TutorAudioCatalog.assetPath('S72')).lengthSync(),
        greaterThan(1000),
      );
      for (final id in <String>['S59', 'S60', 'S61', 'S62', 'S63', 'S11']) {
        expect(
          TutorAudioCatalog.assetIdsForSpokenLine(
            TutorScripts.startingNoteSuccess.first,
          ),
          isNot(<String>[id]),
        );
      }
    });

    test('maps Stage 2 recovery lines onto S70/S71/S73 and S63', () {
      expect(
        TutorScripts.offerDifferentSound,
        "That sound didn't feel quite right. Would you like to try a different one?",
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.makeThisEasier),
        <String>['S70'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.offerDifferentSound,
        ),
        <String>['S71'],
      );
      expect(
        TutorAudioCatalog.linesWithoutRecording,
        isNot(contains(TutorScripts.offerDifferentSound)),
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.stayWithThisSound),
        <String>['S73'],
      );
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.stepBackToVoice),
        <String>['S63'],
      );
      expect(TutorAudioCatalog.assetPath('S70'), 'assets/audio/tutor/S70.mp3');
      expect(TutorAudioCatalog.assetPath('S71'), 'assets/audio/tutor/S71.mp3');
      expect(TutorAudioCatalog.assetPath('S73'), 'assets/audio/tutor/S73.mp3');
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
      expect(() => TutorAudioCatalog.assetPath('S77'), throwsArgumentError);
      expect(TutorAudioCatalog.assetPath('S74'), 'assets/audio/tutor/S74.mp3');
      expect(File(TutorAudioCatalog.assetPath('S74')).existsSync(), isTrue);
      expect(TutorAudioCatalog.assetPath('S75'), 'assets/audio/tutor/S75.mp3');
      expect(File(TutorAudioCatalog.assetPath('S75')).existsSync(), isTrue);
      expect(TutorAudioCatalog.assetPath('S76'), 'assets/audio/tutor/S76.mp3');
      expect(File(TutorAudioCatalog.assetPath('S76')).existsSync(), isTrue);
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
      expect(clips.played, <String>['assets/audio/tutor/S64.mp3']);

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

      final second = voice.speak(TutorScripts.firstStepListen);
      await Future<void>.delayed(Duration.zero);
      expect(clips.played, <String>[
        'assets/audio/tutor/S64.mp3',
        'assets/audio/tutor/S65.mp3',
      ]);
      clips.finishCurrent();
      await second;
    });

    test('awaits interrupt before starting the next clip', () async {
      final events = <String>[];
      final tracking = _OrderingClipPlayer(events);
      final orderedVoice = AssetTutorVoice(clips: tracking);

      final first = orderedVoice.playAssets(const <String>['S70']);
      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['interrupt', 'play:S70']);

      // Start S61 while S70 is still "playing" — interrupt must finish before play.
      // Hard stop is avoided so ExoPlayer is not Released between dialogue lines.
      final second = orderedVoice.playAssets(const <String>['S61']);
      await Future<void>.delayed(Duration.zero);
      expect(events, <String>[
        'interrupt',
        'play:S70',
        'interrupt',
        'play:S61',
      ]);

      tracking.finishCurrent();
      await first;
      tracking.finishCurrent();
      await second;
      await orderedVoice.dispose();
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
      await voice.speak(TutorScripts.firstStepListen);
      expect(clips.played, <String>['assets/audio/tutor/S64.mp3']);
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
  int interruptCount = 0;
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
  Future<void> playToEnd(String assetPath, {void Function()? onStarted}) async {
    if (disposed) {
      return;
    }
    played.add(assetPath);
    onStarted?.call();
    final pending = Completer<void>();
    _pending = pending;
    await pending.future;
  }

  @override
  Future<void> interrupt() async {
    interruptCount += 1;
    finishCurrent();
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

/// Records interrupt/play ordering for race-regression coverage.
class _OrderingClipPlayer implements TutorClipPlayer {
  _OrderingClipPlayer(this.events);

  final List<String> events;
  Completer<void>? _pending;

  void finishCurrent() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  @override
  Future<void> playToEnd(String assetPath, {void Function()? onStarted}) async {
    final id = assetPath.split('/').last.replaceAll('.mp3', '');
    events.add('play:$id');
    onStarted?.call();
    final pending = Completer<void>();
    _pending = pending;
    await pending.future;
  }

  @override
  Future<void> interrupt() async {
    events.add('interrupt');
    finishCurrent();
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    finishCurrent();
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}

class _RecordingTransport implements TutorClipTransport {
  final List<String> loaded = <String>[];
  int pauseCount = 0;
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

  @override
  Future<void> pause() async {
    pauseCount += 1;
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
    loaded.add(filePath);
    _state = ProcessingState.ready;
    _states.add(_state);
  }

  @override
  Future<void> play() async {
    _playing = true;
    final pending = Completer<void>();
    _playDone = pending;
    await pending.future;
    _state = ProcessingState.completed;
    // Mimic just_audio: playing stays true after natural completion.
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
