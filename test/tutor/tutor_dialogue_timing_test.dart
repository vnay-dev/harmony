import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/tutor/tutor_dialogue_timing.dart';
import 'package:harmony/tutor/tutor_scripts.dart';

void main() {
  group('TutorDialogueTiming', () {
    test('paces a line from its text, not a recording length', () {
      final line = TutorScripts.welcome.first;
      final timing = TutorDialogueTiming.forLine(line);
      expect(timing, isNotNull);
      expect(timing!.duration, TutorDialogueTiming.durationFor(line));
      expect(timing.duration, isNot(const Duration(milliseconds: 5062)));
      expect(timing.visibleTextAt(Duration.zero), isEmpty);
      expect(
        timing.visibleTextAt(const Duration(milliseconds: 400)),
        isNotEmpty,
      );
      expect(timing.visibleTextAt(timing.duration), line);
    });

    test('keeps spoken instruction text identical to the script line', () {
      final line = TutorScripts.firstStepInstruction;
      final timing = TutorDialogueTiming.forLine(line);
      expect(timing, isNotNull);
      expect(timing!.duration, TutorDialogueTiming.durationFor(line));
      expect(timing.visibleTextAt(timing.duration), line);
    });

    test('uses the same text pace for a retry line', () {
      final line = TutorScripts.startingNoteRetryOnce.first;
      final timing = TutorDialogueTiming.forLine(line);
      expect(timing, isNotNull);
      expect(timing!.duration, TutorDialogueTiming.durationFor(line));
      expect(timing.visibleTextAt(timing.duration), line);
    });

    test('bounds short and long lines', () {
      expect(
        TutorDialogueTiming.durationFor('Hi'),
        TutorDialogueTiming.minReveal,
      );
      final longLine = 'word ' * 400;
      expect(
        TutorDialogueTiming.durationFor(longLine),
        TutorDialogueTiming.maxReveal,
      );
    });

    test('reveals the full line by the end of its text duration', () {
      for (final line in <String>[
        TutorScripts.startingNoteSuccess.first,
        TutorScripts.lowerSoundListenPrompt,
        TutorScripts.countdownFirst.first,
      ]) {
        final timing = TutorDialogueTiming.forLine(line)!;
        expect(timing.duration, TutorDialogueTiming.durationFor(line));
        expect(timing.visibleTextAt(timing.duration), line);
      }
    });
  });
}
