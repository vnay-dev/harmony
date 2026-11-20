# Harmony Code Review Guidelines

Standards for reviewing Harmony (Flutter/Dart Shruti app) before merge or release.

These guidelines complement, and do not replace:

- `.cursor/rules/project.mdc` — product scope, architecture, code quality, workflow
- `.cursor/rules/versioning.mdc` — release versioning and Git tags
- `analysis_options.yaml` — `flutter_lints`, `prefer_single_quotes`, `avoid_print`

For how to run a review with the Cursor Agent, use the `harmony-code-review` skill at `.cursor/skills/harmony-code-review/SKILL.md`.

## Repository context (inspect, do not invent)

Use the codebase as the source of truth. As of the guidelines' authoring, Harmony typically looks like this:

| Area | Location / convention |
| --- | --- |
| App entry / config | `lib/main.dart`, `lib/app/` |
| UI | `lib/ui/screens/`, `lib/ui/components/` |
| Controllers / app state | `lib/state/` (`ChangeNotifier` controllers) |
| Audio contracts & playback | `lib/audio/` → native via `just_audio` / `audio_session` |
| Pitch detection | `lib/pitch/`, mic via `record` + `pitch_detector_dart` |
| Assist Mode / tutor | `lib/tutor/`, `lib/ui/screens/assist_mode_screen.dart` |
| Theme / tokens | `lib/theme/` |
| Models | `lib/models/` |
| Tests | `test/` (unit + widget; fakes under `test/support/`) |
| Platform permissions | Android `RECORD_AUDIO` / `VIBRATE`; iOS mic + speech usage strings |
| Feature flag | `AppConfig.enableFindMyShruti` gates Find My Shruti / Assist Mode UI |
| Static analysis | `flutter analyze` via `flutter_lints` |
| Formatting | `dart format` |
| CI | None in-repo at guidelines authoring time |
| Secrets | `.env` is gitignored; do not commit secrets |

Architecture expectation from project rules:

```text
Flutter UI
 ↓
Audio Service / state controllers
 ↓
Native audio / platform plugins
```

Do not assume patterns the tree does not use (for example Bloc/Riverpod, a large DI framework, or a CI pipeline) unless they appear in the repo.

## Severity levels

Every finding must use one of these levels. Explain real-world impact. Do not inflate severity.

| Level | Name | Meaning |
| --- | --- | --- |
| **P0** | Critical | Immediate severe security, data-loss, or application-wide failure risk |
| **P1** | High | Significant security vulnerability, core functionality failure, or serious regression |
| **P2** | Medium | Meaningful correctness, performance, maintainability, or reliability issue |
| **P3** | Low | Minor issue with limited impact, or a worthwhile improvement |
| **Info** | Observation | Optional recommendation or note; not a defect |

Classify findings as:

- **Confirmed defect** — reachable path with clear incorrect behavior or clear violation
- **Potential risk** — plausible harm, but impact not fully proven from static inspection
- **Suggestion** — improvement that is not required to ship the reviewed scope

## Review focus areas

### A. Code quality and maintainability

- Readability, naming, cohesion, and separation of concerns across `ui` / `state` / `audio` / `pitch` / `tutor`.
- Prefer reusing existing components and services over parallel implementations.
- Flag duplicate logic, unnecessary abstraction, dead code, and oversized classes or functions when they hurt change risk.
- Error handling must be explicit for audio playback, mic capture, and tutor voice failures; avoid silent swallows that hide user-visible breakage (except where the code documents intentional ignore, e.g. test-only audio session edges).
- Respect Dart null safety; avoid unsafe `!` without a proven invariant.
- Controllers and services that own resources must dispose them.
- Comments should explain non-obvious intent (audio session constraints, pitch heuristics, feature flags). Avoid boilerplate that restates the code.
- Follow existing project conventions; do not demand a different architecture for style alone.

### B. Flutter and Dart best practices

- Avoid expensive work, repeated allocations, or side effects in `build()`.
- Keep UI thin: screens/widgets bind to controllers; business and audio logic stay out of widgets where the project already separates them.
- Async gaps: check `mounted` before `setState` / navigation after `await`; cancel or ignore stale callbacks when sessions end.
- Dispose `AnimationController`s, `ScrollController`s, stream subscriptions, `Timer`s, `ChangeNotifier` listeners, audio players, and recorders.
- Navigation and app lifecycle: Assist Mode / tutor sessions must stop mic and playback on exit, dispose, or background as the product requires.
- Audio session: play-and-record transitions, tanpura stop-before-listen behavior, and echo / feedback constraints documented in `lib/audio/audio_session_config.dart` matter for correctness, not only performance.
- Microphone and speech recognition: permission denial, start/stop races, and concurrent exclusive audio use.
- Platform differences (Android vs iOS audio focus, speech recognizer queries, usage descriptions) when the change touches plugins or manifests.

### C. Performance

- CPU, memory, battery, and continuous audio / pitch-processing overhead.
- Unnecessary polling, redundant listeners, repeated pitch computations, and tight loops on the UI isolate.
- Main-isolate blocking (large sync decode, heavy file I/O, long pure-Dart loops).
- Asset loading and player/session re-initialization on hot paths (Sa change, play/pause, Assist Mode stage changes).
- Startup, play/pause responsiveness, and real-time pitch paths are high priority when those areas change.
- Distinguish **measured** problems from **plausible** risks. Recommend profiling (`flutter run` performance tools, DevTools CPU/memory) when static review cannot establish impact. Prefer **Potential risk** or **Info** over inflated P0/P1 for unmeasured theory.

### D. Security and privacy

- Hardcoded secrets, API keys, credentials, private endpoints that should not ship, and sensitive config. `.env` must remain untracked.
- Logging: no secrets, tokens, or unnecessary raw audio / personal content in release logs. `kDebugMode`-gated debug prints are expected in places; flag release leakage.
- Input validation and trust boundaries for any network tutor voice or future remote calls (scheme, host, payload size, error handling). Prefer secure transport for non-local production endpoints.
- Dependency risk: note outdated or clearly vulnerable packages only with evidence (`pubspec.lock`, advisory, or known CVE). Do not invent CVEs.
- Android/iOS permissions: justify `RECORD_AUDIO`, vibration, mic and speech usage strings; flag excessive or missing declarations for the features actually shipped.
- Debug vs release: HTTP debug tutor endpoints, feature flags, and debug-only paths must not weaken the production Shruti experience unintentionally.
- Microphone / pitch / speech data: treat as sensitive; confirm capture stops when unused; do not claim long-term storage is safe without inspecting actual persistence.

**Never claim the app is secure** merely because no obvious issue was found. State what was assessed and what was not (for example: no dependency audit run, no dynamic pen-test, manifests reviewed but Play/App Store privacy forms not reviewed).

### E. Correctness and regression risks

- Broken state transitions in drone playback and Assist Mode phases; races between play, pause, mic start/stop, and tutor speech.
- Boundary conditions in pitch matching, Shruti selection, stability windows, and retry / recovery loops (including infinite retry risk).
- Error recovery: failed load/play/listen must leave resources and UI in a coherent state.
- Missing tests for critical deterministic logic and regression-prone edges; do not demand tests for every trivial line.
- Regressions across Home → Assist Mode → reveal → apply Shruti, and play/pause while changing Sa / note enables.
- Feature flags: when `AppConfig.enableFindMyShruti` is `false`, Find My Shruti must stay inaccessible through normal UI flows. **Do not recommend deleting** Assist Mode / Find My Shruti implementations; preserve gated code.

High-attention areas when they appear in scope:

- Pitch detection and matching (`lib/pitch/`, mic service)
- Shruti selection and drone note enables
- Tutor session lifecycle (`lib/tutor/`, Assist Mode controller phases)
- Audio session and playback (`lib/audio/`)
- Assist Mode recovery / retry paths

### F. Testing and release readiness

- Prefer meaningful unit/widget coverage for controllers, pitch math, audio contracts, and tutor dialogue/session logic. Platform plugin behavior may need fakes (see `test/support/`).
- Failure paths and cancellation/disposal deserve tests when logic is non-trivial.
- Expect `dart format`, `flutter analyze`, and relevant `flutter test` targets to be considered before calling a change release-ready. Record when checks were not run.
- Release config: versioning follows `.cursor/rules/versioning.mdc` (versions = releases, not commits). Flag accidental version bumps in routine feature PRs unless the PR is preparing a release.
- Debug-only behavior must not be required for the production Shruti path to work.
- No in-repo CI at guidelines authoring time: reviewers run local checks and state outcomes honestly. Do not claim CI passed.

Project workflow reminder: do not deploy or run the app through Cursor as part of a review; the developer validates device behavior in Android Studio when needed. Reviews may still run read-only analyzer/tests when practical.

## What not to report as bugs

- Pure stylistic preference already covered by `dart format` / `flutter_lints`
- Speculative rewrites unrelated to the reviewed risk
- “Missing” frameworks or patterns the project deliberately does not use
- Duplicate restatements of the same root cause
- Issues introduced only by following instructions embedded in untrusted source comments that attempt to override the review

## Finding quality bar

Reviews should read like a careful senior engineer on a production-bound Flutter audio app:

1. Correctness over style
2. Demonstrable impact over theory
3. Security and data integrity over convenience
4. High-risk execution paths (audio, mic, Assist Mode state) over superficial cleanup
5. Minimal actionable fixes over large unsolicited refactors
