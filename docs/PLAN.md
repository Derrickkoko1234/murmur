# Plan: Murmur as a Wispr Flow alternative with a meeting notetaker

macOS only. The Windows app is out of scope, and nothing here changes the dictionary
vectors, so the two implementations stay in agreement.

## Decisions (settled 2026-10-25)

- **Rename everything.** The app becomes **Murmur**: display name `Murmur`, executable
  `Murmur`, bundle ID `ai.pivotstudio.murmur`. The URL scheme only served the deleted
  dashboard, so it goes too. The bundle-ID change
  resets the Accessibility and Microphone grants once. The dictionary and run history move
  from `~/Library/Application Support/MurmurYouTube` to `…/Murmur` on first launch, so
  nothing the user built up is lost. The old preferences domain held only window frames and
  obsolete keys, so it isn't migrated.
- **Delete the benchmarking tools.** Compare mode, `WisprTrigger`, `WisprReader`,
  `EngineComparison`, `ComparisonWindow`, the HTML dashboard and the Apple engine all go.
  Parakeet is the only engine.
- **Notes start automatically** when a call is detected, with a notification saying so and
  a Stop button. Recording other people may need their consent where you live; the
  notification is the reminder.

## What already exists

- fn is already a push-to-talk choice (`PushToTalkKey.fn`, keycode 63, read through the
  `CGEventTap`, never swallowed). Hold-fn-to-talk works today.
- The whole dictation path: capture → Parakeet → cleanup → dictionary → injection, with a
  HUD that never takes focus.

---

## Phase 1: fn hold and double-tap

A gesture recognizer in a new platform-neutral target, `MurmurCore`, fed key events with
timestamps. It holds no I/O, so CI can test it.

| What you do | What happens |
|---|---|
| Press fn | Recording starts at once, so the first syllable isn't lost. The HUD stays hidden for the first ~250 ms. |
| Release after the threshold | Push-to-talk: transcribe and type. |
| Quick tap, then a second press within ~350 ms | **Hands-free.** HUD shows a lock; recording continues after you let go. |
| One tap while hands-free | Stop, transcribe, type. |
| Esc while hands-free | Cancel and discard. |
| A single quick tap, no second tap | Cancel quietly — a stray press. |
| Any other key while fn is down (fn+arrow, fn+delete, fn+F-keys) | Cancel — a shortcut, not dictation. |

Changes:
- `HotkeyMonitor` also observes `keyDown` (never swallowed) and passes raw events to the
  recognizer.
- `DictationController` exposes begin / end / cancel / lock instead of press = begin,
  release = end.
- fn becomes the default push-to-talk key.
- Settings warns about the two macOS settings that collide with fn:
  1. "Press 🌐 key to" (`AppleFnUsageType` in `com.apple.HIToolbox`) must be **Do Nothing**,
     or every press also opens the emoji picker or switches input source.
  2. Apple Dictation's **"Press 🌐 twice"** shortcut is exactly the double-tap gesture.
- `macos.yml` runs the `MurmurCore` tests alongside `VectorTests`.

## Phase 2: meeting recorder (manual start/stop)

- **Two streams.** Mic → "Me" (a second `AudioCapture`, independent of dictation, so you
  can dictate during a call). System audio → "Them", via Core Audio process taps
  (`CATapDescription` + `AudioHardwareCreateProcessTap`), tapping only the meeting app's
  process. Needs "System Audio Recording" (`NSAudioCaptureUsageDescription`), not Screen
  Recording.
- **Audio to disk as it records**, one file per stream, so a crash doesn't lose the meeting.
- **Chunked transcription.** VAD splits speech into ≤30 s segments, each transcribed as it
  finishes, giving a live transcript with timestamps. Shares the one `ParakeetModels`
  instance, serialized, with dictation taking priority. Every segment goes through
  `DictionaryStore.shared.corrector`.
- **Storage:** `~/Library/Application Support/Murmur/Meetings/<id>/` holding `meta.json`,
  `transcript.json`, the audio files and a generated `notes.md`.
- **UI:** a Meetings section in `MainWindow` (list + transcript), a red recording lamp in the
  HUD and menu bar. New values go into `DesignSystem.swift` as tokens.

## Phase 3: call detection

- Core Audio's process list (`kAudioHardwarePropertyProcessObjectList`, with
  `kAudioProcessPropertyBundleID` and `kAudioProcessPropertyIsRunningInput`) says which app
  is using the mic, with change notifications. Murmur's own process is skipped.
- Known meeting apps (Zoom, Teams, Webex, Slack, FaceTime, Discord) count. Browsers count
  only when a window title looks like Meet / Teams / Zoom, read via Accessibility.
- Policy, in `MurmurCore` and tested with fake event sequences: mic in use ≥ ~5 s to start,
  released ≥ ~20 s to end.
- Notes start automatically, with a notification ("Taking notes — Zoom", Stop button), and
  stop when the call ends ("Notes ready").

## Phase 4: speakers and summaries

- FluidAudio's diarizer on the "Them" stream after the meeting → Speaker 1, 2, 3, renamable.
- Summary, decisions and action items via OpenRouter — text only, audio never leaves the Mac.
  API key in the Keychain, model chosen in Settings.
- Markdown export and copy buttons.

## Later, only if wanted

Calendar names and attendees; OpenRouter cleanup for dictation; echo cancellation for calls
on speakers (Phase 2 assumes headphones, otherwise "Them" appears twice); cross-meeting
search; asking questions about a meeting.

## Risks

- The process-tap and process-list code is low-level Core Audio, written without a library,
  and none of it can run in CI.
- FluidAudio's VAD and diarizer APIs must be checked against the pinned version.
- 8 GB of RAM: diarization runs after the meeting, not live.
