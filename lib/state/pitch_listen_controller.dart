import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';

/// App state for live microphone pitch listening and stability.
class PitchListenController extends ChangeNotifier {
  PitchListenController({
    required PitchDetectionService detectionService,
    PitchStabilityTracker? stabilityTracker,
  }) : _detectionService = detectionService,
       _stabilityTracker = stabilityTracker ?? PitchStabilityTracker();

  final PitchDetectionService _detectionService;
  final PitchStabilityTracker _stabilityTracker;

  StreamSubscription<PitchReading>? _readingsSubscription;
  bool _isListening = false;
  bool _isBusy = false;
  double? _frequencyHz;
  Pitch? _note;
  String? _errorMessage;

  bool get isListening => _isListening;
  bool get isBusy => _isBusy;
  double? get frequencyHz => _frequencyHz;
  Pitch? get note => _note;
  bool get isPitchStable => _stabilityTracker.isStable;
  String? get errorMessage => _errorMessage;

  /// Requests mic access (if needed) and starts live detection.
  Future<void> startListening() async {
    if (_isListening || _isBusy) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    _stabilityTracker.reset();
    notifyListeners();

    try {
      await _detectionService.start();
      _readingsSubscription = _detectionService.readings.listen(
        _onReading,
        onError: _onDetectionError,
      );
      _isListening = true;
    } on PitchDetectionException catch (error) {
      _errorMessage = error.message;
      _isListening = false;
    } catch (_) {
      _errorMessage = 'Failed to start listening.';
      _isListening = false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Stops listening and clears the live reading.
  Future<void> stopListening() async {
    if (!_isListening || _isBusy) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _readingsSubscription?.cancel();
      _readingsSubscription = null;
      await _detectionService.stop();
      _isListening = false;
      _frequencyHz = null;
      _note = null;
      _stabilityTracker.reset();
    } on PitchDetectionException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Failed to stop listening.';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> toggleListening() async {
    if (_isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  void _onReading(PitchReading reading) {
    // Keep the last valid result while listening. Invalid/noisy frames must
    // not clear the displayed pitch or frequency.
    final frequency = reading.frequencyHz;
    if (!reading.hasPitch || frequency == null || frequency <= 0) {
      return;
    }

    // Always derive the note from the same frequency that will be displayed so
    // the label and Hz stay in sync for the latest valid detection.
    final note = noteFromFrequency(frequency);
    if (note == null) {
      return;
    }

    _frequencyHz = frequency;
    _note = note;
    _stabilityTracker.add(note);
    notifyListeners();
  }

  void _onDetectionError(Object error) {
    _errorMessage = error is PitchDetectionException
        ? error.message
        : 'Pitch detection failed.';
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_readingsSubscription?.cancel());
    _detectionService.dispose();
    super.dispose();
  }
}
