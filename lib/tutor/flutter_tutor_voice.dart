import 'package:flutter_tts/flutter_tts.dart';

import 'package:harmony/tutor/tutor_voice.dart';

/// Platform text-to-speech backed by [FlutterTts].
class FlutterTutorVoice implements TutorVoice {
  FlutterTutorVoice({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    _initialized = true;
  }

  @override
  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _ensureInitialized();
    await _tts.stop();
    await _tts.speak(trimmed);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
  }
}
