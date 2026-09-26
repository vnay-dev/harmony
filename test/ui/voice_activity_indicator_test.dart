import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/pitch/voice_activity.dart';
import 'package:harmony/ui/components/voice_activity_indicator.dart';

void main() {
  test('silence has no voice energy and a calm level', () {
    final silent = Uint8List(2048);
    expect(VoiceActivity.rmsFromPcm16(silent), 0);
    expect(VoiceActivity.levelFromPcm16(silent), 0);
    expect(VoiceActivity.hasVoiceEnergy(silent), isFalse);
  });

  test('a strong PCM window is voiced and raises the level', () {
    final loud = Uint8List(2048);
    final data = ByteData.sublistView(loud);
    for (var i = 0; i < 1024; i++) {
      data.setInt16(i * 2, i.isEven ? 16000 : -16000, Endian.little);
    }
    expect(
      VoiceActivity.rmsFromPcm16(loud),
      greaterThan(VoiceActivity.minVoicedRms),
    );
    expect(VoiceActivity.hasVoiceEnergy(loud), isTrue);
    expect(VoiceActivity.levelFromPcm16(loud), greaterThan(0.5));
  });

  testWidgets('the orb grows with microphone level and rests in silence', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: VoiceActivityIndicator(level: 0)),
    );
    final quiet = tester.getSize(
      find.byKey(const ValueKey<String>('voice-activity-orb')),
    );

    await tester.pumpWidget(
      const MaterialApp(home: VoiceActivityIndicator(level: 1)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final loud = tester.getSize(
      find.byKey(const ValueKey<String>('voice-activity-orb')),
    );

    expect(loud.width, greaterThan(quiet.width));
    expect(quiet.width, VoiceActivityIndicator.restDiameter);
  });
}
