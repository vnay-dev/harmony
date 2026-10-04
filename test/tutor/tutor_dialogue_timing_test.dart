import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/tutor/tutor_dialogue_timing.dart';
import 'package:harmony/tutor/tutor_scripts.dart';

void main() {
  group('TutorDialogueTiming', () {
    test('reveals Stage 1 welcome words across the clip duration', () {
      final timing = TutorDialogueTiming.forLine(TutorScripts.welcome.first);
      expect(timing, isNotNull);
      expect(timing!.duration, const Duration(milliseconds: 5062));
      expect(timing.visibleTextAt(Duration.zero), isEmpty);
      expect(
        timing.visibleTextAt(const Duration(milliseconds: 400)),
        isNotEmpty,
      );
      expect(timing.visibleTextAt(timing.duration), TutorScripts.welcome.first);
    });

    test('keeps spoken instruction text identical to the script line', () {
      final timing = TutorDialogueTiming.forLine(
        TutorScripts.firstStepInstruction,
      );
      expect(timing, isNotNull);
      expect(timing!.duration, const Duration(milliseconds: 4505));
      expect(
        timing.visibleTextAt(timing.duration),
        TutorScripts.firstStepInstruction,
      );
    });

    test('matches retry clip duration so transcript ends with speech', () {
      final timing = TutorDialogueTiming.forLine(
        TutorScripts.startingNoteRetryOnce.first,
      );
      expect(timing, isNotNull);
      expect(timing!.duration, const Duration(milliseconds: 2601));
      expect(
        timing.visibleTextAt(timing.duration),
        TutorScripts.startingNoteRetryOnce.first,
      );
    });

    test('reveals Stage 2 opening words across the clip duration', () {
      final timing = TutorDialogueTiming.forLine(
        TutorScripts.startingNoteSuccess.first,
      );
      expect(timing, isNotNull);
      expect(timing!.duration, const Duration(milliseconds: 4505));
      expect(timing.visibleTextAt(Duration.zero), isEmpty);
      expect(
        timing.visibleTextAt(timing.duration),
        TutorScripts.startingNoteSuccess.first,
      );
    });

    test('reveals lower-sound listen prompt across the clip duration', () {
      final timing = TutorDialogueTiming.forLine(
        TutorScripts.lowerSoundListenPrompt,
      );
      expect(timing, isNotNull);
      expect(timing!.duration, const Duration(milliseconds: 7663));
      expect(
        timing.visibleTextAt(timing.duration),
        TutorScripts.lowerSoundListenPrompt,
      );
    });

    test('reveals first-attempt countdown across the clip duration', () {
      final timing = TutorDialogueTiming.forLine(
        TutorScripts.countdownFirst.first,
      );
      expect(timing, isNotNull);
      expect(timing!.duration, const Duration(milliseconds: 2136));
      expect(
        timing.visibleTextAt(timing.duration),
        TutorScripts.countdownFirst.first,
      );
    });
  });
}
