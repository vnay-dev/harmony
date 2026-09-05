import 'package:flutter/material.dart';

import 'package:harmony/pitch/mic_pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/state/pitch_listen_controller.dart';
import 'package:harmony/theme/design_tokens.dart';

/// Minimal live pitch-detection screen for microphone testing.
class PitchListenScreen extends StatefulWidget {
  const PitchListenScreen({super.key, PitchDetectionService? detectionService})
    : _detectionService = detectionService;

  final PitchDetectionService? _detectionService;

  @override
  State<PitchListenScreen> createState() => _PitchListenScreenState();
}

class _PitchListenScreenState extends State<PitchListenScreen> {
  late final PitchListenController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PitchListenController(
      detectionService: widget._detectionService ?? MicPitchDetectionService(),
    );
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  String _stabilityLabel() {
    if (!_controller.isListening || _controller.note == null) {
      return '—';
    }
    return _controller.isPitchStable ? 'Stable' : 'Not stable';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final frequency = _controller.frequencyHz;
    final note = _controller.note;
    final errorMessage = _controller.errorMessage;

    final statusLabel = _controller.isListening ? 'Listening...' : 'Idle';
    final frequencyLabel = frequency == null
        ? '—'
        : '${frequency.toStringAsFixed(1)} Hz';
    final noteLabel = note?.label ?? '—';

    return Scaffold(
      appBar: AppBar(title: const Text('Pitch detection')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                statusLabel,
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignTokens.spaceXl),
              Text(
                frequencyLabel,
                key: ValueKey<String>('frequency-$frequencyLabel'),
                style: textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              Text(
                noteLabel,
                key: ValueKey<String>('note-$noteLabel'),
                style: textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              Text(
                _stabilityLabel(),
                key: ValueKey<String>('stability-${_controller.isPitchStable}'),
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: DesignTokens.spaceLg),
                Text(
                  errorMessage,
                  style: textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              SizedBox(
                height: DesignTokens.controlHeight,
                child: FilledButton(
                  onPressed: _controller.isBusy
                      ? null
                      : _controller.toggleListening,
                  child: Text(
                    _controller.isListening ? 'Stop' : 'Start listening',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
