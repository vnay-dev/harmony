import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmony/theme/app_theme.dart';
import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/tutor/tutor_scripts.dart';
import 'package:harmony/ui/components/tutor_dialogue_text.dart';

void main() {
  Future<void> pumpDialogue(WidgetTester tester, String text) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 160,
              child: TutorDialogueText(text: text),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String visiblePlainText(WidgetTester tester) {
    final rich = tester.widget<RichText>(find.byType(RichText));
    return rich.text.toPlainText();
  }

  /// Collects leaf [TextSpan] styles whose text equals [fragment].
  List<TextStyle?> stylesFor(WidgetTester tester, String fragment) {
    final rich = tester.widget<RichText>(find.byType(RichText));
    final styles = <TextStyle?>[];
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text == fragment) {
          styles.add(span.style);
        }
        final children = span.children;
        if (children != null) {
          for (final child in children) {
            walk(child);
          }
        }
      }
    }

    walk(rich.text);
    return styles;
  }

  testWidgets('Stage 1 Beautiful gets blue-heart celebration', (tester) async {
    await pumpDialogue(tester, TutorScripts.stage1Success);
    expect(visiblePlainText(tester), 'Beautiful 💙! You did it.');
  });

  testWidgets('solo listen Beautiful gets the same celebration', (
    tester,
  ) async {
    await pumpDialogue(tester, TutorScripts.listenComplete);
    expect(visiblePlainText(tester), 'Beautiful 💙! You can stop there.');
  });

  testWidgets('soft affirmation lovely gets the same celebration', (
    tester,
  ) async {
    await pumpDialogue(tester, TutorScripts.softAffirmation);
    expect(visiblePlainText(tester), "That's lovely 💙!");
  });

  testWidgets('completion Wonderful gets the same celebration', (tester) async {
    await pumpDialogue(tester, TutorScripts.completion('C'));
    expect(
      visiblePlainText(tester),
      'Wonderful 💙! We found a comfortable Shruti for you. Your Shruti is C.',
    );
  });

  testWidgets('celebration bang uses dialogue color, heart stays accent', (
    tester,
  ) async {
    await pumpDialogue(tester, TutorScripts.stage1Success);

    final heartStyles = stylesFor(tester, '💙');
    final bangStyles = stylesFor(tester, '!');
    expect(heartStyles, isNotEmpty);
    expect(bangStyles, isNotEmpty);
    expect(heartStyles.first?.color, DesignTokens.accent);
    expect(bangStyles.first?.color, DesignTokens.onSurface);
    expect(bangStyles.first?.color, isNot(DesignTokens.accent));
  });

  testWidgets('non-compliment dialogue stays unchanged', (tester) async {
    await pumpDialogue(tester, TutorScripts.readyForNextStep);
    expect(visiblePlainText(tester), TutorScripts.readyForNextStep);
  });
}
