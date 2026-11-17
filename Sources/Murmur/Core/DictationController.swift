import MurmurDictionary
import MurmurCore
import AVFoundation
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case finishing
        case error(String)

        var isActive: Bool {
            switch self {
            case .starting, .listening, .finishing: true
            case .idle, .error: false
            }
        }
    }

    private(set) var state: State = .idle
    /// Live transcript, updated as the engine revises it. Drives the HUD.
    private(set) var transcript = ""
    /// Smoothed 0…1 mic level for the waveform.
    private(set) var level: Float = 0
    /// The HUD stays hidden until a press proves deliberate, so a stray tap of the key
    /// doesn't flash it.
    private(set) var isHUDRevealed = false
    /// Double-tapped: recording continues after the key is released.
    private(set) var isHandsFree = false

    private let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    private let makeEngine: @Sendable () -> any TranscriptionEngine

    /// Injected only by tests; production reads the setting per-utterance below.
    private let formatter: (any TextFormatter)?

    /// Chosen per-utterance so the menu toggle applies to the very next hold.
    private var activeFormatter: any TextFormatter {
        if let formatter { return formatter }
        return Settings.shared.smartCleanup
            ? FoundationModelFormatter()
            : RuleBasedFormatter()
    }

    private var engine: (any TranscriptionEngine)?
    private var consumeTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    /// Timestamps for the history: when the key went down, and when it came up.
    private var holdStarted: Date?
    private var releasedAt: Date?
    private var engineName = ""
    /// Bumped per recording, so a start-up task that outlived its recording can tell.
    private var generation = 0

    init(
        formatter: (any TextFormatter)? = nil,
        makeEngine: @escaping @Sendable () -> any TranscriptionEngine = { ParakeetEngine() }
    ) {
        self.formatter = formatter
        self.makeEngine = makeEngine
    }

    // MARK: - Lifecycle

    /// - Returns: `false` if the hotkey tap couldn't be installed (missing Accessibility).
    @discardableResult
    func activate() -> Bool {
        hotkey.key = Settings.shared.pushToTalkKey
        hotkey.onAction = { [weak self] action in self?.handle(action) }
        return hotkey.start()
    }

    func deactivate() {
        hotkey.stop()
        cancelDictation()
    }

    /// Re-arms the tap after the user picks a different push-to-talk key.
    @discardableResult
    func reloadHotkey() -> Bool {
        // Re-arming forgets the gesture driving any live recording, which would leave a
        // hands-free one with no key able to stop it.
        if state == .starting || state == .listening { cancelDictation() }
        hotkey.stop()
        return activate()
    }

    // MARK: - Gesture

    private func handle(_ action: PushToTalkGesture.Action) {
        switch action {
        case .begin:
            // Another recording is running (the Record button, or the previous utterance
            // still finishing). This press isn't driving it, so drop the gesture — otherwise
            // its later `.cancel` or `.finish` would act on a recording it never started.
            guard case .idle = state else {
                hotkey.resetGesture()
                return
            }
            beginDictation()
        case .reveal: reveal()
        case .lock:
            isHandsFree = true
            reveal()
        case .finish: endDictation()
        case .cancel:
            // Only a recording this gesture started. A `.finishing` one belongs to the
            // previous utterance and must still be typed.
            guard state == .starting || state == .listening else { return }
            cancelDictation()
        }
    }

    /// Shows the HUD and plays the start sound, once per recording.
    private func reveal() {
        guard state.isActive, !isHUDRevealed else { return }
        isHUDRevealed = true
        if Settings.shared.soundEnabled { NSSound(named: "Tink")?.play() }
    }

    /// Every route back to idle goes through here so the HUD flags can't outlive a recording.
    private func becomeIdle() {
        state = .idle
        transcript = ""
        isHUDRevealed = false
        isHandsFree = false
    }

    // MARK: - Button-driven recording

    /// Starts a recording from the window's Record button rather than the hotkey.
    func startButtonRecording() {
        guard case .idle = state else { return }
        hotkey.resetGesture()
        beginDictation()
        reveal()
    }

    /// Stops a button-started recording.
    func stopButtonRecording() {
        hotkey.resetGesture()
        endDictation()
    }

    // MARK: - Dictation

    private func beginDictation() {
        guard case .idle = state else { return }
        state = .starting
        transcript = ""
        holdStarted = Date()
        engineName = "Parakeet"
        generation += 1
        let current = generation

        // A cancel and a fresh press can both land while this task awaits — the first model
        // load takes ~20s. Its recording is then over, and touching shared state would
        // clobber the new one, so every resume checks `current` first.
        Task { @MainActor in
            do {
                guard await Permissions.requestMicrophone() else {
                    if self.generation == current {
                        fail("Microphone access is off. Enable it in System Settings ▸ Privacy & Security ▸ Microphone.")
                    }
                    return
                }
                guard self.generation == current else { return }

                let engine = makeEngine()
                self.engine = engine

                let chunks = try await engine.start()

                guard let format = await engine.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }
                // Cancelled, released or superseded while the model loaded: nothing to record,
                // and the mic must not open.
                guard self.generation == current, case .starting = self.state else {
                    await engine.finish()
                    return
                }

                // Audio must reach the engine in capture order. A stream plus a single
                // draining task guarantees that; spawning a Task per buffer would not.
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                self.audioContinuation = audioContinuation

                self.feedTask = Task.detached(priority: .userInitiated) {
                    for await chunk in audioStream {
                        await engine.feed(chunk)
                    }
                }

                try capture.start(
                    outputFormat: format,
                    onBuffer: { chunk in
                        audioContinuation.yield(chunk)
                    },
                    // Strong on purpose: the enclosing task already holds `self`, and
                    // `capture.stop()` drops this closure when the recording ends.
                    onLevel: { level in
                        Task { @MainActor in self.updateLevel(level) }
                    }
                )

                self.state = .listening

                self.consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            self.transcript = chunk.text
                        }
                    } catch {
                        if self.generation == current { self.fail(error.localizedDescription) }
                    }
                }
            } catch {
                if self.generation == current { self.fail(error.localizedDescription) }
            }
        }
    }

    private func endDictation() {
        // `.finishing` is "active", so without this a second press during processing would
        // run the whole tail again — re-reading `transcript` before the first pass cleared
        // it and pasting the same utterance twice. The window is wide: Parakeet transcribes
        // inside `finish()`, and smart cleanup adds up to 4s on top.
        guard state.isActive, state != .finishing else { return }
        // Released while the model was still loading: the start-up task has nothing left to
        // record, so it mustn't report a late failure over whatever comes next.
        if state == .starting { generation += 1 }
        state = .finishing
        // A hold released just before the reveal tick fired still gets its "Transcribing…".
        isHUDRevealed = true
        isHandsFree = false
        capture.stop()
        level = 0
        releasedAt = Date()

        Task { @MainActor in
            // Drain every captured buffer into the engine before asking it to finalize,
            // or the tail of the utterance gets dropped.
            audioContinuation?.finish()
            audioContinuation = nil
            await feedTask?.value
            feedTask = nil

            await engine?.finish()
            await consumeTask?.value
            // Transcription failed: `fail()` has already reported it and will clear itself.
            // Carrying on would find an empty transcript and wipe the error straight away.
            guard state == .finishing else { return }
            consumeTask = nil
            engine = nil

            let raw = transcript
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                becomeIdle()
                return
            }

            let cleaned = Settings.shared.cleanupEnabled
                ? await activeFormatter.format(raw)
                : raw

            // The dictionary runs last, and runs regardless of the cleanup setting. Biasing
            // only raises the odds of the right word; this is the pass that guarantees it,
            // so it must not be something the user can accidentally switch off.
            let (output, corrections) = DictionaryStore.shared.corrector.apply(to: cleaned)
            if !corrections.isEmpty {
                Log.speech.info("dictionary · \(corrections.count, privacy: .public) correction(s) applied")
            }

            recordRun(text: output, corrections: corrections)
            TextInjector.insert(output)
            if Settings.shared.soundEnabled { NSSound(named: "Pop")?.play() }

            becomeIdle()
        }
    }

    private func cancelDictation() {
        // Invalidates a start-up task still awaiting the model, so it neither opens the mic
        // nor reports an error for a recording the user already discarded.
        generation += 1
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil

        let engine = self.engine
        self.engine = nil
        Task { await engine?.finish() }

        becomeIdle()
        level = 0
    }

    // MARK: - Helpers

    /// Files the finished utterance in the history.
    ///
    /// `processSeconds` is measured from key release, not from capture start — that's the
    /// wait the user actually experiences, and it's the only number on which a streaming
    /// engine and a batch engine can be compared honestly.
    private func recordRun(text: String, corrections: [AppliedCorrection] = []) {
        guard let holdStarted, let releasedAt else { return }
        RunLog.record(
            DictationRun(
                date: releasedAt,
                engine: engineName,
                audioSeconds: releasedAt.timeIntervalSince(holdStarted),
                processSeconds: Date().timeIntervalSince(releasedAt),
                text: text,
                corrections: corrections.isEmpty ? nil : corrections
            )
        )
        self.holdStarted = nil
        self.releasedAt = nil
    }

    /// Light smoothing so the waveform glides instead of strobing at buffer rate.
    private func updateLevel(_ new: Float) {
        level += (new - level) * 0.35
    }

    private func fail(_ message: String) {
        Log.app.error("\(message)")
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .error(message)
        isHUDRevealed = true
        isHandsFree = false
        hotkey.resetGesture()
        level = 0

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if case .error = state { becomeIdle() }
        }
    }
}
