import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/tutor/kitten_speech_text.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_scripts.dart';

void main() {
  group('normalizeKittenSpeechText', () {
    test('lowercases title-case Try so it is not spelled T-R-Y', () {
      const line = 'Try humming any comfortable, steady sound, like Sa.';
      expect(line, TutorDialogues.s66.text);
      expect(line, TutorScripts.firstStepInstruction);

      expect(
        normalizeKittenSpeechText(line),
        'try humming any comfortable, steady sound, like Sa.',
      );
    });

    test('lowercases other title-case Y-vowel words', () {
      expect(normalizeKittenSpeechText('Cry softly.'), 'cry softly.');
      expect(normalizeKittenSpeechText('Why wait?'), 'why wait?');
      expect(normalizeKittenSpeechText('Fly higher.'), 'fly higher.');
      expect(normalizeKittenSpeechText('Dry your hands.'), 'dry your hands.');
    });

    test('leaves normal title-case and lowercase try unchanged', () {
      expect(
        normalizeKittenSpeechText('Would you like to try a different one?'),
        'Would you like to try a different one?',
      );
      expect(normalizeKittenSpeechText("Hi, I'm Harmony."), "Hi, I'm Harmony.");
      expect(
        normalizeKittenSpeechText('Listen carefully.'),
        'Listen carefully.',
      );
    });

    test('leaves Sa and internal-capital abbreviations unchanged', () {
      expect(normalizeKittenSpeechText('like Sa.'), 'like Sa.');
      expect(normalizeKittenSpeechText('Earn a PhD.'), 'Earn a PhD.');
      expect(
        normalizeKittenSpeechText('Open the TTS menu.'),
        'Open the TTS menu.',
      );
    });

    test('is idempotent', () {
      const line = 'Try humming any comfortable, steady sound, like Sa.';
      final once = normalizeKittenSpeechText(line);
      expect(normalizeKittenSpeechText(once), once);
    });
  });
}
