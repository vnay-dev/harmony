import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/ui/components/play_pause_button.dart';

void main() {
  testWidgets('center of play button triggers onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayPauseButton(
            isPlaying: false,
            isBusy: false,
            onPressed: () => taps++,
          ),
        ),
      ),
    );

    final button = find.byType(PlayPauseButton);
    await tester.tap(button);
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('taps outside the circular face do not trigger onPressed', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayPauseButton(
            isPlaying: false,
            isBusy: false,
            onPressed: () => taps++,
          ),
        ),
      ),
    );

    final box = tester.renderObject<RenderBox>(find.byType(PlayPauseButton));
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;

    // Far corner of the ripple stage — outside the raised circular face.
    await tester.tapAt(topLeft + const Offset(4, 4));
    await tester.pump();
    expect(taps, 0);

    // Near the stage edge, still outside the circular hit diameter.
    final radius = PlayPauseButton.hitTargetDiameter / 2;
    final center = topLeft + size.center(Offset.zero);
    await tester.tapAt(center + Offset(radius + 12, 0));
    await tester.pump();
    expect(taps, 0);

    // Center of the visible button still works.
    await tester.tapAt(center);
    await tester.pump();
    expect(taps, 1);

    // Just inside the circular face.
    await tester.tapAt(center + Offset(radius - 4, 0));
    await tester.pump();
    expect(taps, 2);
  });

  testWidgets('hit target diameter matches the raised play button size', (
    tester,
  ) async {
    expect(
      PlayPauseButton.hitTargetDiameter,
      DesignTokens.playButtonSize,
    );
  });
}
