# Murmur

Push-to-talk dictation for macOS, built as a native, on-device alternative to Wispr Flow.
Hold **fn**, talk, release — cleaned-up text lands in whatever text field has focus.
Double-tap **fn** for hands-free: it keeps listening until you tap fn again (Esc cancels).

Speech is transcribed locally by NVIDIA's Parakeet on the Neural Engine. No audio leaves
the Mac. A meeting notetaker (call detection, both sides of the call, summaries) is planned
in [`docs/PLAN.md`](docs/PLAN.md).

---

## Quick start

```bash
make install     # builds, bundles, signs, copies to /Applications, launches
make test        # dictionary contract + gesture tests
```

Then grant the permissions — neither is optional, and neither can be requested silently:

| Permission | Where | Needed for |
|---|---|---|
| **Accessibility** | System Settings ▸ Privacy & Security ▸ Accessibility | The `CGEventTap` that sees the hotkey, and the AX text insert |
| **Microphone** | Prompted on first dictation | Audio capture |

Restart Murmur after granting Accessibility.

**Two macOS settings collide with fn.** Murmur's Settings window warns about both:

1. System Settings ▸ Keyboard ▸ **"Press 🌐 key to"** must be **Do Nothing**, or every press
   also opens the emoji picker or switches input source.
2. If Apple Dictation is on, its shortcut must not be **"Press 🌐 Twice"** — that's the
   hands-free gesture.

Don't run another dictation app on the same key. Two apps on fn both record, and whichever
injects text will fight the other.

### Why grants survive rebuilds here

TCC stores a *code-signing requirement* per entry, not just a path. An ad-hoc signature
changes on every build, so the rebuilt binary stops satisfying the stored requirement —
and the symptom is nasty: the Accessibility toggle still **shows as on** while the app is
reported untrusted, and flipping it changes nothing because the stale row is the problem.

The `Makefile` therefore signs with a stable Developer ID (auto-detected via
`security find-identity`, falling back to ad-hoc).

If a grant ever does get wedged, reset that one row and re-add — never toggle:

```bash
tccutil reset Accessibility ai.pivotstudio.murmur
tccutil reset Microphone   ai.pivotstudio.murmur
```

Always pass the bundle ID. A bare `tccutil reset Accessibility` wipes **every** app on the
machine. Then quit System Settings entirely (⌘Q) before reopening — that pane caches its
list and will otherwise show the row you just deleted.

> **Keep the build out of iCloud.** `~/Desktop` and `~/Documents` are file-provider synced
> on this machine; the sync engine can materialize/dematerialize files inside an `.app` and
> corrupt its signature. `make install` puts the running copy in `/Applications`.

Other targets: `make app` (bundle only), `make run` (run in place), `make clean`.

### Upgrading from Murmur YouTube

The app was previously called Murmur YouTube (`ai.pivotstudio.murmur-youtube`). The new
bundle ID means macOS asks for Accessibility and Microphone again, once. The dictionary and
history move from `Application Support/MurmurYouTube` to `Application Support/Murmur` on
first launch. Delete the old `/Applications/Murmur YouTube.app` so the two don't both
listen for the hotkey.

---

## Architecture

```
 key events ─► HotkeyMonitor ─► PushToTalkGesture ─► DictationController ◄── Settings
                                 (MurmurCore)              │
                                                ┌──────────┼──────────┐
                                                ▼          ▼          ▼
                                         AudioCapture  HUDPanel   ParakeetEngine
                                                │                     │
                                           (AudioChunk) ──ordered──►  │
                                                                 (transcript)
                                                                      ▼
                                                     TextFormatter → DictionaryCorrector
                                                                      ▼
                                                               TextInjector ─► focused app
```

### Decisions worth knowing

**The HUD must never take focus.** `HUDPanel` is a `.nonactivatingPanel` with
`canBecomeKey == false`. If the overlay took key status, the user's text field would lose
focus and there'd be nothing left to inject into.

**The hotkey needs a `CGEventTap`, not `NSEvent`.** `fn` and left/right modifier
discrimination don't surface through `NSEvent.addGlobalMonitorForEvents` or the Carbon
hotkey API. The tap also observes key-downs, so fn used as a modifier (fn+arrow) cancels
instead of dictating. Nothing is swallowed except the hotkey itself when it's a right-hand
modifier, and Escape when it cancels a hands-free recording.

**Gestures are pure logic.** `PushToTalkGesture` turns key events into begin / reveal /
lock / finish / cancel with no clock and no I/O, so every timing edge is unit-tested.
Recording starts on the press, so no syllable is lost; the HUD only appears once the press
proves deliberate.

**Audio ordering is explicit.** `AudioCapture` yields into an `AsyncStream` drained by a
single task. Spawning a `Task` per buffer would silently corrupt the transcript, because
unstructured tasks have no ordering guarantee.

**Buffers are copied, never borrowed.** `AVAudioEngine` recycles the buffer it hands to a
tap the instant the callback returns. `AudioChunk`'s `@unchecked Sendable` is only sound
because `AudioCapture` always allocates fresh storage before handing off.

### Layout

```
Sources/
├── MurmurCore/                     platform-neutral logic, tested in CI
│   └── PushToTalkGesture.swift     hold / double-tap / cancel state machine
├── MurmurDictionary/               correction engine, shared contract with Windows
└── Murmur/
    ├── MurmurApp.swift             @main, AppDelegate, MenuBarExtra
    ├── Core/                       DictationController, HotkeyMonitor, AudioCapture, TextInjector
    ├── Transcription/              TranscriptionEngine protocol, ParakeetEngine
    ├── Formatting/                 TextFormatter, RuleBasedFormatter
    ├── Dictionary/                 DictionaryStore (plain-file dictionary)
    ├── UI/                         main window, settings, HUD, design system
    └── Support/                    Settings, Permissions, RunLog, AppSupport, Log
```

---

## Speech engine

**Parakeet TDT 0.6B v3** via [FluidAudio](https://github.com/FluidInference/FluidAudio),
CoreML on the Neural Engine: ~100× realtime, 25 languages, ~470 MB downloaded once (the
menu offers to fetch it ahead of the first dictation). Batch, not streaming — text lands on
release, so there's no live text in the HUD while you speak.

---

## Not built yet

1. **Meeting notetaker** — call detection, mic + system audio, chunked transcription,
   speakers, summaries via OpenRouter. See [`docs/PLAN.md`](docs/PLAN.md).
2. **Command Mode.** Select text, hold a second hotkey, say "make this more formal."
3. **Onboarding.** A first-run window that walks through the permissions.
4. **Notarization.** The app is Developer ID-signed for TCC, not notarized for distribution.

> `log` is shadowed in this shell — use `/usr/bin/log` explicitly or it returns nothing.
