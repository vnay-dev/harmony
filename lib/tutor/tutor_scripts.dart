import 'package:harmony/tutor/tutor_dialogue.dart';

/// Spoken (and mirrored UI) lines for the voice-first tutor.
///
/// Spoken wording comes from [TutorDialogues] so transcript text and audio ids
/// stay a single definition. UI-only labels that are never spoken stay here.
///
/// Tone: calm, patient, encouraging — like a meditation guide and music teacher.
/// Never claim "sing with me" unless Harmony is actually audible while singing.
class TutorScripts {
  const TutorScripts._();

  /// Stage 1 introduction. Spoken once before any listening.
  static final welcome = <String>[TutorDialogues.s64.text];

  /// Spoken after the user taps "Let's begin".
  static final firstStepListen = TutorDialogues.s65.text;

  /// Spoken after [firstStepListen], before the ready CTA.
  static final firstStepInstruction = TutorDialogues.s66.text;

  /// On-screen instruction while Harmony listens in Stage 1.
  ///
  /// Displayed as a secondary hint (not spoken dialogue).
  static const stage1ListenPrompt =
      'Your turn. Sing one steady sound for a few seconds.';

  /// Spoken once per session after Stage 1 success acknowledgement.
  ///
  /// Kept for Stage 2 entry. Not part of the Stage 1 CTA redesign.
  static final orientation = <String>[
    TutorDialogues.s54.text,
    TutorDialogues.s55.text,
    TutorDialogues.s56.text,
    TutorDialogues.s57.text,
    TutorDialogues.s58.text,
  ];

  /// Legacy discover intro. Stage 1 now uses [firstStepListen] /
  /// [firstStepInstruction] instead.
  static final discoverIntro = <String>[
    TutorDialogues.s04.text,
    TutorDialogues.s05.text,
    TutorDialogues.s06.text,
  ];

  /// Spoken countdown before a solo turn. Listening starts after the last step.
  ///
  /// Stage 1 no longer uses a countdown. Stage 2 still does.
  /// Use [countdownFirst] when the current range point has not failed yet;
  /// use [countdown] on later solo retries of the same point.
  static final countdownFirst = <String>[
    TutorDialogues.s75.text,
    TutorDialogues.s08.text,
    TutorDialogues.s09.text,
  ];

  /// Solo retry countdown after a prior miss on the same range point.
  static final countdown = <String>[
    TutorDialogues.s07.text,
    TutorDialogues.s08.text,
    TutorDialogues.s09.text,
  ];

  /// Spoken countdown before assisted sing-along. Same 2... / 1... steps.
  static final assistedCountdown = <String>[
    TutorDialogues.s36.text,
    TutorDialogues.s08.text,
    TutorDialogues.s09.text,
  ];

  /// True for solo / assisted countdown step lines (including stray "1...").
  static bool isCountdownLine(String line) {
    final trimmed = line.trim();
    return countdownFirst.contains(trimmed) ||
        countdown.contains(trimmed) ||
        assistedCountdown.contains(trimmed);
  }

  static const sessionStopped = 'Session stopped';

  static const sessionStoppedSupport =
      "You can try again whenever you're ready.";

  /// Stage 1 success acknowledgement.
  static final stage1Success = TutorDialogues.s67.text;

  /// After Stage 1 success, before the user continues.
  static final readyForNextStep = TutorDialogues.s68.text;

  /// After a Stage 2 listen window — warm, not commanding.
  static final listenComplete = TutorDialogues.s10.text;

  /// Stage 2 opening after the user taps "I'm ready".
  static final startingNoteSuccess = <String>[TutorDialogues.s72.text];

  static final startingNoteRetryOnce = <String>[
    TutorDialogues.s12.text,
    TutorDialogues.s13.text,
    "I'll let you know when to begin.",
  ];

  /// Stage 1 failure spoken lines (S70 → S61). Mirrored on screen.
  ///
  /// After S61 finishes, the same S61 text switches to instruction style and
  /// the example / shuffle controls appear. S60 / S71 / S62 are not part of
  /// this sequence.
  static final startingNoteGuided = <String>[
    TutorDialogues.s70.text,
    TutorDialogues.s61.text,
  ];

  /// Spoken immediately before a reference sound the singer should hear, not sing.
  static final listenFirst = TutorDialogues.s15.text;

  /// Spoken after [lowerSoundIntro], before the first Stage 2 reference.
  static final lowerSoundListenPrompt = TutorDialogues.s74.text;

  /// On-screen only while a Stage 2 reference tone plays (not spoken).
  static const referenceListenPrompt = 'Listen to this sound…';

  /// Tertiary Stage 1 action under "Listen to an example" (not spoken).
  static const shuffleExamplePrompt = 'Want to try another sound?';

  /// Transient labels on the example button while shuffling (not spoken).
  static const exampleLoadingLabel = 'Loading a new sound';
  static const exampleLoadedLabel = 'New sound loaded';

  static final lowerSoundIntro = TutorDialogues.s20.text;

  static final middleSoundIntro = TutorDialogues.s21.text;

  static final upperSoundIntro = TutorDialogues.s22.text;

  static final exploreHigher = TutorDialogues.s23.text;

  static final exploreLower = TutorDialogues.s24.text;

  static final softAffirmation = TutorDialogues.s26.text;

  static final lowerAudibilityQuestion = TutorDialogues.s25.text;

  static final upperComfortQuestion = TutorDialogues.s30.text;

  static final lowerNotClear = TutorDialogues.s27.text;

  static final upperNotComfortable = TutorDialogues.s31.text;

  /// Unused legacy constant (not spoken). Kept so older references stay safe.
  static const listenOnceMore = "That's okay. Listen once more.";

  /// First solo retry on a range point, before sing-along help.
  static final rangeRetryOnce = TutorDialogues.s12.text;

  static final letMeHelpYou = 'Let me help you.';

  /// Explains why sing-along practice is starting. Only used in assisted mode.
  static final practiceTogether = TutorDialogues.s34.text;

  /// Only spoken when the reference will keep playing while the user sings.
  static final singAlongWithMe = TutorDialogues.s35.text;

  /// Spoken and shown while the assisted-singing reference is playing.
  ///
  /// Replaces any leftover countdown transcript (e.g. "1...") for that phase.
  static final assistedSingAlongPrompt = TutorDialogues.s76.text;

  /// Spoken only after a confirmed user match during assisted singing.
  static const assistedReady = "Beautiful. You're ready.";

  static final tryOnYourOwn = TutorDialogues.s38.text;

  /// Another practice pass when assisted singing could not confirm the singer.
  static final practiceOnceMore = TutorDialogues.s37.text;

  /// After assisted practice, before offering a nearby sound.
  static final makeThisEasier = TutorDialogues.s70.text;

  /// Yes/No question after a sound did not feel right.
  ///
  /// Does not name pitch, notes, or targets.
  static final offerDifferentSound = TutorDialogues.s71.text;

  /// Spoken when the user wants to keep the current sound.
  static final stayWithThisSound = TutorDialogues.s73.text;

  /// Returns to Stage 1 listening without restarting the session.
  static final stepBackToVoice = TutorDialogues.s63.text;

  static final letMeHelp = <String>[
    'Let me help you.',
    TutorDialogues.s18.text,
  ];

  static final makeEasier = <String>[
    TutorDialogues.s17.text,
    TutorDialogues.s18.text,
  ];

  static final unclearYesNo = <String>[
    TutorDialogues.s28.text,
    TutorDialogues.s29.text,
  ];

  static final unclearComfort = <String>[
    TutorDialogues.s28.text,
    TutorDialogues.s32.text,
  ];

  static String completion(String shrutiLabel) =>
      '${TutorDialogues.s39.text} Your Shruti is $shrutiLabel.';

  static final unresolved = <String>[
    TutorDialogues.s52.text,
    TutorDialogues.s53.text,
  ];

  // --- Tutor CTA labels (not spoken) ---

  static const ctaLetsBegin = "Let's begin";

  /// Secondary control under the Stage 1 instruction (not spoken).
  static const hearSaLabel = 'Listen to an example';

  /// Shown after Stage 1 instructions, before listening begins.
  static const ctaImReadyToSingSa = "I'm ready to sing Sa";

  /// Shown after Stage 1 success, before Stage 2.
  static const ctaImReady = "I'm ready";

  static const ctaLetsTryAgain = "Let's try again";

  /// Shown after the Stage 2 lower-sound listen prompt (S74), before reference.
  static const ctaPlayTheSound = 'Play the sound';

  /// Lower audibility Yes (not spoken).
  static const ctaHeardClearly = 'Yes, I could hear it';

  /// Lower audibility No (not spoken).
  static const ctaHardToHear = 'No, it was hard to hear';

  /// Middle / upper comfort Yes (not spoken).
  static const ctaComfortable = 'Comfortable';

  /// Middle / upper comfort No (not spoken).
  static const ctaNotComfortable = 'Not comfortable';
}
