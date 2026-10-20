import 'dart:async';

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
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.countdownFirst[0]),
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
      expect(TutorAudioCatalog.isValidAssetId('S70'), isTrue);
      expect(TutorAudioCatalog.isValidAssetId('S61'), isTrue);
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
      expect(TutorAudioCatalog.isValidAssetId('S72'), isTrue);
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
      expect(TutorAudioCatalog.isValidAssetId('S70'), isTrue);
      expect(TutorAudioCatalog.isValidAssetId('S71'), isTrue);
      expect(TutorAudioCatalog.isValidAssetId('S73'), isTrue);
      expect(TutorAudioCatalog.isValidAssetId('S63'), isTrue);
    });

    test('maps a bare asset id', () {
      expect(TutorAudioCatalog.assetIdsForSpokenLine('S01'), <String>['S01']);
      expect(TutorAudioCatalog.isValidAssetId('S01'), isTrue);
      expect(TutorAudioCatalog.isValidAssetId('S53'), isTrue);
    });

    test('orientation lines are not speakable yet', () {
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
      expect(TutorAudioCatalog.isValidAssetId('S00'), isFalse);
      expect(TutorAudioCatalog.isValidAssetId('S54'), isFalse);
      expect(TutorAudioCatalog.isValidAssetId('S77'), isFalse);
      expect(TutorAudioCatalog.isValidAssetId('S74'), isTrue);
      expect(TutorAudioCatalog.isValidAssetId('S75'), isTrue);
      expect(TutorAudioCatalog.isValidAssetId('S76'), isTrue);
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
      final first = player.playToEnd('clip-a');
      await Future<void>.delayed(Duration.zero);
      expect(transport.stopCount, 0);
      expect(transport.pauseCount, 0);
      expect(transport.loaded, <String>['clip-a']);

      transport.finish();
      await first;
      expect(transport.stopCount, 0);

      final second = player.playToEnd('clip-b');
      await Future<void>.delayed(Duration.zero);
      expect(transport.stopCount, 0);
      expect(transport.pauseCount, 1);
      expect(transport.loaded, <String>['clip-a', 'clip-b']);

      transport.finish();
      await second;
      expect(transport.stopCount, 0);
    });

    test('playing the same clip again does not stop the player', () async {
      final first = player.playToEnd('clip-b');
      await Future<void>.delayed(Duration.zero);
      transport.finish();
      await first;

      final second = player.playToEnd('clip-b');
      await Future<void>.delayed(Duration.zero);
      expect(transport.stopCount, 0);
      expect(transport.pauseCount, 1);
      expect(transport.loaded, <String>['clip-b', 'clip-b']);
      transport.finish();
      await second;
    });

    test('stop still cancels the clip in progress', () async {
      final playing = player.playToEnd('clip-a');
      await Future<void>.delayed(Duration.zero);
      await player.stop();
      await playing;
      expect(transport.stopCount, 1);

      final next = player.playToEnd('clip-b');
      await Future<void>.delayed(Duration.zero);
      expect(transport.loaded, contains('clip-b'));
      transport.finish();
      await next;
    });

    test('file playback loads a local path without stopping', () async {
      final playing = player.playFileToEnd(r'C:\tmp\tutor-line.wav');
      await Future<void>.delayed(Duration.zero);
      expect(transport.loaded, isEmpty);
      expect(transport.loadedFiles, <String>[r'C:\tmp\tutor-line.wav']);
      expect(transport.stopCount, 0);

      transport.finish();
      await playing;
      expect(transport.stopCount, 0);
    });
  });
}

class _RecordingTransport implements TutorClipTransport {
  final List<String> loaded = <String>[];
  final List<String> loadedFiles = <String>[];
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
  Duration? get duration => null;

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
    loadedFiles.add(filePath);
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
