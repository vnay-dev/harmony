import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/app/app.dart';
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

  testWidgets('shows default Sa, play control, and Find my Shruti', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('C'), findsOneWidget);
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    expect(
      find.text('Not sure which Shruti is right for you?'),
      findsOneWidget,
    );
    expect(find.text('Find my Shruti'), findsOneWidget);
  });

  testWidgets('tapping the pitch card opens all 12 notes', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Select Shruti'));
    await tester.pumpAndSettle();

    expect(find.text('Select Shruti'), findsOneWidget);
    for (final pitch in Pitch.values) {
      expect(find.text(pitch.label), findsWidgets);
    }

    await tester.tap(find.text('G'));
    await tester.pumpAndSettle();

    expect(find.text('Select Shruti'), findsNothing);
    expect(find.text('G'), findsOneWidget);
  });

  testWidgets('closing the pitch sheet keeps the current Sa', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Select Shruti'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Select Shruti'), findsNothing);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('selecting a pitch updates the selected Sa display', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Higher Sa'));
    await tester.pumpAndSettle();

    expect(find.text(Pitch.cSharp.label), findsOneWidget);
  });

  testWidgets('all 12 pitch options can be selected', (tester) async {
    await pumpApp(tester);

    var pitch = Pitch.c;
    for (var step = 0; step < Pitch.values.length; step++) {
      expect(find.text(pitch.label), findsOneWidget);
      await tester.tap(find.byTooltip('Higher Sa'));
      await tester.pumpAndSettle();
      pitch = pitch.next;
    }

    expect(find.text(Pitch.c.label), findsOneWidget);
  });

  testWidgets('play and pause update the button label', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Play'));
    // Looping play ripple never settles; advance a frame instead.
    await tester.pump();
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
  });

  testWidgets('pitch can change while playing without stopping', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Higher Sa'));
    await tester.pump();
    await tester.tap(find.byTooltip('Higher Sa'));
    await tester.pump();

    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.text(Pitch.d.label), findsOneWidget);
  });
}
