import 'dart:async';

import 'package:harmony/tutor/tutor_timing.dart';
import 'package:harmony/tutor/tutor_voice.dart';

/// Single owner of spoken tutor instructions.
///
/// Guarantees:
/// - one utterance at a time
/// - configurable pause after each line
/// - mutual exclusion with reference audio (never speak while reference plays)
class TutorVoiceCoordinator {
  TutorVoiceCoordinator({
    required TutorVoice voice,
    this.timing = const TutorTimingConfig(),
    Future<void> Function(Duration duration)? wait,
  }) : _voice = voice,
       _wait = wait ?? Future<void>.delayed;

  final TutorVoice _voice;
  final TutorTimingConfig timing;
  final Future<void> Function(Duration duration) _wait;

  bool _isSpeaking = false;
  bool _referenceActive = false;
  bool _isDisposed = false;
  bool _cancelled = false;
  int _speechEpoch = 0;
  final Set<String> _spokenEventIds = <String>{};
  String? _lastLine;
  final List<String> _spokenLog = <String>[];

  bool get isSpeaking => _isSpeaking;
  bool get isReferenceActive => _referenceActive;
  String? get lastLine => _lastLine;
  List<String> get spokenLog => List<String>.unmodifiable(_spokenLog);

  /// Marks that musical reference audio is about to play.
  ///
  /// Blocks new speech until [endReferenceAudio].
  Future<void> beginReferenceAudio() async {
    if (_isSpeaking) {
      await _voice.stop();
      _isSpeaking = false;
    }
    _referenceActive = true;
  }

  /// Marks that musical reference audio has fully stopped.
  void endReferenceAudio() {
    _referenceActive = false;
  }

  /// Drops queued speech immediately. In-flight lines must not continue.
  void cancelSpeech() {
    _speechEpoch += 1;
    _cancelled = true;
    _referenceActive = false;
    _isSpeaking = false;
    unawaited(_voice.stop());
  }

  /// Speaks [line] once for [eventId], then pauses.
  ///
  /// Returns `false` when the event was already spoken or speech is blocked.
  Future<bool> speakOnce(
    String eventId,
    String line, {
    Duration? pauseAfter,
  }) async {
    if (_isDisposed || _cancelled || _spokenEventIds.contains(eventId)) {
      return false;
    }
    _spokenEventIds.add(eventId);
    await speak(line, pauseAfter: pauseAfter);
    return true;
  }

  /// Speaks [line] and waits [pauseAfter] (defaults to sentence pause).
  Future<void> speak(String line, {Duration? pauseAfter}) async {
    final epoch = _speechEpoch;
    if (_isDisposed || _cancelled || epoch != _speechEpoch) {
      return;
    }
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return;
    }

    // Never overlap tutor speech with reference audio.
    while (_referenceActive &&
        !_isDisposed &&
        !_cancelled &&
        epoch == _speechEpoch) {
      await _wait(const Duration(milliseconds: 50));
    }
    if (_isDisposed || _cancelled || epoch != _speechEpoch) {
      return;
    }
    _isSpeaking = true;
    _lastLine = trimmed;
    _spokenLog.add(trimmed);
    try {
      await _voice.speak(trimmed);
      if (_cancelled || _isDisposed || epoch != _speechEpoch) {
        return;
      }
      final pause = pauseAfter ?? timing.sentencePause;
      if (pause > Duration.zero &&
          !_isDisposed &&
          !_cancelled &&
          epoch == _speechEpoch) {
        await _wait(pause);
      }
    } finally {
      if (epoch == _speechEpoch) {
        _isSpeaking = false;
      }
    }
  }

  /// Holds the speech lock for [duration] without saying anything.
  ///
  /// Reference audio must wait until this returns.
  Future<void> pause(Duration duration) async {
    final epoch = _speechEpoch;
    if (_isDisposed ||
        _cancelled ||
        epoch != _speechEpoch ||
        duration <= Duration.zero) {
      return;
    }
    while (_referenceActive &&
        !_isDisposed &&
        !_cancelled &&
        epoch == _speechEpoch) {
      await _wait(const Duration(milliseconds: 50));
    }
    if (_isDisposed || _cancelled || epoch != _speechEpoch) {
      return;
    }
    _isSpeaking = true;
    try {
      if (_cancelled || epoch != _speechEpoch) {
        return;
      }
      await _wait(duration);
    } finally {
      if (epoch == _speechEpoch) {
        _isSpeaking = false;
      }
    }
  }

  /// Speaks each line with sentence pauses between them.
  Future<void> speakAll(List<String> lines, {String? eventIdPrefix}) async {
    final epoch = _speechEpoch;
    for (var i = 0; i < lines.length; i++) {
      if (_isDisposed || _cancelled || epoch != _speechEpoch) {
        return;
      }
      final line = lines[i];
      if (eventIdPrefix != null) {
        await speakOnce('$eventIdPrefix-$i', line);
      } else {
        await speak(line);
      }
    }
  }

  /// Clears once-keys so a new session can re-speak the same logical events.
  void resetEventKeys() {
    _spokenEventIds.clear();
    _cancelled = false;
  }

  Future<void> stop() => _voice.stop();

  Future<void> dispose() async {
    _isDisposed = true;
    await _voice.stop();
    await _voice.dispose();
  }
}
