import 'package:harmony/tutor/tutor_scripts.dart';

/// Maps a tutor line to bundled recording ids `S01`–`S53` and `S59`–`S63`.
///
/// [TutorSession] keeps speaking the current script text. This catalog turns
/// that text into asset ids. File paths stay here, not in the session.
///
/// [TutorScripts.orientation] still needs recordings `S54`–`S58`
/// ([orientationRecordingIds]). Those lines stay in [linesWithoutRecording]
/// and play no audio. The screen still shows them.
class TutorAudioCatalog {
  const TutorAudioCatalog._();

  static const assetDirectory = 'assets/audio/tutor';

  static final RegExp _assetIdPattern = RegExp(
    r'^S(?:0[1-9]|[1-4][0-9]|5[0-3]|59|6[0-3])$',
  );

  /// Current script text to one or more recording ids.
  ///
  /// Completion is two clips: the celebration, then the Shruti name.
  /// A few lines the finalized recordings dropped resolve to an empty list.
  static final Map<String, List<String>> _lineAssets = <String, List<String>>{
    TutorScripts.welcome[0]: <String>['S01'],
    TutorScripts.welcome[1]: <String>['S02'],
    TutorScripts.welcome[2]: <String>['S03'],
    TutorScripts.discoverIntro[0]: <String>['S04'],
    TutorScripts.discoverIntro[1]: <String>['S05'],
    TutorScripts.discoverIntro[2]: <String>['S06'],
    TutorScripts.countdown[0]: <String>['S07'],
    TutorScripts.countdown[1]: <String>['S08'],
    TutorScripts.countdown[2]: <String>['S09'],
    TutorScripts.listenComplete: <String>['S10'],
    TutorScripts.startingNoteSuccess[0]: <String>['S11'],
    TutorScripts.startingNoteRetryOnce[0]: <String>['S12'],
    TutorScripts.startingNoteRetryOnce[1]: <String>['S13'],
    TutorScripts.startingNoteGuided[0]: <String>['S14'],
    TutorScripts.listenFirst: <String>['S15'],
    TutorScripts.nowTryThatSound: <String>['S16'],
    TutorScripts.makeEasier[0]: <String>['S17'],
    TutorScripts.makeEasier[1]: <String>['S18'],
    TutorScripts.lowerSoundIntro: <String>['S20'],
    TutorScripts.middleSoundIntro: <String>['S21'],
    TutorScripts.upperSoundIntro: <String>['S22'],
    TutorScripts.exploreHigher: <String>['S23'],
    TutorScripts.exploreLower: <String>['S24'],
    TutorScripts.lowerAudibilityQuestion: <String>['S25'],
    TutorScripts.softAffirmation: <String>['S26'],
    TutorScripts.lowerNotClear: <String>['S27'],
    TutorScripts.unclearYesNo[0]: <String>['S28'],
    TutorScripts.unclearYesNo[1]: <String>['S29'],
    TutorScripts.upperComfortQuestion: <String>['S30'],
    TutorScripts.upperNotComfortable: <String>['S31'],
    TutorScripts.unclearComfort[1]: <String>['S32'],
    TutorScripts.practiceTogether: <String>['S34'],
    TutorScripts.singAlongWithMe: <String>['S35'],
    TutorScripts.assistedCountdown[0]: <String>['S36'],
    TutorScripts.practiceOnceMore: <String>['S37'],
    TutorScripts.tryOnYourOwn: <String>['S38'],
    TutorScripts.makeThisEasier: <String>['S59'],
    TutorScripts.offerDifferentSound: <String>['S60'],
    TutorScripts.tryThisSound: <String>['S61'],
    TutorScripts.stayWithThisSound: <String>['S62'],
    TutorScripts.stepBackToVoice: <String>['S63'],
    TutorScripts.unresolved[0]: <String>['S52'],
    TutorScripts.unresolved[1]: <String>['S53'],
  };

  /// Spoken display label (`C`, `C#`, …) to the name clip.
  static const Map<String, String> shrutiAssetIds = <String, String>{
    'C': 'S40',
    'C#': 'S41',
    'D': 'S42',
    'D#': 'S43',
    'E': 'S44',
    'F': 'S45',
    'F#': 'S46',
    'G': 'S47',
    'G#': 'S48',
    'A': 'S49',
    'A#': 'S50',
    'B': 'S51',
  };

  static const _completionPrefix =
      'Wonderful. We found a comfortable Shruti for you. Your Shruti is ';

  /// Recordings still needed for [TutorScripts.orientation], in speak order.
  ///
  /// Not bundled yet: `assets/audio/tutor/S54.mp3` through `S58.mp3`.
  static const List<String> orientationRecordingIds = <String>[
    'S54',
    'S55',
    'S56',
    'S57',
    'S58',
  ];

  /// Lines the current session can still request, with no finalized recording.
  static final Set<String> linesWithoutRecording = <String>{
    TutorScripts.startingNoteRetryOnce[2],
    TutorScripts.letMeHelpYou,
    TutorScripts.assistedReady,
    TutorScripts.listenOnceMore,
    ...TutorScripts.orientation,
  };

  /// Recording ids for [line].
  ///
  /// [line] may be the script text [TutorSession] already speaks, or an asset
  /// id such as `S01`. Empty text and [linesWithoutRecording] yield no clips.
  static List<String> assetIdsForSpokenLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }

    final mapped = _lineAssets[trimmed];
    if (mapped != null) {
      return mapped;
    }

    final completion = _completionAssetIds(trimmed);
    if (completion != null) {
      return completion;
    }

    if (linesWithoutRecording.contains(trimmed)) {
      return const <String>[];
    }

    if (_assetIdPattern.hasMatch(trimmed)) {
      return <String>[trimmed];
    }

    throw StateError('No tutor audio for: $trimmed');
  }

  /// Bundled path for [assetId], for example `assets/audio/tutor/S01.mp3`.
  static String assetPath(String assetId) {
    if (!_assetIdPattern.hasMatch(assetId)) {
      throw ArgumentError.value(
        assetId,
        'assetId',
        'Expected a bundled tutor recording id (S01–S53 or S59–S63).',
      );
    }
    return '$assetDirectory/$assetId.mp3';
  }

  static List<String>? _completionAssetIds(String line) {
    if (!line.startsWith(_completionPrefix) || !line.endsWith('.')) {
      return null;
    }
    final label = line.substring(_completionPrefix.length, line.length - 1);
    final pitchId = shrutiAssetIds[label];
    if (pitchId == null) {
      throw StateError('No tutor audio for Shruti "$label".');
    }
    return <String>['S39', pitchId];
  }
}
