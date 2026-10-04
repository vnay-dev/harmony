import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_voice.dart';

/// Records spoken lines for deterministic tutor tests.
class FakeTutorVoice implements TutorVoice {
  final List<String> spoken = <String>[];
  final List<String> playedAssets = <String>[];
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> speak(String text, {void Function()? onStarted}) async {
    onStarted?.call();
    spoken.add(text);
    final hook = onSpeak;
    if (hook != null) {
      await hook(text);
    }
  }

  @override
  Future<void> playAssets(
    List<String> assetIds, {
    void Function()? onStarted,
  }) async {
    onStarted?.call();
    playedAssets.addAll(assetIds);
    for (final id in assetIds) {
      final dialogue = TutorDialogues.byId(id);
      final text = dialogue?.text ?? id;
      spoken.add(text);
      final speakHook = onSpeak;
      if (speakHook != null) {
        await speakHook(text);
      }
    }
    final hook = onPlayAssets;
    if (hook != null) {
      await hook(assetIds);
    }
  }

  /// Optional gate so tests can stop mid-utterance.
  Future<void> Function(String text)? onSpeak;

  /// Optional gate for asset-id playback.
  Future<void> Function(List<String> assetIds)? onPlayAssets;

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
