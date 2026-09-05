import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/ui/screens/pitch_listen_screen.dart';

import '../support/fake_pitch_detection_service.dart';

void main() {
  testWidgets('shows idle pitch detection UI', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: PitchListenScreen(detectionService: FakePitchDetectionService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('Start listening'), findsOneWidget);
  });

  testWidgets('shows live frequency and note while listening', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detectionService = FakePitchDetectionService();

    await tester.pumpWidget(
      MaterialApp(home: PitchListenScreen(detectionService: detectionService)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start listening'));
    await tester.pumpAndSettle();

    expect(find.text('Listening...'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));

    detectionService.emit(
      const PitchReading(hasPitch: true, frequencyHz: 246.94, note: Pitch.b),
    );
    await tester.pumpAndSettle();

    expect(find.text('246.9 Hz'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    detectionService.emit(PitchReading.none);
    await tester.pumpAndSettle();

    expect(find.text('246.9 Hz'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    detectionService.emit(
      // Wrong note on purpose; UI must follow the frequency.
      const PitchReading(hasPitch: true, frequencyHz: 277.18, note: Pitch.b),
    );
    await tester.pumpAndSettle();

    expect(find.text('277.2 Hz'), findsOneWidget);
    expect(find.text('C#'), findsOneWidget);
    expect(find.text('B'), findsNothing);
  });
}
