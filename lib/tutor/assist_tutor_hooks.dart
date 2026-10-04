/// Hooks the Assist search engine uses so the tutor can speak before/after
/// musical reference audio without overlapping.
///
/// Pitch/search logic stays in the engine; these callbacks are presentation
/// gates only.
class AssistTutorHooks {
  const AssistTutorHooks({
    this.beforeReference,
    this.afterReference,
    this.beforeCountdown,
    this.onCountdownStep,
    this.beforeListen,
    this.afterListenWindow,
    this.beforeAssistedSinging,
    this.onAssistedReferenceWillStart,
    this.afterAssistedSinging,
    this.afterAssistedPracticeUnconfirmed,
    this.beforeCompletionPlayback,
  });

  /// Speak intro lines before reference audio starts (engine has not played yet).
  final Future<void> Function()? beforeReference;

  /// After reference fully stops and settles, before countdown/listen speech.
  final Future<void> Function()? afterReference;

  /// Called once before the 3, 2, 1 countdown. Does not speak a separate cue.
  final Future<void> Function()? beforeCountdown;

  /// Called for each countdown value: 3, 2, 1. Awaited for sync.
  final Future<void> Function(int value)? onCountdownStep;

  /// After the last countdown step, before mic analysis.
  ///
  /// Listening starts immediately. This must not add another instruction.
  final Future<void> Function()? beforeListen;

  /// After the listen window ends.
  ///
  /// [captured] is true only when voiced input produced a real capture or
  /// target match. Silence must not be announced as success.
  final Future<void> Function(bool captured)? afterListenWindow;

  /// Explanation before the assisted countdown. Reference audio has not started.
  final Future<void> Function()? beforeAssistedSinging;

  /// Called once the countdown has finished and the reference is about to play.
  final Future<void> Function()? onAssistedReferenceWillStart;

  /// After assisted reference playback has stopped and settled.
  ///
  /// Speaks the solo handoff only. The practice window is not a match result.
  final Future<void> Function()? afterAssistedSinging;

  /// Practice ended with no confirmed user match. Do not claim the user is ready.
  final Future<void> Function()? afterAssistedPracticeUnconfirmed;

  /// Final success dialogue before the confirmed Shruti sample starts.
  ///
  /// The engine has stopped any prior sample/reference audio. The Shruti
  /// sample must not start until this Future completes.
  final Future<void> Function()? beforeCompletionPlayback;
}
