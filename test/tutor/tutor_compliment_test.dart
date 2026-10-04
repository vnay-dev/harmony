import 'package:flutter_test/flutter_test.dart';
import 'package:harmony/tutor/tutor_compliment.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_scripts.dart';

void main() {
  group('TutorCompliment', () {
    test('detects Stage 1 success Beautiful', () {
      expect(
        TutorCompliment.containsCompliment(TutorScripts.stage1Success),
        isTrue,
      );
      expect(
        TutorCompliment.celebrationInsertIndex(TutorScripts.stage1Success),
        'Beautiful'.length,
      );
    });

    test('detects solo listen Beautiful', () {
      expect(
        TutorCompliment.containsCompliment(TutorScripts.listenComplete),
        isTrue,
      );
      expect(
        TutorCompliment.celebrationInsertIndex(TutorScripts.listenComplete),
        'Beautiful'.length,
      );
    });

    test('detects soft affirmation lovely', () {
      expect(
        TutorCompliment.containsCompliment(TutorScripts.softAffirmation),
        isTrue,
      );
      expect(
        TutorCompliment.celebrationInsertIndex(TutorDialogues.s26.text),
        TutorDialogues.s26.text.indexOf('lovely') + 'lovely'.length,
      );
    });

    test('detects completion Wonderful', () {
      final line = TutorScripts.completion('C');
      expect(TutorCompliment.containsCompliment(line), isTrue);
      expect(TutorCompliment.celebrationInsertIndex(line), 'Wonderful'.length);
    });

    test('ignores non-compliment dialogue', () {
      expect(
        TutorCompliment.containsCompliment(TutorScripts.readyForNextStep),
        isFalse,
      );
      expect(
        TutorCompliment.containsCompliment(TutorScripts.makeThisEasier),
        isFalse,
      );
      expect(
        TutorCompliment.containsCompliment(TutorScripts.stage1ListenPrompt),
        isFalse,
      );
      expect(TutorCompliment.celebrationInsertIndex('Take your time.'), -1);
    });

    test('does not treat comfortable as a compliment adjective', () {
      expect(
        TutorCompliment.containsCompliment(
          TutorDialogues.s39.text.replaceFirst('Wonderful', 'Comfortable'),
        ),
        isFalse,
      );
    });
  });
}
