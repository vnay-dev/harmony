import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmony/theme/app_theme.dart';
import 'package:harmony/ui/components/pitch_direction_dial.dart';

void main() {
  Future<void> pumpDial(WidgetTester tester, {required double? cents}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: PitchDirectionDial(centsFromTarget: cents)),
      ),
    );
  }

  Future<void> pumpDialHost(
    WidgetTester tester, {
    required ValueNotifier<double?> cents,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ValueListenableBuilder<double?>(
            valueListenable: cents,
            builder: (context, value, _) {
              return PitchDirectionDial(centsFromTarget: value);
            },
          ),
        ),
      ),
    );
  }

  testWidgets('renders neutral listening state when cents are null', (
    tester,
  ) async {
    await pumpDial(tester, cents: null);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('pitch-direction-dial')),
      findsOneWidget,
    );
    expect(find.text('Listening for your pitch'), findsOneWidget);
    expect(find.text('Sing higher'), findsNothing);
    expect(find.text('Sing lower'), findsNothing);
    expect(find.text('On pitch'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('pitch-direction-legend')),
      findsOneWidget,
    );
    expect(find.text('Target zone'), findsOneWidget);
    expect(find.text('Outside'), findsOneWidget);
  });

  testWidgets('shows Sing higher when pitch is too low', (tester) async {
    await pumpDial(tester, cents: -70);
    await tester.pump();

    expect(find.text('Sing higher'), findsOneWidget);
    expect(find.text('On pitch'), findsNothing);
    expect(find.text('Sing lower'), findsNothing);
  });

  testWidgets('shows On pitch when within ±50 cent tolerance', (tester) async {
    await pumpDial(tester, cents: -25);
    await tester.pump();

    expect(find.text('On pitch'), findsOneWidget);
    expect(find.text('Sing higher'), findsNothing);
    expect(find.text('Sing lower'), findsNothing);
  });

  testWidgets('shows Sing lower when pitch is too high', (tester) async {
    await pumpDial(tester, cents: 70);
    await tester.pump();

    expect(find.text('Sing lower'), findsOneWidget);
    expect(find.text('On pitch'), findsNothing);
    expect(find.text('Sing higher'), findsNothing);
  });

  testWidgets('updates when cents move from low to high', (tester) async {
    final cents = ValueNotifier<double?>(-70);

    await pumpDialHost(tester, cents: cents);
    await tester.pump();
    expect(find.text('Sing higher'), findsOneWidget);

    cents.value = 70;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Sing lower'), findsOneWidget);
    expect(find.text('Sing higher'), findsNothing);
  });

  testWidgets('holds last direction briefly when cents become null', (
    tester,
  ) async {
    final cents = ValueNotifier<double?>(-70);

    await pumpDialHost(tester, cents: cents);
    await tester.pump();
    expect(find.text('Sing higher'), findsOneWidget);

    cents.value = null;
    await tester.pump();

    // Still holding the last valid cue inside the 250 ms window.
    expect(find.text('Sing higher'), findsOneWidget);
    expect(find.text('Listening for your pitch'), findsNothing);

    await tester.pump(
      PitchDirectionDial.nullHoldDuration - const Duration(milliseconds: 20),
    );
    expect(find.text('Sing higher'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Listening for your pitch'), findsOneWidget);
    expect(find.text('Sing higher'), findsNothing);
  });

  testWidgets('cancels null hold when a reading returns', (tester) async {
    final cents = ValueNotifier<double?>(70);

    await pumpDialHost(tester, cents: cents);
    await tester.pump();
    expect(find.text('Sing lower'), findsOneWidget);

    cents.value = null;
    await tester.pump();
    expect(find.text('Sing lower'), findsOneWidget);

    // Recovery before the hold expires.
    await tester.pump(const Duration(milliseconds: 100));
    cents.value = 20;
    await tester.pump();

    expect(find.text('On pitch'), findsOneWidget);
    expect(find.text('Listening for your pitch'), findsNothing);

    // Former hold must not fire after recovery.
    await tester.pump(PitchDirectionDial.nullHoldDuration);
    expect(find.text('On pitch'), findsOneWidget);
    expect(find.text('Listening for your pitch'), findsNothing);
  });

  testWidgets('avoids label flicker at the ±50 cent boundary', (tester) async {
    final cents = ValueNotifier<double?>(45);

    await pumpDialHost(tester, cents: cents);
    await tester.pump();
    expect(find.text('On pitch'), findsOneWidget);

    // Just outside 50 but inside hysteresis — stay on pitch.
    cents.value = 55;
    await tester.pump();
    expect(find.text('On pitch'), findsOneWidget);
    expect(find.text('Sing lower'), findsNothing);

    // Clearly outside the hysteresis band — switch to Sing lower.
    cents.value = 65;
    await tester.pump();
    expect(find.text('Sing lower'), findsOneWidget);

    // Just inside 50 but still outside enter-in threshold — stay high.
    cents.value = 45;
    await tester.pump();
    expect(find.text('Sing lower'), findsOneWidget);

    // Deep enough into the band to re-enter on pitch.
    cents.value = 35;
    await tester.pump();
    expect(find.text('On pitch'), findsOneWidget);
  });

  testWidgets('settles so pumpAndSettle can complete', (tester) async {
    await pumpDial(tester, cents: -25);

    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.byType(PitchDirectionDial), findsOneWidget);
    expect(find.text('On pitch'), findsOneWidget);
  });
}
