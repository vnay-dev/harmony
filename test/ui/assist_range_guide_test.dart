import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/pitch/assist_range_targets.dart';
import 'package:harmony/theme/app_theme.dart';
import 'package:harmony/ui/components/assist_range_guide.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpGuide(
    WidgetTester tester, {
    required AssistRangePoint point,
    required double targetPosition,
    double? voicePosition,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AssistRangeGuide(
            currentPoint: point,
            targetPosition: targetPosition,
            voicePosition: voicePosition,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double targetMarkerTop(WidgetTester tester) {
    final marker = find.byKey(
      const ValueKey<String>('assist-range-target-marker'),
    );
    expect(marker, findsOneWidget);
    final positioned = tester.widget<Positioned>(
      find.ancestor(of: marker, matching: find.byType(Positioned)).first,
    );
    return positioned.top!;
  }

  testWidgets('Lower Sa target marker sits at LOW', (tester) async {
    await pumpGuide(
      tester,
      point: AssistRangePoint.lowerSa,
      targetPosition: 0.0,
    );

    expect(find.text('Lower Sa'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey<String>('assist-range-target-${AssistRangePoint.lowerSa}'),
      ),
      findsOneWidget,
    );

    final top = targetMarkerTop(tester);
    // LOW is near the bottom of the track (largest top offset).
    expect(top, greaterThan(150));
  });

  testWidgets('Pa target marker sits at MID', (tester) async {
    await pumpGuide(
      tester,
      point: AssistRangePoint.pa,
      targetPosition: 0.5,
    );

    expect(find.text('Pa'), findsOneWidget);
    expect(find.text('Mid'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey<String>('assist-range-target-${AssistRangePoint.pa}'),
      ),
      findsOneWidget,
    );

    final top = targetMarkerTop(tester);
    // MID is near the vertical center of the ~220px track.
    expect(top, greaterThan(70));
    expect(top, lessThan(150));
  });

  testWidgets('Upper Sa target marker sits at HIGH', (tester) async {
    await pumpGuide(
      tester,
      point: AssistRangePoint.upperSa,
      targetPosition: 1.0,
    );

    expect(find.text('Upper Sa'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey<String>('assist-range-target-${AssistRangePoint.upperSa}'),
      ),
      findsOneWidget,
    );

    final top = targetMarkerTop(tester);
    // HIGH is near the top of the track (smallest top offset).
    expect(top, lessThan(20));
  });

  testWidgets('voice marker is independent of the target marker', (
    tester,
  ) async {
    await pumpGuide(
      tester,
      point: AssistRangePoint.pa,
      targetPosition: 0.5,
      voicePosition: 0.0,
    );

    final targetTop = targetMarkerTop(tester);
    final voiceMarker = find.byKey(
      const ValueKey<String>('assist-range-voice-marker'),
    );
    expect(voiceMarker, findsOneWidget);
    final voiceTop = tester.widget<Positioned>(
      find.ancestor(of: voiceMarker, matching: find.byType(Positioned)).first,
    ).top!;

    expect(voiceTop, isNot(closeTo(targetTop, 1)));
    expect(voiceTop, greaterThan(targetTop));
  });
}
