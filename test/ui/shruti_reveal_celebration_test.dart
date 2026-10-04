import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmony/theme/app_theme.dart';
import 'package:harmony/ui/components/shruti_reveal_celebration.dart';

void main() {
  testWidgets('plays a one-shot celebration then settles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: ShrutiRevealCelebration(
              playHaptic: false,
              child: Text('C#'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('C#'), findsOneWidget);
    expect(find.byType(ShrutiRevealCelebration), findsOneWidget);

    // Post-frame start + mid-burst.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('C#'), findsOneWidget);

    // Finish the one-shot animation; it must not loop.
    await tester.pump(ShrutiRevealCelebration.duration);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('C#'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('keeps the Shruti label readable during the burst', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: ShrutiRevealCelebration(
              playHaptic: false,
              child: Text(
                key: ValueKey<String>('assist-confirmed-shruti'),
                'F',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(
      find.byKey(const ValueKey<String>('assist-confirmed-shruti')),
      findsOneWidget,
    );
    expect(find.text('F'), findsOneWidget);
  });
}
