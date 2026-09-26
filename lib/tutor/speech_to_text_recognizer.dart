import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import 'package:harmony/tutor/tutor_speech_recognizer.dart';

/// Platform speech recognition for tutor Yes/No and comfort answers.
///
/// Listening starts only when [listen] is called, which the tutor does after
/// the question has finished. [stop] ends an in-flight listen so a button tap
/// or Stop cannot leave recognition running.
class SpeechToTextTutorRecognizer implements TutorSpeechRecognizer {
  SpeechToTextTutorRecognizer({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialized = false;
  Completer<String?>? _pending;
  String _best = '';

  @override
  Future<bool> get isAvailable async {
    if (!_initialized) {
      try {
        _initialized = await _speech.initialize(
          onError: (_) {},
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              _completePending(_best.isEmpty ? null : _best);
            }
          },
        );
      } catch (_) {
        _initialized = false;
      }
    }
    return _initialized && _speech.isAvailable;
  }

  @override
  Future<String?> listen({
    required Duration timeout,
    void Function(String partial)? onPartial,
  }) async {
    final available = await isAvailable;
    if (!available) {
      return null;
    }

    await stop();
    final pending = Completer<String?>();
    _pending = pending;
    _best = '';

    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isEmpty) {
            return;
          }
          _best = words;
          onPartial?.call(words);
          if (result.finalResult) {
            _completePending(words);
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.confirmation,
          listenFor: timeout,
          pauseFor: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
      _completePending(_best.isEmpty ? null : _best);
    }

    final timed = await Future.any<String?>([
      pending.future,
      Future<String?>.delayed(timeout, () => _best.isEmpty ? null : _best),
    ]);

    await _haltRecognizer();
    _pending = null;
    final trimmed = timed?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  Future<void> stop() async {
    _completePending(_best.isEmpty ? null : _best);
    await _haltRecognizer();
  }

  @override
  Future<void> dispose() async {
    await stop();
  }

  void _completePending(String? value) {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(value);
    }
  }

  Future<void> _haltRecognizer() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}
  }
}
