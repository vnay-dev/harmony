import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_scripts.dart';

/// Resolves spoken tutor lines to bundled recording ids.
///
/// Playback ids and transcript text both come from [TutorDialogues]. This
/// catalog does not keep a second wording table — it only looks up the shared
/// dialogue definition and returns its id / asset path.
class TutorAudioCatalog {
  const TutorAudioCatalog._();

  static const assetDirectory = 'assets/audio/tutor';

  /// Bundled ids: S01–S53, S60–S76. S54–S58 are reserved / not bundled.
  static final RegExp _assetIdPattern = RegExp(
    r'^S(?:0[1-9]|[1-4][0-9]|5[0-3]|6[0-9]|7[0-6])$',
  );

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

  static final String _completionPrefix =
      '${TutorDialogues.s39.text} Your Shruti is ';

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

    final dialogue = TutorDialogues.byText(trimmed);
    if (dialogue != null) {
      if (TutorDialogues.reservedWithoutRecordingIds.contains(dialogue.id)) {
        return const <String>[];
      }
      return <String>[dialogue.id];
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

  /// Exact dialogue definition for a spoken line, when one exists.
  static TutorDialogue? dialogueForSpokenLine(String line) {
    return TutorDialogues.byText(line.trim());
  }

  /// Bundled path for [assetId], for example `assets/audio/tutor/S01.mp3`.
  static String assetPath(String assetId) {
    if (!_assetIdPattern.hasMatch(assetId)) {
      throw ArgumentError.value(
        assetId,
        'assetId',
        'Expected a bundled tutor recording id (S01–S75).',
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
