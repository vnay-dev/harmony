import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/ui/components/play_pause_button.dart';
import 'package:harmony/ui/components/shruti_info_sheet.dart';
import 'package:harmony/ui/screens/assist_mode_screen.dart';
import 'package:harmony/ui/screens/home_screen.dart';

import '../support/fake_audio_service.dart';

void main() {
  testWidgets('info icon opens What is Shruti sheet and dismisses cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(audioService: FakeAudioService())),
    );
    await tester.pump();

    expect(
      find.textContaining('Not sure which Shruti', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shruti-info-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('shruti-info-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ShrutiInfoSheet), findsOneWidget);
    expect(find.text('What is Shruti?'), findsOneWidget);
    expect(
      find.textContaining('pitch that feels most comfortable'),
      findsOneWidget,
    );
    expect(find.textContaining('key or tonic'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('shruti-info-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ShrutiInfoSheet), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Find my Shruti'), findsOneWidget);
  });

  testWidgets('Find my Shruti stops Home Shruti before opening Tutor Mode', (
    tester,
  ) async {
    final audio = FakeAudioService();

    await tester.pumpWidget(MaterialApp(home: HomeScreen(audioService: audio)));
    // Initial load only — avoid settle after play (ripple loops forever).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(PlayPauseButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(audio.isPlaying, isTrue);

    final pauseCountBeforeNavigate = audio.pauseCount;

    await tester.tap(find.text('Find my Shruti'));
    await tester.pump();
    await tester.pump();

    expect(audio.isPlaying, isFalse);
    expect(audio.pauseCount, greaterThan(pauseCountBeforeNavigate));
    expect(find.byType(AssistModeScreen), findsOneWidget);

    // Returning without a confirmed pitch must not auto-restart Home audio.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(audio.isPlaying, isFalse);
  });
}
