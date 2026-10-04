/// One spoken tutor line: transcript text and recording id are inseparable.
///
/// When Harmony speaks a dialogue, both the audio clip and the on-screen text
/// must come from the same [TutorDialogue] instance.
class TutorDialogue {
  const TutorDialogue({required this.id, required this.text});

  /// Bundled recording id, for example `S70`.
  final String id;

  /// Exact spoken wording. Mirrored on screen while this clip plays.
  final String text;

  String get assetFileName => '$id.mp3';
}

/// Canonical spoken dialogues for Tutor Mode.
///
/// This is the single source of truth for dialogue id ↔ spoken text.
/// [TutorScripts] exposes session-facing groupings; [TutorAudioCatalog] resolves
/// playback from these definitions. Do not add a second text table for the same
/// recording id.
abstract final class TutorDialogues {
  const TutorDialogues._();

  static const s01 = TutorDialogue(
    id: 'S01',
    text: "Hi. I'll help you find a comfortable Shruti.",
  );
  static const s02 = TutorDialogue(
    id: 'S02',
    text: "You don't need to know anything about singing.",
  );
  static const s03 = TutorDialogue(
    id: 'S03',
    text: 'Settle in, and follow my voice.',
  );
  static const s04 = TutorDialogue(id: 'S04', text: "Let's begin gently.");
  static const s05 = TutorDialogue(
    id: 'S05',
    text: 'Sing or hum a sound that feels comfortable.',
  );
  static const s06 = TutorDialogue(
    id: 'S06',
    text: 'Stay with it for a few seconds.',
  );
  static const s07 = TutorDialogue(
    id: 'S07',
    text: "Let's try singing it again in 3...",
  );
  static const s08 = TutorDialogue(id: 'S08', text: '2...');
  static const s09 = TutorDialogue(id: 'S09', text: '1...');

  /// First solo countdown on a range point (no prior attempt).
  static const s75 = TutorDialogue(
    id: 'S75',
    text: "Let's try singing it in 3...",
  );
  static const s10 = TutorDialogue(
    id: 'S10',
    text: 'Beautiful. You can stop there.',
  );
  static const s11 = TutorDialogue(
    id: 'S11',
    text: "Now let's find a comfortable range for your voice.",
  );
  static const s12 = TutorDialogue(
    id: 'S12',
    text: "That's okay. Let's try once more.",
  );
  static const s13 = TutorDialogue(
    id: 'S13',
    text: 'A soft, steady hum is enough.',
  );
  static const s14 = TutorDialogue(
    id: 'S14',
    text: "That's alright. I'll let you hear the sound first.",
  );
  static const s15 = TutorDialogue(id: 'S15', text: 'Just listen.');

  /// First Stage 2 reference after the lower-sound intro.
  static const s74 = TutorDialogue(
    id: 'S74',
    text:
        "I'll play a sound for you now. Listen carefully. When it finishes, it's your turn to sing it back.",
  );
  static const s17 = TutorDialogue(
    id: 'S17',
    text: "We'll take this more gently.",
  );
  static const s18 = TutorDialogue(id: 'S18', text: "Let's listen once more.");
  static const s19 = TutorDialogue(
    id: 'S19',
    text: "That's okay. Let's listen once more.",
  );
  static const s20 = TutorDialogue(
    id: 'S20',
    text: "Let's try a slightly lower sound.",
  );
  static const s21 = TutorDialogue(
    id: 'S21',
    text: "Let's try one in the middle.",
  );
  static const s22 = TutorDialogue(
    id: 'S22',
    text: 'Now a slightly higher sound.',
  );
  static const s23 = TutorDialogue(
    id: 'S23',
    text: "Let's move a little higher.",
  );
  static const s24 = TutorDialogue(
    id: 'S24',
    text: "Let's move a little lower.",
  );
  static const s25 = TutorDialogue(
    id: 'S25',
    text: 'Could you hear your voice clearly?',
  );
  static const s26 = TutorDialogue(id: 'S26', text: "That's lovely.");
  static const s27 = TutorDialogue(
    id: 'S27',
    text: "That's okay. Let's try a little higher.",
  );
  static const s28 = TutorDialogue(
    id: 'S28',
    text: "Sorry, I didn't quite catch that.",
  );
  static const s29 = TutorDialogue(id: 'S29', text: 'Yes or no is enough.');
  static const s30 = TutorDialogue(id: 'S30', text: 'How did that feel?');
  static const s31 = TutorDialogue(
    id: 'S31',
    text: "That's all right. We'll keep this comfortable.",
  );
  static const s32 = TutorDialogue(
    id: 'S32',
    text: 'You can say comfortable, or not comfortable.',
  );
  static const s33 = TutorDialogue(id: 'S33', text: "There's no hurry.");
  static const s34 = TutorDialogue(
    id: 'S34',
    text:
        "That's okay. Let's practice it together so you can get familiar with the sound.",
  );
  static const s35 = TutorDialogue(
    id: 'S35',
    text: 'Listen carefully, and sing along with me.',
  );
  static const s36 = TutorDialogue(
    id: 'S36',
    text: "Let's sing together in 3...",
  );
  static const s37 = TutorDialogue(
    id: 'S37',
    text: "That's okay. Let's practice that sound together once more.",
  );
  static const s38 = TutorDialogue(
    id: 'S38',
    text: 'Now try that sound on your own.',
  );
  static const s39 = TutorDialogue(
    id: 'S39',
    text: 'Wonderful. We found a comfortable Shruti for you.',
  );
  static const s40 = TutorDialogue(id: 'S40', text: 'Your Shruti is C.');
  static const s41 = TutorDialogue(id: 'S41', text: 'Your Shruti is C sharp.');
  static const s42 = TutorDialogue(id: 'S42', text: 'Your Shruti is D.');
  static const s43 = TutorDialogue(id: 'S43', text: 'Your Shruti is D sharp.');
  static const s44 = TutorDialogue(id: 'S44', text: 'Your Shruti is E.');
  static const s45 = TutorDialogue(id: 'S45', text: 'Your Shruti is F.');
  static const s46 = TutorDialogue(id: 'S46', text: 'Your Shruti is F sharp.');
  static const s47 = TutorDialogue(id: 'S47', text: 'Your Shruti is G.');
  static const s48 = TutorDialogue(id: 'S48', text: 'Your Shruti is G sharp.');
  static const s49 = TutorDialogue(id: 'S49', text: 'Your Shruti is A.');
  static const s50 = TutorDialogue(id: 'S50', text: 'Your Shruti is A sharp.');
  static const s51 = TutorDialogue(id: 'S51', text: 'Your Shruti is B.');
  static const s52 = TutorDialogue(
    id: 'S52',
    text: "We haven't found a comfortable Shruti just yet.",
  );
  static const s53 = TutorDialogue(
    id: 'S53',
    text: 'We can try again whenever you like.',
  );
  static const s54 = TutorDialogue(
    id: 'S54',
    text: "First, I'll listen to your voice.",
  );
  static const s55 = TutorDialogue(
    id: 'S55',
    text: "Then, we'll explore a few sounds around it.",
  );
  static const s56 = TutorDialogue(
    id: 'S56',
    text: "You'll tell me how each one feels.",
  );
  static const s57 = TutorDialogue(
    id: 'S57',
    text: "We'll keep going until we find a comfortable place for your voice.",
  );
  static const s58 = TutorDialogue(
    id: 'S58',
    text:
        "There's no right or wrong answer. Just sing naturally and tell me how it feels.",
  );

  /// Retained; not used by Stage 1 initial failure (removed from that path).
  static const s60 = TutorDialogue(
    id: 'S60',
    text: "That's okay. Let's try again.",
  );

  /// Stage 1 failure — final spoken line, then grey instruction style.
  static const s61 = TutorDialogue(
    id: 'S61',
    text: "Listen to the sound again, then sing it when you're ready.",
  );

  /// Bundled recording retained; not used by Stage 1 initial failure recovery.
  static const s62 = TutorDialogue(
    id: 'S62',
    text: 'Take your time. You can do this.',
  );
  static const s63 = TutorDialogue(
    id: 'S63',
    text: "Let's take a small step back and listen to your voice once more.",
  );

  /// Current Stage 1 welcome / CTA path.
  static const s64 = TutorDialogue(
    id: 'S64',
    text:
        "Hi, I'm Harmony. I'll help you find a comfortable Shruti for your voice.",
  );
  static const s65 = TutorDialogue(
    id: 'S65',
    text: 'To start, I need to listen to your voice.',
  );
  static const s66 = TutorDialogue(
    id: 'S66',
    text: 'Try humming any comfortable, steady sound, like Sa.',
  );
  static const s67 = TutorDialogue(id: 'S67', text: 'Beautiful. You did it.');
  static const s68 = TutorDialogue(id: 'S68', text: 'Ready for the next step?');

  /// Stage 2 opening after the user taps "I'm ready".
  static const s72 = TutorDialogue(
    id: 'S72',
    text: "Now that I understand your voice, let's find your singing range.",
  );

  /// Stage 2 recovery (and Stage 1 failure lead-in).
  static const s70 = TutorDialogue(
    id: 'S70',
    text: "That's okay. Let's make this a little easier.",
  );
  static const s71 = TutorDialogue(
    id: 'S71',
    text:
        "That sound didn't feel quite right. Would you like to try a different one?",
  );
  static const s73 = TutorDialogue(
    id: 'S73',
    text: "That's perfectly okay. Let's stay with this one for now.",
  );

  /// On-screen + spoken while the assisted-singing reference is playing.
  static const s76 = TutorDialogue(
    id: 'S76',
    text: 'Listen and sing along with this sound.',
  );

  /// Every dialogue definition, including reserved orientation ids.
  static const List<TutorDialogue> all = <TutorDialogue>[
    s01,
    s02,
    s03,
    s04,
    s05,
    s06,
    s07,
    s08,
    s09,
    s10,
    s11,
    s12,
    s13,
    s14,
    s15,
    s17,
    s18,
    s19,
    s20,
    s21,
    s22,
    s23,
    s24,
    s25,
    s26,
    s27,
    s28,
    s29,
    s30,
    s31,
    s32,
    s33,
    s34,
    s35,
    s36,
    s37,
    s38,
    s39,
    s40,
    s41,
    s42,
    s43,
    s44,
    s45,
    s46,
    s47,
    s48,
    s49,
    s50,
    s51,
    s52,
    s53,
    s54,
    s55,
    s56,
    s57,
    s58,
    s60,
    s61,
    s62,
    s63,
    s64,
    s65,
    s66,
    s67,
    s68,
    s70,
    s71,
    s72,
    s73,
    s74,
    s75,
    s76,
  ];

  /// Ids reserved for orientation; not bundled yet.
  static const Set<String> reservedWithoutRecordingIds = <String>{
    'S54',
    'S55',
    'S56',
    'S57',
    'S58',
  };

  /// Dialogues with a bundled MP3 available for playback.
  static final List<TutorDialogue> withBundledRecording = all
      .where((d) => !reservedWithoutRecordingIds.contains(d.id))
      .toList(growable: false);

  /// Stage 1 initial failure spoken lines (S70 → S61).
  ///
  /// Does not include S60 ("Let's try again"), S62, or S71.
  /// Stage 2 still uses S70 / S71 / S73 separately.
  static const List<TutorDialogue> stage1FailureRecovery = <TutorDialogue>[
    s70,
    s61,
  ];

  /// Stage 2 recovery lines (S70, S71, S73) plus step-back (S63).
  static const List<TutorDialogue> stage2Recovery = <TutorDialogue>[
    s70,
    s71,
    s73,
    s63,
  ];

  static final Map<String, TutorDialogue> _byId = <String, TutorDialogue>{
    for (final dialogue in all) dialogue.id: dialogue,
  };

  static final Map<String, TutorDialogue> _byText = <String, TutorDialogue>{
    for (final dialogue in all) dialogue.text: dialogue,
  };

  static TutorDialogue? byId(String id) => _byId[id];

  static TutorDialogue? byText(String text) => _byText[text.trim()];
}
