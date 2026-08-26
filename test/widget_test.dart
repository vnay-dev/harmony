import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/app/app.dart';
import 'package:harmony/app/app_config.dart';
import 'package:harmony/models/pitch.dart';

import 'support/fake_audio_service.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(HarmonyApp(audioService: FakeAudioService()));
    await tester.pumpAndSettle();
  }

  testWidgets('shows app name, default Sa, and play control', (tester) async {
    await pumpApp(tester);

    expect(find.text(AppConfig.appName), findsOneWidget);
    expect(find.text('Sa'), findsOneWidget);
    expect(find.text('C'), findsWidgets);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('selecting a pitch updates the selected Sa display', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('G'));
    await tester.pumpAndSettle();

    expect(find.text(Pitch.g.label), findsWidgets);
  });

  testWidgets('play and pause update the button label', (tester) async {
    await pumpApp(tester);

    final playFinder = find.text('Play');
    await tester.ensureVisible(playFinder);
    await tester.tap(playFinder);
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsOneWidget);

    final pauseFinder = find.text('Pause');
    await tester.ensureVisible(pauseFinder);
    await tester.tap(pauseFinder);
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
  });
}
