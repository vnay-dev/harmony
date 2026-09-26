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

  /// After a confirmed user match: reference has stopped and settled.
  ///
  /// Not called when the capture path cannot separate the singer from the
  /// speaker. Ending the practice window is not confirmation.
  final Future<void> Function()? afterAssistedSinging;

  /// Practice ended with no confirmed user match. Do not claim the user is ready.
  final Future<void> Function()? afterAssistedPracticeUnconfirmed;
}
