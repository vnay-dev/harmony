import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/app/app_config.dart';
import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/tutor/tutor_voice.dart';
import 'package:harmony/ui/components/play_pause_button.dart';
import 'package:harmony/ui/components/shruti_info_sheet.dart';
import 'package:harmony/ui/screens/assist_mode_screen.dart';
import 'package:harmony/ui/screens/home_screen.dart';

import '../support/fake_audio_service.dart';
import '../support/fake_pitch_detection_service.dart';
import '../support/fake_reference_sound_generator.dart';

void main() {
  testWidgets('info icon opens What is Shruti sheet and dismisses cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          audioService: FakeAudioService(),
          enableFindMyShruti: true,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining(
        'What does Shruti mean in Indian music?',
        findRichText: true,
      ),
      findsOneWidget,
    );
    final infoButton = find.byKey(const ValueKey<String>('shruti-info-button'));
    expect(infoButton, findsOneWidget);

    final infoIcon = tester.widget<Icon>(
      find.descendant(of: infoButton, matching: find.byType(Icon)),
    );
    expect(infoIcon.size, 18);
    expect(infoIcon.color, DesignTokens.onSurface);

    final infoButtonSize = tester.getSize(infoButton);
    expect(infoButtonSize.width, greaterThanOrEqualTo(44));
    expect(infoButtonSize.height, greaterThanOrEqualTo(44));

    await tester.tap(infoButton);
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

  testWidgets('hides Find my Shruti when the feature flag is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          audioService: FakeAudioService(),
          enableFindMyShruti: false,
        ),
      ),
    );
    await tester.pump();

    expect(AppConfig.enableFindMyShruti, isFalse);
    expect(find.text('Find my Shruti'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('find-my-shruti-button')),
      findsNothing,
    );
    expect(find.byType(AssistModeScreen), findsNothing);
    expect(find.byType(PlayPauseButton), findsOneWidget);
    expect(
      find.textContaining(
        'What does Shruti mean in Indian music?',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('enabling Find my Shruti restores the Home entry point', (
    tester,
  ) async {
    final audio = FakeAudioService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          audioService: audio,
          enableFindMyShruti: true,
          assistModeBuilder: (_) => AssistModeScreen(
            detectionService: FakePitchDetectionService(),
            audioService: FakeAudioService(),
            referenceSoundGenerator: FakeReferenceSoundGenerator(),
            tutorVoice: SilentTutorVoice(),
            autoBegin: false,
            prepareAudioSession: () async {},
            wait: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Find my Shruti'), findsOneWidget);
    await tester.tap(find.text('Find my Shruti'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AssistModeScreen), findsOneWidget);
  });

  testWidgets('Find my Shruti stops Home Shruti before opening Tutor Mode', (
    tester,
  ) async {
    final audio = FakeAudioService();

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          audioService: audio,
          enableFindMyShruti: true,
          // Avoid downloading the Kitten model in widget tests.
          assistModeBuilder: (_) => AssistModeScreen(
            detectionService: FakePitchDetectionService(),
            audioService: FakeAudioService(),
            referenceSoundGenerator: FakeReferenceSoundGenerator(),
            tutorVoice: SilentTutorVoice(),
            autoBegin: false,
            prepareAudioSession: () async {},
            wait: (_) async {},
          ),
        ),
      ),
    );
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
