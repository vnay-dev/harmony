import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:harmony/tutor/tutor_audio_catalog.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_timing.dart';
import 'package:harmony/tutor/tutor_voice.dart';

/// Single owner of spoken tutor instructions.
///
/// Guarantees:
/// - one utterance at a time
/// - configurable pause after each line
/// - mutual exclusion with reference audio (never speak while reference plays)
/// - transcript text and audio ids come from the same [TutorDialogue] when one
///   exists for the spoken line
class TutorVoiceCoordinator {
  TutorVoiceCoordinator({
    required TutorVoice voice,
    this.timing = const TutorTimingConfig(),
    Future<void> Function(Duration duration)? wait,
    this.onChanged,
  }) : _voice = voice,
       _wait = wait ?? Future<void>.delayed;

  final TutorVoice _voice;
  final TutorTimingConfig timing;
  final Future<void> Function(Duration duration) _wait;

  /// Fired when [isSpeaking], [lastLine], or [activeDialogue] changes.
  void Function()? onChanged;

  bool _isSpeaking = false;
  bool _referenceActive = false;
  bool _isDisposed = false;
  bool _cancelled = false;
  int _speechEpoch = 0;
  final Set<String> _spokenEventIds = <String>{};
  String? _lastLine;
  TutorDialogue? _activeDialogue;
  final List<String> _spokenLog = <String>[];
  final List<String> _playedAssetLog = <String>[];

  bool get isSpeaking => _isSpeaking;
  bool get isReferenceActive => _referenceActive;
  String? get lastLine => _lastLine;

  /// Dialogue currently driving transcript + audio, if resolved.
  TutorDialogue? get activeDialogue => _activeDialogue;

  List<String> get spokenLog => List<String>.unmodifiable(_spokenLog);

  /// Asset ids actually requested for playback (tests / diagnostics).
  List<String> get playedAssetLog => List<String>.unmodifiable(_playedAssetLog);

  void _emitChanged() {
    onChanged?.call();
  }

  static void _log(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
      developer.log(message, name: tag);
    }
  }

  /// Marks that musical reference audio is about to play.
  ///
  /// Blocks new speech until [endReferenceAudio].
  Future<void> beginReferenceAudio() async {
    if (_isSpeaking) {
      await _voice.stop();
      _isSpeaking = false;
      _emitChanged();
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
    final wasSpeaking = _isSpeaking;
    _isSpeaking = false;
    _activeDialogue = null;
    unawaited(_voice.stop());
    if (wasSpeaking) {
      _emitChanged();
    }
  }

  /// Speaks [dialogue] once for [eventId], then pauses.
  ///
  /// Returns `false` when the event was already spoken or speech is blocked.
  Future<bool> speakDialogueOnce(
    String eventId,
    TutorDialogue dialogue, {
    Duration? pauseAfter,
  }) async {
    if (_isDisposed || _cancelled || _spokenEventIds.contains(eventId)) {
      return false;
    }
    _spokenEventIds.add(eventId);
    await speakDialogue(dialogue, pauseAfter: pauseAfter);
    return true;
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

  /// Atomic dialogue event: one definition supplies transcript text and audio.
  Future<void> speakDialogue(
    TutorDialogue dialogue, {
    Duration? pauseAfter,
  }) async {
    final epoch = _speechEpoch;
    if (_isDisposed || _cancelled || epoch != _speechEpoch) {
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

    final assetIds =
        TutorDialogues.reservedWithoutRecordingIds.contains(dialogue.id)
        ? const <String>[]
        : <String>[dialogue.id];

    // Mark speaking first, but bind transcript only when audio is about to
    // start — otherwise the screen can show a line while ExoPlayer is still
    // Initializing and the user hears silence or the next line.
    _isSpeaking = true;
    _activeDialogue = null;
    _lastLine = null;
    _playedAssetLog.addAll(assetIds);
    _emitChanged();

    void bindTranscript() {
      if (_cancelled || _isDisposed || epoch != _speechEpoch) {
        return;
      }
      _activeDialogue = dialogue;
      _lastLine = dialogue.text;
      _spokenLog.add(dialogue.text);
      _emitChanged();
      _log(
        'TUTOR',
        'id=${dialogue.id} text="${dialogue.text}" audio=${dialogue.assetFileName}',
      );
    }

    try {
      if (assetIds.isNotEmpty) {
        await _voice.playAssets(assetIds, onStarted: bindTranscript);
      } else {
        bindTranscript();
      }
      if (_cancelled || _isDisposed || epoch != _speechEpoch) {
        return;
      }
      if (_isSpeaking) {
        _isSpeaking = false;
        _emitChanged();
      }
      final pause = pauseAfter ?? timing.sentencePause;
      if (pause > Duration.zero &&
          !_isDisposed &&
          !_cancelled &&
          epoch == _speechEpoch) {
        await _wait(pause);
      }
    } finally {
      if (epoch == _speechEpoch && _isSpeaking) {
        _isSpeaking = false;
        _emitChanged();
      }
    }
  }

  /// Speaks [line] and waits [pauseAfter] (defaults to sentence pause).
  ///
  /// When [line] matches a [TutorDialogue], delegates to [speakDialogue] so
  /// text and audio cannot resolve independently.
  Future<void> speak(String line, {Duration? pauseAfter}) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final dialogue = TutorDialogues.byText(trimmed);
    if (dialogue != null) {
      await speakDialogue(dialogue, pauseAfter: pauseAfter);
      return;
    }

    final epoch = _speechEpoch;
    if (_isDisposed || _cancelled || epoch != _speechEpoch) {
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

    List<String> assetIds = const <String>[];
    try {
      assetIds = TutorAudioCatalog.assetIdsForSpokenLine(trimmed);
    } on StateError {
      assetIds = const <String>[];
    }
    _isSpeaking = true;
    _activeDialogue = null;
    _lastLine = null;
    _playedAssetLog.addAll(assetIds);
    _emitChanged();

    void bindTranscript() {
      if (_cancelled || _isDisposed || epoch != _speechEpoch) {
        return;
      }
      _lastLine = trimmed;
      _spokenLog.add(trimmed);
      _emitChanged();
      _log(
        'TUTOR DIALOGUE',
        'id: (unmapped) text: "$trimmed" audio: ${assetIds.join(",")}',
      );
      _log('TUTOR TRANSCRIPT', 'id: (unmapped) text: "$trimmed"');
    }

    try {
      // Keep [speak] for composite lines (e.g. completion) so fakes record the
      // full transcript string once while AssetTutorVoice still plays by id.
      // Always call speak (even with no clips) so fakes still record the line;
      // bindTranscript runs from onStarted when audible playback begins.
      await _voice.speak(trimmed, onStarted: bindTranscript);
      if (_cancelled || _isDisposed || epoch != _speechEpoch) {
        return;
      }
      if (_isSpeaking) {
        _isSpeaking = false;
        _emitChanged();
      }
      final pause = pauseAfter ?? timing.sentencePause;
      if (pause > Duration.zero &&
          !_isDisposed &&
          !_cancelled &&
          epoch == _speechEpoch) {
        await _wait(pause);
      }
    } finally {
      if (epoch == _speechEpoch && _isSpeaking) {
        _isSpeaking = false;
        _emitChanged();
      }
    }
  }

  /// Holds the speech lock for [duration] without saying anything.
  ///
  /// Reference audio must wait until this returns. Sets [isSpeaking] so the
  /// UI treats the tutor as occupied (used between spoken lines).
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
    _emitChanged();
    try {
      if (_cancelled || epoch != _speechEpoch) {
        return;
      }
      await _wait(duration);
    } finally {
      if (epoch == _speechEpoch) {
        _isSpeaking = false;
        _emitChanged();
      }
    }
  }

  /// Waits [duration] without changing [isSpeaking] or [lastLine].
  ///
  /// Use for non-speech UI pacing (e.g. example-button affirmation) so the
  /// transcript is never treated as speaking again.
  Future<void> waitQuietly(Duration duration) async {
    if (_isDisposed || duration <= Duration.zero) {
      return;
    }
    await _wait(duration);
  }

  /// Clears the mirrored transcript line without speaking.
  ///
  /// Used when entering the user-turn listening UI so a stale pre-listen
  /// line cannot flash before the listen instruction appears.
  void clearLastLine({bool notify = true}) {
    if (_lastLine == null && _activeDialogue == null) {
      return;
    }
    _lastLine = null;
    _activeDialogue = null;
    if (notify) {
      _emitChanged();
    }
  }

  /// Speaks each [TutorDialogue] with sentence pauses between them.
  Future<void> speakDialogues(
    List<TutorDialogue> dialogues, {
    String? eventIdPrefix,
  }) async {
    final epoch = _speechEpoch;
    for (var i = 0; i < dialogues.length; i++) {
      if (_isDisposed || _cancelled || epoch != _speechEpoch) {
        return;
      }
      final dialogue = dialogues[i];
      if (eventIdPrefix != null) {
        await speakDialogueOnce('$eventIdPrefix-$i', dialogue);
      } else {
        await speakDialogue(dialogue);
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
    _playedAssetLog.clear();
  }

  Future<void> stop() => _voice.stop();

  Future<void> dispose() async {
    _isDisposed = true;
    await _voice.stop();
    await _voice.dispose();
  }
}
