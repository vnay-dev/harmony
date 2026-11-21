import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/tutor/tutor_dialogue_timing.dart';
import 'package:harmony/ui/components/tutor_dialogue_text.dart';

void main() {
  testWidgets('types the line from its text duration', (tester) async {
    const line = 'Hello there friend';
    final duration = TutorDialogueTiming.durationFor(line);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 160,
            child: TutorDialogueText(text: line, isSpeaking: true),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final early = _spanAlphas(tester);
    expect(early.first, greaterThan(0));
    expect(early.last, 0);

    await tester.pump(duration);
    final done = _spanAlphas(tester);
    expect(done.every((alpha) => alpha > 0.99), isTrue);
  });

  testWidgets(
    'starts the typewriter when playback starts and follows the clip',
    (tester) async {
      const line = 'Hello there friend';
      const playback = Duration(milliseconds: 400);
      expect(playback, isNot(TutorDialogueTiming.durationFor(line)));

      Future<void> show({required bool hold, Duration? reveal}) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 160,
                child: TutorDialogueText(
                  text: line,
                  isSpeaking: true,
                  holdReveal: hold,
                  revealDuration: reveal,
                ),
              ),
            ),
          ),
        );
      }

      await show(hold: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_spanAlphas(tester).every((alpha) => alpha == 0), isTrue);

      await show(hold: false, reveal: playback);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final early = _spanAlphas(tester);
      expect(early.first, greaterThan(0));
      expect(early.last, 0);

      await tester.pump(playback);
      final done = _spanAlphas(tester);
      expect(done.every((alpha) => alpha > 0.99), isTrue);
    },
  );

  testWidgets('a failed playback reveals on the text pace after the hold', (
    tester,
  ) async {
    const line = 'Hello there friend';
    final textPace = TutorDialogueTiming.durationFor(line);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 160,
            child: TutorDialogueText(
              text: line,
              isSpeaking: true,
              holdReveal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(_spanAlphas(tester).every((alpha) => alpha == 0), isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 160,
            child: TutorDialogueText(text: line, isSpeaking: true),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_spanAlphas(tester).last, 0);

    await tester.pump(textPace);
    expect(_spanAlphas(tester).every((alpha) => alpha > 0.99), isTrue);
  });

  testWidgets('cancellation while waiting shows the line immediately', (
    tester,
  ) async {
    const line = 'Hello there friend';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 160,
            child: TutorDialogueText(
              text: line,
              isSpeaking: true,
              holdReveal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_spanAlphas(tester).every((alpha) => alpha == 0), isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 160,
            child: TutorDialogueText(text: line),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_spanAlphas(tester).every((alpha) => alpha > 0.99), isTrue);
  });
}

List<double> _spanAlphas(WidgetTester tester) {
  final text = tester.widget<Text>(find.byType(Text));
  final root = text.textSpan! as TextSpan;
  return root.children!
      .whereType<TextSpan>()
      .map((span) => span.style?.color?.a ?? 0)
      .toList();
}
