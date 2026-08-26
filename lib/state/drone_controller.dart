import 'package:flutter/foundation.dart';

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

  /// Loads the tanpura sample so play can start quickly.
  Future<void> initialize() async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _audioService.load();
    } on AudioServiceException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Failed to load the tanpura sample.';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Updates the selected Sa pitch.
  ///
  /// Pitch shifting is not implemented yet, so the same C sample continues
  /// to play for every selection.
  void selectPitch(Pitch pitch) {
    if (_selectedPitch == pitch) {
      return;
    }
    _selectedPitch = pitch;
    notifyListeners();
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
