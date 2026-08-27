import 'package:flutter/foundation.dart';

import 'package:harmony/audio/audio_assets.dart';
import 'package:harmony/audio/audio_service.dart';
import 'package:harmony/models/pitch.dart';

/// App state for the Shruti drone: selected Sa, playback, and errors.
///
/// Keeps business logic out of the Flutter UI widgets.
class DroneController extends ChangeNotifier {
  DroneController({required AudioService audioService})
    : _audioService = audioService;

  final AudioService _audioService;

  Pitch _selectedPitch = Pitch.defaultPitch;
  bool _isPlaying = false;
  bool _isBusy = false;
  String? _errorMessage;

  Pitch get selectedPitch => _selectedPitch;
  bool get isPlaying => _isPlaying;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  /// Loads the default Sa sample so play can start quickly.
  Future<void> initialize() async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final asset = AudioAssets.sampleFor(_selectedPitch);
      if (asset == null) {
        throw AudioServiceException('No tanpura sample is available for Sa.');
      }
      await _audioService.load(asset);
    } on AudioServiceException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Failed to load the tanpura sample.';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Updates the selected Sa.
  ///
  /// While paused, only app state changes. While playing, switches to the
  /// matching sample when one exists; otherwise pauses so audio does not
  /// continue under the wrong pitch.
  Future<void> selectPitch(Pitch pitch) async {
    if (_selectedPitch == pitch) {
      return;
    }

    _selectedPitch = pitch;
    _errorMessage = null;
    notifyListeners();

    if (!_isPlaying) {
      return;
    }

    final asset = AudioAssets.sampleFor(pitch);
    if (asset == null) {
      try {
        await _audioService.pause();
      } on AudioServiceException catch (error) {
        _errorMessage = error.message;
      } catch (_) {
        _errorMessage = 'Failed to pause playback.';
      }
      _isPlaying = false;
      _errorMessage ??= 'No sample available for ${pitch.label} yet.';
      notifyListeners();
      return;
    }

    try {
      await _audioService.load(asset);
    } on AudioServiceException catch (error) {
      _errorMessage = error.message;
      _isPlaying = _audioService.isPlaying;
      notifyListeners();
    } catch (_) {
      _errorMessage = 'Failed to load the tanpura sample.';
      _isPlaying = _audioService.isPlaying;
      notifyListeners();
    }
  }

  /// Toggles between play and pause.
  Future<void> togglePlayback() async {
    if (_isBusy) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_isPlaying) {
        await _audioService.pause();
        _isPlaying = false;
      } else {
        final asset = AudioAssets.sampleFor(_selectedPitch);
        if (asset == null) {
          _errorMessage =
              'No sample available for ${_selectedPitch.label} yet.';
          return;
        }
        await _audioService.load(asset);
        await _audioService.play();
        _isPlaying = true;
      }
    } on AudioServiceException catch (error) {
      _errorMessage = error.message;
      _isPlaying = _audioService.isPlaying;
    } catch (_) {
      _errorMessage = _isPlaying
          ? 'Failed to pause playback.'
          : 'Failed to play the tanpura sample.';
      _isPlaying = _audioService.isPlaying;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }
}
