# Tutor Dialogue Inventory

Source of truth: the current Tutor / Assist Mode implementation on this branch.

Spoken text is produced only by `TutorSession` passing strings into `TutorVoiceCoordinator`, which calls `TutorVoice.speak`. The running app uses `FlutterTutorVoice` (`flutter_tts`). There are no localization files.

The phrases "Get ready." and "Go." are not present in the current source. Solo countdown speech is "Let's try singing it again in 3...", "2...", and "1...", including the first starting-note attempt.

This inventory lists every unique string `TutorSession` can pass to the voice. **39 items are reachable in the current engine flow** (38 static + 1 finite-dynamic template). **3 additional strings exist in speech handlers the current engine does not invoke.** Those three are included below and marked unreachable so they are not mistaken for lines the running Tutor says today.

On-screen headlines, support text, buttons, and `AssistModeController.errorMessage` are not spoken. They are listed after the spoken inventory.

| ID | Exact Dialogue | Type | State/Stage | Trigger | User Response? | Audio/Timing Dependency |
|----|----------------|------|-------------|---------|----------------|--------------------------|
| T01 | Hi. I'll help you find a comfortable Shruti. | STATIC | Welcome | `TutorSession.begin` / restart after Stop | No | Speech must finish, then T02. Blocks session start. |
| T02 | You don't need to know anything about singing. | STATIC | Welcome | Immediately after T01 | No | After T01; before T03. Default 850 ms sentence pause. |
| T03 | Just follow my voice. | STATIC | Welcome | Immediately after T02 | No | After T02. Session does not start until this line and its pause finish. |
| T04 | Let's begin gently. | STATIC | Discover starting note | After welcome, before `startSession` | No | After T03. Before T05. |
| T05 | Sing or hum one comfortable sound. | STATIC | Discover starting note | After T04 | No | After T04. Before T06. Instruction only; mic is not open yet. |
| T06 | Keep that same sound going for a few seconds. | STATIC | Discover starting note | After T05 | No | After T05. `startSession` runs only after this line finishes. |
| T07 | Let's try singing it again in 3... | STATIC | Solo countdown | Each solo countdown step value 3. Used for the first starting-note listen, later starting-note retries, Stage 1 guided-demo retries, and every non-assisted range listen. | No — user is expected to sing after 1, not answer | Spoken in parallel with a 1 second visual "3". Next step waits for both speech and the timer. `pauseAfter` is zero. |
| T08 | 2... | STATIC | Solo countdown and assisted countdown | Countdown step value 2 | No | Same sync as T07, for digit 2. Shared by both countdown scripts. |
| T09 | 1... | STATIC | Solo countdown and assisted countdown | Countdown step value 1 | No | Same sync as T07, for digit 1. Listening starts only after this step's speech and 1 second timer both finish. |
| T10 | Let's sing together in 3... | STATIC | Assisted countdown | Assisted sing-along countdown step value 3 | No — user is expected to sing along after the countdown, while the reference plays | Same countdown sync as T07. Reference audio starts only after 3, 2, and 1 have finished. |
| T11 | That's okay. Let's try once more. | STATIC | Starting-note failure (1st miss) and range-point retry (1st miss on that point) | Stage 1 `retry` when `stage1FailureCount` is 1. Also Stage 2 `beforeReference` when `rangePointFailureCount` is 1. | No | Stage 1: speech finishes, then auto-retry (countdown, or guided demo once failures reach 2). Range: speech finishes, then reference audio. No "Listen first." on this range retry. |
| T12 | Sing or hum one steady, comfortable sound. | STATIC | Starting-note failure (1st miss) | Second line of the Stage 1 one-miss script, after T11 | No | After T11, before T13. Then auto-retry. |
| T13 | I'll let you know when to begin. | STATIC | Starting-note failure (1st miss) | Third line of the Stage 1 one-miss script | No | After T12. Completion is required before `retryRound`. The next cue to begin is the countdown, not this sentence. |
| T14 | No problem. I'll help you this time. | STATIC | Starting-note failure (2nd miss) | Stage 1 `retry` when `stage1FailureCount` is 2 (`guided`) | No | Before T15. Then auto-retry plays a guided reference demo. |
| T15 | Listen first. | STATIC | Starting-note guided demo, and first attempt of each range point | Stage 1: second line of the 2nd-miss script, and again immediately before the demo tone. Range: after the point intro, only when `rangePointFailureCount` is 0. | No | Must finish before reference audio. Extra pause after this line is 650 ms (`speechToReferencePause`). Reference is blocked while this is speaking. |
| T16 | Let's make this easier. | STATIC | Starting-note failure (3rd miss and later) | Stage 1 `retry` when `stage1FailureCount` is 3 or more (`humAlong`) | No | Before T17. The same two-line script is also attached to range `humAlong`, which the current engine does not enter (see Unreachable speech). |
| T17 | Listen once more. | STATIC | Starting-note failure (3rd miss and later) | Second line of the Stage 1 `humAlong` script, after T16 | No | After T16, before auto-retry. A guided demo then plays T15 and a reference tone. Also the second line of the unreachable range `guided` script (U03). |
| T18 | Let's try a slightly lower sound. | STATIC | Lower reference, first candidate | Range `beforeReference`, point `lowerSa`, search mode `initial`, failure count 0 | No | Before T15, then reference audio of Lower Sa. |
| T19 | Nice. Let's try one in the middle. | STATIC | Middle reference (Pa) | Range `beforeReference`, point `pa`, failure count 0. Also used when a later Shruti is tested. | No | Before T15, then Pa reference audio. |
| T20 | One more. A slightly higher sound. | STATIC | Upper reference | Range `beforeReference`, point `upperSa`, failure count 0 | No | Before T15, then Upper Sa reference audio. |
| T21 | Let's try one a little higher. | STATIC | Next Shruti, upward | Range `beforeReference`, point `lowerSa`, failure count 0, search mode `climbing`, `seekingHigher`, or `initial` when the lower-intro branch is not taken. In the current engine, a non-initial lower point uses this line for `climbing` and `seekingHigher`. | No | Before T15, then the new candidate's Lower Sa reference. |
| T22 | Let's try one a little lower. | STATIC | Next Shruti, downward | Range `beforeReference`, point `lowerSa`, failure count 0, search mode `seekingLower` | No | Before T15, then the new candidate's Lower Sa reference. |
| T23 | Now try that sound. | STATIC | After any reference tone that uses `afterReference` | After Stage 1 guided demo and after every non-assisted range reference, once the tone has stopped and settled | No | Reference has already stopped. 650 ms pause, then this line, then a 500 ms pause, then the solo countdown. Mic opens after the countdown, not after this line. |
| T24 | Beautiful. You can stop there. | STATIC | After a listen window that captured a note or range match | `afterListenWindow` when `captured` is true. Silence does not speak this line. | No | Spoken after the listen window ends. The engine waits for this hook before continuing. Not a claim that the final Shruti is found. |
| T25 | Now I'll find a comfortable range for you. | STATIC | Starting note captured | Engine phase `startingPointFound` | No | Spoken from the tutor listener while the engine's own 2 second transition timers run. The engine does not await this line. The next spoken lines are the first range intro (T18) and T15. |
| T26 | Could you hear that sound clearly? | STATIC | Lower audibility question | Phase `awaitingLowerAudibility`, after Lower Sa was matched. Skipped on later climbs when a previous Lower Sa was already audible. | Yes — yes or no. Spoken answers are parsed; buttons are "Yes" and "No". | Question is spoken before speech recognition starts. Recognition timeout is 5 seconds. Reference audio is not playing. |
| T27 | How did that feel? | STATIC | Upper comfort question | Phase `awaitingUpperComfort`, after Upper Sa was matched | Yes — comfortable or not comfortable. Buttons are "Comfortable" and "Not comfortable". | Same recognition timing as T26. |
| T28 | Good. | STATIC | Answer acknowledgment | User answers yes to T26, or comfortable to T27 | No | Spoken before the engine advances. Event ids `lower-yes-ack` and `upper-yes-ack` are not per-round, so a later answer in the same session does not speak "Good." again. |
| T29 | That's okay. Let's try a little higher. | STATIC | Lower audibility, answer no | User says or taps no for T26 | No | Spoken before seeking the next higher Shruti. Same once-per-session event id `lower-no-ack`. |
| T30 | That's okay. | STATIC | Upper comfort, answer not comfortable | User says or taps not comfortable for T27 | No | Spoken before the strained-upper branch (boundary, unresolved, or seek lower). Once-per-session event id `upper-no-ack`. |
| T31 | Sorry, I didn't quite catch that. | STATIC | Unclear yes/no or unclear comfort | Speech recognition returned text that parsed as unclear | Yes — the same answer as the open question | Before T32 or T33. One automatic re-listen when the unclear count is 1. Later unclear answers are spoken again, without another automatic re-listen. |
| T32 | Just say yes or no. | STATIC | Unclear yes/no | After T31 while the lower-audibility question is open | Yes — yes or no | After T31. Re-listen follows only on the first unclear answer. |
| T33 | Just say comfortable or not comfortable. | STATIC | Unclear comfort | After T31 while the upper-comfort question is open | Yes — comfortable or not comfortable | After T31. Re-listen follows only on the first unclear answer. |
| T34 | That's okay. Let's practice it together so you can get familiar with the sound. | STATIC | Assisted singing, explanation | Range point has 2 solo misses and fewer than 2 assisted attempts. Spoken at the start of each assisted pass. | No | Before T35. Reference is not playing yet. |
| T35 | Listen carefully, and sing along with me. | STATIC | Assisted singing, instruction | Immediately after T34, before the assisted countdown | No | Must finish before the countdown. Extra pause is 650 ms. The reference starts only after T10, T08, and T09. This is the only line that tells the user the reference will stay on while they sing. |
| T36 | That's okay. Let's practice that sound together once more. | STATIC | Assisted singing, unconfirmed | Assisted practice ended without a confirmed match, and assisted attempts used on this point are still below 2 | No | Spoken after the assisted reference stops. The current engine never confirms a match, so the first assisted pass always reaches this line. The second pass does not speak it; the session goes to T38 and T39. |
| T37 | Wonderful. We found a comfortable Shruti for you. Your Shruti is {label}. | FINITE_DYNAMIC | Completion | Engine phase `completed`. `{label}` is `Pitch.label`. | No | Spoken from the tutor listener while the engine starts tanpura playback of the chosen Shruti. That playback does not take the reference-audio speech lock, so this line and the tanpura can overlap. See Finite Dynamic Dialogue. |
| T38 | We couldn't find a comfortable Shruti just yet. | STATIC | Unresolved | Phase `rangeUnresolved`: assisted attempts exhausted, or search hit a bound with no comfortable Shruti | No | Before T39. Not spoken on Stop. |
| T39 | We can try again whenever you like. | STATIC | Unresolved | Immediately after T38 | No | After T38. Try Again restarts the search without replaying the welcome. |
| U01 | Beautiful. You're ready. | STATIC | Post-assisted verification | `TutorSession._onAfterAssistedSinging` | No | Would play after a confirmed assisted match, then U02. **The current engine never calls `afterAssistedSinging`.** Assisted practice always returns unconfirmed. |
| U02 | Now try that sound on your own. | STATIC | Post-assisted verification | Same handler as U01, after U01 | No | Would be followed by a solo countdown and microphone listen. **Not invoked by the current engine.** |
| U03 | Let me help you. | STATIC | Range guided retry | First line of `TutorScripts.letMeHelp`, from `_speakStruggleLeadIn` when range `teachingLevel` is `guided` (`rangePointFailureCount` >= 2) and `beforeReference` runs | No | Would be followed by T17, a pause, then reference audio. **The current engine switches to assisted singing at 2 misses and does not call `beforeReference` on that path, so this line is not spoken.** |

`TutorScripts.letMeHelp` is `["Let me help you.", "Listen once more."]`. Only the first of those is unique to the unreachable path. "Listen once more." is already T17.

---

# Finite Dynamic Dialogue

## T37 — Shruti result

- Dialogue/template: `Wonderful. We found a comfortable Shruti for you. Your Shruti is $shrutiLabel.`
- Exact currently spoken form: `Wonderful. We found a comfortable Shruti for you. Your Shruti is {Pitch.label}.`
- Dynamic variable: `shrutiLabel`, supplied only as `_engine.referencePitch.label`
- Possible values: `C`, `C#`, `D`, `D#`, `E`, `F`, `F#`, `G`, `G#`, `A`, `A#`, `B`
- Number of audio files required: 12
- Current selection logic: `TutorScripts.completion` interpolates the label. The only call site is `TutorSession._processEnginePhase` when the phase is `AssistUiPhase.completed`. `Pitch` is a 12-value enum; each value's `label` is the string above. The source text contains `#`, not the word "sharp". How device TTS pronounces `#` is not defined in this codebase.
- Relevant source: `lib/tutor/tutor_scripts.dart` `TutorScripts.completion`; `lib/tutor/tutor_session.dart` `TutorSession._processEnginePhase`; `lib/models/pitch.dart` `Pitch.label`
- Example outputs:
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is C.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is C#.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is D.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is D#.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is E.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is F.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is F#.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is G.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is G#.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is A.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is A#.
  - Wonderful. We found a comfortable Shruti for you. Your Shruti is B.

No other Tutor line interpolates, concatenates, or maps an enum to spoken text.

`_exploreDirectionLine` selects between two fixed strings (T21 and T22). It does not build a new sentence.

Countdown selection chooses between two fixed lists (`TutorScripts.countdown` and `TutorScripts.assistedCountdown`) from `AssistCountdownKind`. The shared steps are the fixed strings T08 and T09.

---

# Truly Dynamic Dialogue

No truly dynamic Tutor dialogue found.

---

# Duplicate Dialogue

## Exact duplicates

| Exact text | IDs | Where it is spoken |
|------------|-----|--------------------|
| That's okay. Let's try once more. | T11 | `TutorScripts.startingNoteRetryOnce` (Stage 1, one miss) and `TutorScripts.rangeRetryOnce` (range point, one miss). Same characters, two constants. |
| Listen first. | T15 | `TutorScripts.listenFirst`, and the second line of `TutorScripts.startingNoteGuided`. |
| Listen once more. | T17 | Second line of `TutorScripts.makeEasier` (spoken on Stage 1, third miss and later). Also the second line of `TutorScripts.letMeHelp` (unreachable range `guided` path). |
| Sorry, I didn't quite catch that. | T31 | First line of both `TutorScripts.unclearYesNo` and `TutorScripts.unclearComfort`. |
| Good. | T28 | Lower "yes" acknowledgment and upper "comfortable" acknowledgment. Both use `TutorScripts.softAffirmation`. |
| 2... | T08 | Second step of both `TutorScripts.countdown` and `TutorScripts.assistedCountdown`. |
| 1... | T09 | Third step of both countdown lists. |

## Same meaning, different wording

These are separate lines. Do not merge them.

| Lines | Relationship |
|-------|----------------|
| T11 "That's okay. Let's try once more." | Spoken. |
| Controller text "That's okay. Let's try that once more." | Not spoken. See non-spoken section. Adds the word "that". |
| T16 "Let's make this easier." plus T17 "Listen once more." | Spoken on the third starting-note miss. |
| T14 "No problem. I'll help you this time." plus T15 "Listen first." | Spoken on the second starting-note miss. Different help wording. |
| U03 "Let me help you." plus T17 "Listen once more." | Different from T14/T15. Present in code, not reached by the current engine. |
| T34 "That's okay. Let's practice it together so you can get familiar with the sound." | First assisted pass. |
| T36 "That's okay. Let's practice that sound together once more." | Later assisted pass. Similar reassurance, different sentence. |
| T29 "That's okay. Let's try a little higher." | Spoken after a "no" to the lower-audibility question. |
| T30 "That's okay." | Spoken after "not comfortable". Shorter, and does not name the next direction. |
| T21 "Let's try one a little higher." | Exploration intro. |
| T18 "Let's try a slightly lower sound." / T22 "Let's try one a little lower." | Different lower-direction wording. "Slightly lower sound" versus "a little lower". |
| T05 "Sing or hum one comfortable sound." | First discovery instruction. |
| T12 "Sing or hum one steady, comfortable sound." | Retry instruction. Adds "steady,". |

## Defined in `TutorScripts` but never passed to the voice

| Constant | Exact text | What happens instead |
|----------|------------|----------------------|
| `listenOnceMore` | That's okay. Listen once more. | Never spoken. The spoken retry line is T17, "Listen once more.", without "That's okay." |
| `letMeHelpYou` | Let me help you. | The constant is never passed to the voice. The same characters appear as the first element of `letMeHelp` (U03), which the current engine does not reach. |
| `sessionStopped` | Session stopped | Shown as the Stop headline. Not spoken. |
| `sessionStoppedSupport` | You can try again whenever you're ready. | Shown as the Stop support line. Not spoken. |

`TutorTimingConfig.afterSpeechBeforeListenPause` (500 ms) is defined and unused. Nothing reads it.

---

# Current TTS Architecture

## TTS service / class

- `TutorVoice` (`lib/tutor/tutor_voice.dart`) — `speak`, `stop`, `dispose`.
- `FlutterTutorVoice` (`lib/tutor/flutter_tutor_voice.dart`) — the only real speaker. Uses `package:flutter_tts` `FlutterTts`.
- `SilentTutorVoice` — no-op implementation. Tests and an optional screen injection use it. It does not speak.
- `TutorVoiceCoordinator` (`lib/tutor/tutor_voice_coordinator.dart`) — the only object `TutorSession` calls. It trims text, skips empty strings, records a spoken log, and calls `TutorVoice.speak`.

No other class calls `FlutterTts` or `speak`.

## Initialization

`AssistModeScreen` constructs `TutorSession` with `FlutterTutorVoice()` unless a test injects another `TutorVoice`.

`FlutterTutorVoice` does not configure TTS in its constructor. On the first non-empty `speak` it calls:

- `setSpeechRate(0.45)`
- `setPitch(1.0)`
- `awaitSpeakCompletion(true)`

Volume, voice, and locale are not set in this codebase.

## How text reaches TTS

1. `TutorScripts` holds the sentences.
2. `TutorSession` chooses a sentence or list from the script and the engine state.
3. `speakOnce` or `speakAll` on `TutorVoiceCoordinator` runs.
4. `speakAll` speaks each line in order. With an event-id prefix, each line goes through `speakOnce`.
5. `FlutterTutorVoice.speak` trims, stops any current utterance, then calls `_tts.speak`.

`speakOnce` remembers the event id for the session. A repeated id does not speak again until `resetEventKeys`. Welcome, discovery, questions, and acknowledgments use ids that suppress a second play in the same session. Countdown, retry, and reference lines include epoch, round, point, or failure count, so those can repeat.

`tryAgain` from completion or unresolved clears event ids and restarts the search. It does not replay the welcome. Stop, then Try Again, does replay the welcome.

## Speech completion

`awaitSpeakCompletion(true)` makes `FlutterTts.speak` complete when the utterance finishes.

The coordinator then waits, unless cancelled:

- default `sentencePause`: 850 ms
- `speechToReferencePause`: 650 ms, used before reference audio (T15, T35)
- `shortTransitionPause`: 500 ms, used after T23 and would be used after U02
- `Duration.zero` for countdown steps

## Speech stopping

- Each new `speak` calls `_tts.stop()` first.
- `TutorVoiceCoordinator.cancelSpeech` bumps an epoch, sets cancelled, and stops the voice. In-flight lines return without continuing the list.
- `TutorSession.stop` cancels speech, stops the recognizer, and does not speak a stop line.
- `beginReferenceAudio` stops in-progress speech and blocks new speech until `endReferenceAudio`.

## Asynchronous behavior

Tutor methods `await` coordinator calls, so lines inside one handler are sequential.

The engine `await`s these hooks before it continues:

- `beforeReference`
- `afterReference`
- `beforeCountdown` (no speech)
- `onCountdownStep` (in parallel with the 1 second visual step; both must finish)
- `beforeListen` (no speech)
- `afterListenWindow`
- `beforeAssistedSinging`
- `onAssistedReferenceWillStart` (no speech; locks out speech)
- `afterAssistedPracticeUnconfirmed`

These are not awaited by the engine. They run from the tutor's phase listener or from `begin`:

- Welcome and discovery: awaited inside `begin` before `startSession`.
- Starting-note failure speech: the engine has already stopped the round. The tutor speaks, then calls `retryRound`. Speech finishes before the retry.
- Starting-note success (T25), questions (T26, T27), unresolved (T38, T39), and completion (T37): the listener speaks while the engine continues its own timers or playback.
- Answer acknowledgments (T28, T29, T30) are awaited before `reportLowerSaAudible`, `reportLowerSaTooLow`, `reportUpperSaComfortable`, or `reportUpperSaStrained`.

## Tutor state dependencies

State changes that wait on speech are the hook list above, welcome-before-start, failure-speech-before-`retryRound`, and answer-acknowledgment-before-the engine report methods.

T25, T37, T38, and T39 do not gate the engine. Completion speech can overlap the final tanpura.

`afterAssistedSinging` would gate post-assisted lines U01 and U02, but `AssistModeController` never calls that hook. `_runAssistedSinging` always returns `AssistedSingResult.unconfirmed` because this build cannot separate the singer from the speaker.

## One speaker

Only one `TutorVoice` is attached. The coordinator's comment says one utterance at a time. Concurrent `speak` calls are not queued behind a lock. Overlap with musical audio is prevented only where the engine calls `beginReferenceAudio` / `endReferenceAudio`. Final Shruti tanpura playback does not.

Speech recognition (`SpeechToTextTutorRecognizer`) listens. It does not speak. It starts after the question handler has finished speaking. Partial results that already parse as a clear answer stop recognition early. Empty transcripts do not trigger the unclear script.

## TTS configuration currently set

| Setting | Value |
|---------|--------|
| Speech rate | 0.45 |
| Pitch | 1.0 |
| Await completion | true |
| Volume | not set |
| Voice | not set |
| Locale / language | not set |

---

# Tutor Flow Summary

Stop at any time cancels speech and shows on-screen text only. It does not speak.

## Welcome and first listen

`welcome`
→ T01, T02, T03
→ no user answer
→ no reference, no mic
→ `discoverStartingNote`

`discoverStartingNote`
→ T04, T05, T06
→ user will sing after the countdown
→ then `startSession`
→ solo countdown T07, T08, T09
→ microphone listen (no reference on the first attempt)
→ if a note is captured: T24, then T25, then lower-reference flow
→ if not: starting-note failure

There is no separate "get ready" or "go" line. The first listen uses the same solo countdown as a retry.

## Starting-note failure

Miss 1 (`stage1FailureCount` 1)
→ T11, T12, T13
→ auto `retryRound` if fewer than 5 auto-retries have run
→ countdown T07–T09
→ mic
→ no reference

Miss 2
→ T14, T15
→ auto-retry plays a short reference on G
→ T15 again, reference, T23, countdown T07–T09, mic

Miss 3 and later
→ T16, T17
→ same guided-demo path as miss 2 (T15, reference, T23, countdown, mic)

After 5 auto-retries the failure lines still play, and the screen waits for a Try Again tap. That tap retries without a new spoken line.

## Range check, first try at a point

Lower Sa of the first candidate
→ T18, T15
→ reference
→ T23
→ countdown T07–T09
→ mic
→ match: T24, then T26
→ miss: see range retry

Pa
→ T19, T15
→ reference, T23, countdown, mic
→ match: T24, then Upper Sa with no spoken question
→ miss: range retry

Upper Sa
→ T20, T15
→ reference, T23, countdown, mic
→ match: T24, then T27
→ miss: range retry

## Yes / No and comfort

T26
→ user says or taps yes or no
→ speech recognition, or buttons if recognition is unavailable or the answer stays empty
→ yes: T28 (first time only), then Pa
→ no: T29 (first time only), then a higher Shruti
→ unclear speech: T31, T32, then one re-listen

T27
→ user says or taps comfortable or not comfortable
→ comfortable: T28 (first time only). If the search was seeking a fit, completion. Otherwise climb to the next higher Shruti.
→ not comfortable: T30 (first time only). If a comfortable Shruti already exists, completion with that Shruti and no extra boundary sentence. Otherwise unresolved or a lower Shruti.
→ unclear speech: T31, T33, then one re-listen

Climbing after an audible Lower Sa skips T26. Pa and Upper Sa are still introduced with T19 and T20.

## Next Shruti

Before the new candidate's Lower Sa, failure count 0
→ T21 when moving up (`climbing` or `seekingHigher`)
→ T22 when moving down (`seekingLower`)
→ T15, reference, T23, countdown, mic

## Range miss and assisted singing

First miss on a point
→ T11
→ reference with no "Listen first."
→ T23, countdown, mic

Second miss
→ assisted path, not the `guided` / `humAlong` reference scripts
→ T34, T35
→ countdown T10, T08, T09
→ reference stays on while the user is invited to sing along
→ current engine does not confirm the singer
→ T36
→ second assisted pass: T34, T35, countdown, reference
→ then T38, T39

U01 and U02 are not in this flow.

The range scripts "Let me help you." (U03) and the range use of "Let's make this easier." are not entered, because two misses start assisted singing instead of `beforeReference`.

## Completion and unresolved

Completion
→ T37 with one of the 12 pitch labels
→ tanpura of that Shruti may already be starting
→ screen can show the label and Play My Shruti
→ Try Again restarts the search without welcome speech

Unresolved
→ T38, T39
→ Try Again restarts without welcome speech

---

# Timing-Critical Dialogue

| Item | What must happen before / after |
|------|----------------------------------|
| T01–T06 | Welcome and discovery finish before `startSession`. No reference and no mic during these lines. |
| T07, T08, T09 | One spoken step per countdown value. Speech runs in parallel with a 1 second visual digit. The next digit, or the microphone, waits until both the speech and the timer finish. No extra sentence pause. |
| T10 | Same countdown lock as T07. Assisted reference must not start until T10, T08, and T09 have finished. |
| T15 | Must finish, then 650 ms, before reference audio. The coordinator stops speech if reference is marked active. |
| T18, T19, T20, T21, T22 | Spoken while reference is still off, immediately before T15 on a first attempt. |
| T23 | Reference has stopped, plus 600 ms engine settling, plus 650 ms tutor pause. Then this line, plus 500 ms, then the solo countdown. The mic stays closed until the countdown ends. |
| T24 | After the listen window. The engine waits for the hook. Not spoken for silence. |
| T25 | Not synchronized to a completion callback. It can overlap the engine's transition delay before the first range reference. |
| T26, T27 | Speech recognition starts only after the question handler finishes, including the 850 ms sentence pause. |
| T28, T29, T30 | Must finish before the engine applies the answer and moves to the next point or Shruti. |
| T31–T33 | Spoken before the optional re-listen. They are not themselves recognized as the user's answer. |
| T34, T35 | Both finish before the assisted countdown. T35 has a 650 ms pause. Reference starts after the countdown, not after T35 directly. |
| T36 | After the assisted reference has stopped. Then a transition, then another assisted pass. Not spoken when the attempt limit is already reached. |
| T37 | Not waited on by the engine. Can overlap final tanpura playback. |
| U01, U02 | Would be ordered after confirmed assisted audio and before a solo retry. That callback is not used. |

Countdown values outside 1–3 are ignored. A countdown step value already emitted in that countdown does not speak twice.

---

# Potential Local Audio Asset Structure

Proposal only. These directories are not part of the app.

```text
assets/audio/tutor/
  welcome/
    t01_hi_help_find_shruti.wav
    t02_no_need_to_know_singing.wav
    t03_follow_my_voice.wav
  discovery/
    t04_begin_gently.wav
    t05_sing_or_hum_comfortable.wav
    t06_keep_same_sound.wav
  countdown/
    t07_try_singing_again_in_3.wav
    t08_2.wav
    t09_1.wav
    t10_sing_together_in_3.wav
  starting_note/
    t11_try_once_more.wav
    t12_steady_comfortable_sound.wav
    t13_let_you_know_when_to_begin.wav
    t14_help_you_this_time.wav
    t15_listen_first.wav
    t16_make_this_easier.wav
    t17_listen_once_more.wav
    t24_beautiful_stop_there.wav
    t25_find_comfortable_range.wav
  reference/
    t18_slightly_lower_sound.wav
    t19_one_in_the_middle.wav
    t20_slightly_higher_sound.wav
    t21_a_little_higher.wav
    t22_a_little_lower.wav
    t23_now_try_that_sound.wav
  questions/
    t26_hear_that_clearly.wav
    t27_how_did_that_feel.wav
    t28_good.wav
    t29_try_a_little_higher.wav
    t30_thats_okay.wav
    t31_didnt_catch_that.wav
    t32_say_yes_or_no.wav
    t33_say_comfortable_or_not.wav
  assisted/
    t34_practice_together.wav
    t35_sing_along_with_me.wav
    t36_practice_once_more.wav
    u01_youre_ready.wav
    u02_try_on_your_own.wav
    u03_let_me_help_you.wav
  completion/
    t37_your_shruti_c.wav
    t37_your_shruti_c_sharp.wav
    t37_your_shruti_d.wav
    t37_your_shruti_d_sharp.wav
    t37_your_shruti_e.wav
    t37_your_shruti_f.wav
    t37_your_shruti_f_sharp.wav
    t37_your_shruti_g.wav
    t37_your_shruti_g_sharp.wav
    t37_your_shruti_a.wav
    t37_your_shruti_a_sharp.wav
    t37_your_shruti_b.wav
  unresolved/
    t38_couldnt_find_shruti.wav
    t39_try_again_whenever.wav
```

U01–U03 are optional until those handlers are actually called. One file can cover each exact duplicate (T08, T09, T11, T15, T17, T28, T31).

Playback will need the current pauses and the countdown's parallel 1 second steps. Replacing TTS does not by itself preserve that timing.

---

# Local Audio Conversion Summary

1. Total unique spoken dialogue items in the running flow: **39** (T01–T39).
2. Total static audio files required for that flow: **38** (T01–T36 and T38–T39).
3. Total finite-dynamic variants required: **12** (T37, one file per pitch label).
4. Total truly dynamic messages: **0**.
5. Total estimated audio assets after expanding finite dynamic dialogue: **50** (38 static + 12 Shruti lines).
6. Dialogue generated outside the main Tutor / TTS path: **no**. Every spoken line goes through `TutorSession` → `TutorVoiceCoordinator` → `FlutterTutorVoice`. Three further static lines (U01, U02, U03) are implemented on tutor callbacks or branches the current engine does not enter. Adding them later would make 53 assets. `AssistModeController` also stores fallback strings that are not spoken and are not shown on the Assist screen.
7. Whether any dialogue appears to require runtime TTS: **no.** Every reachable sentence is static, or one of 12 known Shruti sentences. Nothing is built from free-form runtime text.
8. Files and classes most likely to change when TTS is replaced with local audio:
   - `lib/tutor/flutter_tutor_voice.dart` — `FlutterTutorVoice`
   - `lib/tutor/tutor_voice.dart` — `TutorVoice`
   - `lib/tutor/tutor_voice_coordinator.dart` — `TutorVoiceCoordinator` (completion, pauses, reference lock, `speakOnce`)
   - `lib/tutor/tutor_session.dart` — `TutorSession` (where each line is chosen and awaited)
   - `lib/tutor/tutor_scripts.dart` — `TutorScripts` (the sentence list and `completion`)
   - `lib/ui/screens/assist_mode_screen.dart` — `AssistModeScreen` (constructs `FlutterTutorVoice`)
   - `lib/tutor/tutor_timing.dart` — `TutorTimingConfig` (pauses that must remain if assets replace TTS)
   - `lib/state/assist_mode_controller.dart` — `AssistModeController` (awaits the speech hooks and runs countdown timing; not a second speaker)

## On-screen text that is not spoken

Headlines and support text in `TutorSession.headline` / `supportText`, rendered by `AssistModeScreen`:

- Find your comfortable Shruti
- I'll guide you. You just sing.
- Your turn
- Listen
- Sing one comfortable sound
- Keep the same sound going.
- Let's try once more
- Lovely — I heard that
- Could you hear that sound clearly? (same words as T26, displayed while the question is open; the spoken copy is T26)
- How did that feel? (same words as T27, displayed; the spoken copy is T27)
- Say yes or no — or tap below.
- Say comfortable or not comfortable — or tap below.
- We found it
- Your comfortable Shruti
- Let's try again
- Whenever you are ready.
- Session stopped
- You can try again whenever you're ready.
- Practice together
- Nice
- Follow my voice
- Listen once more, then try that sound.
- Now I'll find a comfortable range for you. (same words as T25, also displayed)

Buttons, not spoken: Yes, No, Comfortable, Not comfortable, Stop, Try Again, Play My Shruti. The app bar title "Find your Shruti" is not spoken.

`AssistModeController.errorMessage` is set and never passed to TTS. `AssistModeScreen` does not display it either.

| Stored text | When it is assigned |
|-------------|---------------------|
| Let's try that again in a moment. | Audio-session prepare fails in `startSession` or `tryAgain`. |
| That's okay. Let's try that once more. | Pitch-detection start failure, reference playback failure, assisted reference failure, or a detection-stream error. |
| That's okay — your Shruti is ready. | Final tanpura playback throws after the Shruti is already chosen. T37 can still be spoken. |

## Reachability notes that affect asset planning

- Stage 1 attempt 1 has no reference and still says "Let's try singing it again in 3...".
- `teachingLevel` `standard` inside `_onStartingNoteFailure` uses the same script as the one-miss path. The failure count is already at least 1 when that handler runs, so the `standard` branch does not add a different sentence.
- Assisted confirmation speech (U01, U02) is wired in `TutorSession` and unused by `AssistModeController`.
- Range `guided` speech (U03, then T17) and range `humAlong` speech (T16, T17 via `_speakStruggleLeadIn`) are unused while assisted singing replaces `beforeReference` at two misses.
