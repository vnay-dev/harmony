import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:harmony/audio/reference_tone_temp_file.dart';
import 'package:harmony/audio/reference_tone_wav.dart';
import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/tutor/asset_tutor_voice.dart';

/// Optional Stage 1 Sa example using the Stage 2 reference-tone architecture.
///
/// Synthesizes a clean single-note Sa via [buildLoopableReferenceToneWav],
/// plays it through the tutor clip transport with native looping, and stops
/// only when the user pauses or the session cancels. Does not advance steps.
class TutorSaSamplePlayer {
  TutorSaSamplePlayer({
    TutorClipTransport? transport,
    Pitch? initialPitch,
    double? frequencyHz,
    Directory? tempDirectory,
    Uint8List Function(double frequencyHz)? buildWav,
    Future<File> Function(Uint8List bytes, {Directory? directory})?
    writeTempFile,
    this.onChanged,
  }) : _injected = transport,
       _pitch = initialPitch ?? Pitch.g,
       _frequencyHz =
           frequencyHz ?? frequencyHzForPitch(initialPitch ?? Pitch.g),
       _tempDirectory = tempDirectory,
       _buildWav =
           buildWav ?? ((hz) => buildLoopableReferenceToneWav(frequencyHz: hz)),
       _writeTempFile =
           writeTempFile ??
           ((bytes, {Directory? directory}) =>
               writeReferenceToneTempFile(bytes, directory: directory));

  final TutorClipTransport? _injected;
  Pitch _pitch;
  double _frequencyHz;
  final Directory? _tempDirectory;
  final Uint8List Function(double frequencyHz) _buildWav;
  final Future<File> Function(Uint8List bytes, {Directory? directory})
  _writeTempFile;

  /// Fired when [isPlaying] changes.
  void Function()? onChanged;

  TutorClipTransport? _owned;
  File? _activeTempFile;
  bool _isPlaying = false;
  bool _hasActiveSource = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isPlaying => _isPlaying;

  /// Current Sa pitch for the synthesized example.
  Pitch get pitch => _pitch;

  /// Sa frequency used for the synthesized example (tests).
  double get frequencyHz => _frequencyHz;

  TutorClipTransport get _transport =>
      _injected ?? (_owned ??= JustAudioTutorClipTransport());

  void _emitChanged() {
    onChanged?.call();
  }

  void _setPlaying(bool value) {
    if (_isPlaying == value) {
      return;
    }
    _isPlaying = value;
    _emitChanged();
  }

  Future<void> toggle() async {
    if (_disposed) {
      return;
    }
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (_disposed) {
      return;
    }
    final generation = ++_generation;
    try {
      if (!_hasActiveSource) {
        await _prepareSource(generation);
        if (_disposed || generation != _generation) {
          return;
        }
      }

      _setPlaying(true);
      // Looping play() completes only on pause/stop — do not await it.
      unawaited(
        _transport.play().catchError((Object _) {
          if (_disposed || generation != _generation) {
            return;
          }
          _hasActiveSource = false;
          _setPlaying(false);
        }),
      );
    } catch (_) {
      if (_disposed || generation != _generation) {
        return;
      }
      _hasActiveSource = false;
      _setPlaying(false);
    }
  }

  Future<void> pause() async {
    if (_disposed || !_isPlaying) {
      return;
    }
    final generation = ++_generation;
    await _transport.pause();
    if (_disposed || generation != _generation) {
      return;
    }
    _setPlaying(false);
  }

  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    _generation += 1;
    _hasActiveSource = false;
    final wasPlaying = _isPlaying;
    _isPlaying = false;
    await _transport.stop();
    await deleteReferenceToneTempFile(_activeTempFile);
    _activeTempFile = null;
    if (wasPlaying) {
      _emitChanged();
    }
  }

  /// Advances to the next supported Sa pitch and prepares it without playing.
  Future<void> prepareNextPitch() async {
    if (_disposed) {
      return;
    }
    final nextIndex = (_pitch.index + 1) % Pitch.values.length;
    await preparePitch(Pitch.values[nextIndex]);
  }

  /// Stops playback, switches to [pitch], and prepares the looping WAV.
  Future<void> preparePitch(Pitch pitch) async {
    if (_disposed) {
      return;
    }
    final generation = ++_generation;
    if (_isPlaying) {
      _isPlaying = false;
      _emitChanged();
    }
    _hasActiveSource = false;
    await _transport.stop();
    if (_disposed || generation != _generation) {
      return;
    }

    _pitch = pitch;
    _frequencyHz = frequencyHzForPitch(pitch);
    await _prepareSource(generation);
  }

  Future<void> _prepareSource(int generation) async {
    final wav = _buildWav(_frequencyHz);
    final tempFile = await _writeTempFile(wav, directory: _tempDirectory);
    if (_disposed || generation != _generation) {
      await deleteReferenceToneTempFile(tempFile);
      return;
    }
    await deleteReferenceToneTempFile(_activeTempFile);
    _activeTempFile = tempFile;
    await _transport.loadFile(tempFile.path, loop: true);
    if (_disposed || generation != _generation) {
      return;
    }
    _hasActiveSource = true;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation += 1;
    _isPlaying = false;
    _hasActiveSource = false;
    onChanged = null;
    final owned = _owned;
    if (owned != null) {
      await owned.dispose();
      _owned = null;
    } else {
      await _injected?.stop();
    }
    await deleteReferenceToneTempFile(_activeTempFile);
    _activeTempFile = null;
  }
}
