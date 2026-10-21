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

    group('punctuation modulation', () {
      test('keeps full stops so sentence endings stay clear', () {
        expect(
          normalizeKittenSpeechText(
            "Hi. I'll help you find a comfortable Shruti.",
          ),
          "Hi. I'll help you find a comfortable Shruti.",
        );
        expect(
          normalizeKittenSpeechText(TutorDialogues.s74.text),
          TutorDialogues.s74.text,
        );
      });

      test(
        'inserts a space after a glued full stop before the next sentence',
        () {
          expect(
            normalizeKittenSpeechText('Beautiful.You can stop there.'),
            'Beautiful. You can stop there.',
          );
        },
      );

      test('keeps commas as subtle pauses without inventing extras', () {
        expect(
          normalizeKittenSpeechText('Settle in, and follow my voice.'),
          'Settle in, and follow my voice.',
        );
        expect(
          normalizeKittenSpeechText('A soft,steady hum is enough.'),
          'A soft, steady hum is enough.',
        );
      });

      test('preserves question marks for questioning tone', () {
        expect(
          normalizeKittenSpeechText('Could you hear your voice clearly?'),
          'Could you hear your voice clearly?',
        );
        expect(
          normalizeKittenSpeechText('Ready for the next step?'),
          'Ready for the next step?',
        );
        expect(
          normalizeKittenSpeechText('How did that feel??'),
          'How did that feel?',
        );
      });

      test('keeps a single exclamation for gentle emphasis', () {
        expect(normalizeKittenSpeechText('You did it!'), 'You did it!');
        expect(normalizeKittenSpeechText('You did it!!!'), 'You did it!');
      });

      test('normalizes unicode ellipsis without duplicating pause markers', () {
        expect(
          normalizeKittenSpeechText('Listen to this sound…'),
          'Listen to this sound...',
        );
        expect(
          normalizeKittenSpeechText("Let's try singing it again in 3..."),
          "Let's try singing it again in 3...",
        );
      });

      test('does not invent punctuation for short unpunctuated lines', () {
        expect(normalizeKittenSpeechText('Just listen'), 'Just listen');
        expect(normalizeKittenSpeechText('2...'), '2...');
      });

      test('does not stack pauses when punctuation is already well spaced', () {
        const line =
            "That's okay. Let's practice it together so you can get familiar "
            'with the sound.';
        expect(normalizeKittenSpeechText(line), line);
      });

      test('punctuation modulation remains idempotent', () {
        const line = 'Wow!!! Ready…Next,step?';
        final once = normalizeKittenSpeechText(line);
        expect(once, 'Wow! Ready... Next, step?');
        expect(normalizeKittenSpeechText(once), once);
      });
    });
  });
}
