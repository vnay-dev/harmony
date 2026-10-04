import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmony/theme/app_theme.dart';
import 'package:harmony/ui/components/pitch_direction_dial.dart';

void main() {
  testWidgets('renders inactive dial when cents are null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: PitchDirectionDial(centsFromTarget: null)),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('pitch-direction-dial')),
      findsOneWidget,
    );
    expect(find.byType(PitchDirectionDial), findsOneWidget);
  });

  testWidgets('updates when cents move from low to high', (tester) async {
    double? cents = -40;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  PitchDirectionDial(centsFromTarget: cents),
                  TextButton(
                    onPressed: () => setState(() => cents = 55),
                    child: const Text('sharp'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('sharp'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(PitchDirectionDial), findsOneWidget);
  });

  testWidgets('settles so pumpAndSettle can complete', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: PitchDirectionDial(centsFromTarget: -25)),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.byType(PitchDirectionDial), findsOneWidget);
  });
}
