/// Spoken (and mirrored UI) lines for the voice-first tutor.
///
/// Tone: calm, patient, encouraging — like a meditation guide and music teacher.
/// Never claim "sing with me" unless Harmony is actually audible while singing.
class TutorScripts {
  const TutorScripts._();

  static const welcome = <String>[
    "Hi. I'll help you find a comfortable Shruti.",
    "You don't need to know anything about singing.",
    'Just follow my voice.',
  ];

  static const discoverIntro = <String>[
    "Let's begin gently.",
    'Sing or hum one comfortable sound.',
    'Keep that same sound going for a few seconds.',
  ];

  /// Spoken countdown before a solo turn. Listening starts after the last step.
  static const countdown = <String>[
    "Let's try singing it again in 3...",
    '2...',
    '1...',
  ];

  /// Spoken countdown before assisted sing-along. Same 2... / 1... steps.
  static const assistedCountdown = <String>[
    "Let's sing together in 3...",
    '2...',
    '1...',
  ];

  static const sessionStopped = 'Session stopped';

  static const sessionStoppedSupport =
      "You can try again whenever you're ready.";

  /// After a listen window — warm, not commanding.
  static const listenComplete = 'Beautiful. You can stop there.';

  /// Next step after the single Stage 1 completion line.
  static const startingNoteSuccess = <String>[
    "Now I'll find a comfortable range for you.",
  ];

  static const startingNoteRetryOnce = <String>[
    "That's okay. Let's try once more.",
    'Sing or hum one steady, comfortable sound.',
    "I'll let you know when to begin.",
  ];

  static const startingNoteGuided = <String>[
    "No problem. I'll help you this time.",
    'Listen first.',
  ];

  /// Honest instruction after a reference — Harmony is silent while the user sings.
  static const nowTryThatSound = 'Now try that sound.';

  static const listenFirst = 'Listen first.';

  static const lowerSoundIntro = "Let's try a slightly lower sound.";

  static const middleSoundIntro = "Nice. Let's try one in the middle.";

  static const upperSoundIntro = 'One more. A slightly higher sound.';

  static const exploreHigher = "Let's try one a little higher.";

  static const exploreLower = "Let's try one a little lower.";

  static const softAffirmation = 'Good.';

  static const lowerAudibilityQuestion = 'Could you hear that sound clearly?';

  static const upperComfortQuestion = 'How did that feel?';

  static const lowerNotClear = "That's okay. Let's try a little higher.";

  static const upperNotComfortable = "That's okay.";

  static const listenOnceMore = "That's okay. Listen once more.";

  /// First solo retry on a range point, before sing-along help.
  static const rangeRetryOnce = "That's okay. Let's try once more.";

  static const letMeHelpYou = 'Let me help you.';

  /// Explains why sing-along practice is starting. Only used in assisted mode.
  static const practiceTogether =
      "That's okay. Let's practice it together so you can get familiar with the sound.";

  /// Only spoken when the reference will keep playing while the user sings.
  static const singAlongWithMe = 'Listen carefully, and sing along with me.';

  /// Spoken only after a confirmed user match during assisted singing.
  static const assistedReady = "Beautiful. You're ready.";

  static const tryOnYourOwn = 'Now try that sound on your own.';

  /// Another practice pass when assisted singing could not confirm the singer.
  static const practiceOnceMore =
      "That's okay. Let's practice that sound together once more.";

  static const letMeHelp = <String>['Let me help you.', 'Listen once more.'];

  static const makeEasier = <String>[
    "Let's make this easier.",
    'Listen once more.',
  ];

  static const unclearYesNo = <String>[
    "Sorry, I didn't quite catch that.",
    'Just say yes or no.',
  ];

  static const unclearComfort = <String>[
    "Sorry, I didn't quite catch that.",
    'Just say comfortable or not comfortable.',
  ];

  static String completion(String shrutiLabel) =>
      'Wonderful. We found a comfortable Shruti for you. Your Shruti is $shrutiLabel.';

  static const unresolved = <String>[
    "We couldn't find a comfortable Shruti just yet.",
    'We can try again whenever you like.',
  ];
}
