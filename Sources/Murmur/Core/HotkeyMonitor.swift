import AppKit
import Carbon.HIToolbox
import Foundation
import MurmurCore

/// Which modifier key holds the mic open.
enum PushToTalkKey: String, CaseIterable, Sendable {
    case rightOption
    case fn
    case rightCommand

    var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)   // 61
        case .fn: Int64(kVK_Function)               // 63
        case .rightCommand: Int64(kVK_RightCommand) // 54
        }
    }

    /// Device-*dependent* bit for this specific physical key.
    ///
    /// `CGEventFlags.maskAlternate` is the union mask — it's set whenever *either* Option
    /// key is down. Using it means: hold Left ⌥, tap Right ⌥, and the release is invisible
    /// (the union bit is still set by the left key), so the release never registers. The mic
    /// stays open, the HUD stays up, and the next press is swallowed too.
    ///
    /// These raw values are the NX_DEVICE* masks from IOKit's event system; they carry the
    /// left/right distinction that the public `CGEventFlags` constants discard.
    var flag: CGEventFlags {
        switch self {
        case .rightOption: CGEventFlags(rawValue: 0x40)   // NX_DEVICERALTKEYMASK
        case .rightCommand: CGEventFlags(rawValue: 0x10)  // NX_DEVICERCMDKEYMASK
        case .fn: .maskSecondaryFn                        // no left/right variant exists
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .fn: "fn"
        case .rightCommand: "Right ⌘"
        }
    }

    /// Swallowing `fn` would break fn+arrow, fn+delete and the emoji picker, so we let it
    /// through. Dedicated right-hand modifiers are safe to consume.
    var shouldConsumeEvent: Bool { self != .fn }
}

/// Two macOS keyboard settings that fight fn-to-dictate. Read from the system's own
/// preferences, which an unsandboxed app can see.
enum SystemKeyboard {
    /// "Press 🌐 key to" is Do Nothing (`AppleFnUsageType` 0). Anything else — emoji
    /// picker, input source, Apple Dictation — also fires on every fn press. A missing key
    /// means the system default, which is not Do Nothing.
    static var fnKeyDoesNothing: Bool {
        UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int == 0
    }

    /// Apple Dictation is on. Its default shortcut is "Press 🌐 twice", the same gesture
    /// as hands-free mode; the shortcut itself isn't readable, so this can only warn.
    static var appleDictationEnabled: Bool {
        UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleDictationAutoEnable") as? Int == 1
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}

/// Watches the push-to-talk key and hands its events to `PushToTalkGesture`.
///
/// It observes key-downs as well as the modifier flag, because a lone tap of the key and the
/// key pressed merely as a modifier (fn+arrow, fn+delete) both look exactly like a dictation
/// until the other keys are seen. No key-down is ever swallowed — that would break the very
/// shortcuts this exists to distinguish — except Escape, and only when it cancelled something.
///
/// A tap is required rather than `NSEvent.addGlobalMonitor` because `fn` and left/right
/// modifier discrimination don't surface through the higher-level APIs. This needs
/// Accessibility permission; without it `CGEvent.tapCreate` returns nil.
@MainActor
final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private var gesture = PushToTalkGesture()
    private var deadlineTask: Task<Void, Never>?

    var key: PushToTalkKey = .rightOption
    var onAction: ((PushToTalkGesture.Action) -> Void)?

    /// - Returns: `false` if the tap couldn't be created — almost always missing Accessibility permission.
    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // CGEvent isn't Sendable, so pull out the plain values before crossing into
                // actor-isolated code. The tap was added to the main run loop, so this
                // callback genuinely does run on the main thread.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("listening for \(self.key.displayName)")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isPressed = false
        resetGesture()
    }

    // MARK: - Tap callback

    /// - Returns: `true` if the event should be swallowed rather than passed along.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        // The system disables a tap that runs too slowly or is interrupted; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        switch type {
        case .keyDown:
            let event: PushToTalkGesture.Event = keyCode == Int64(kVK_Escape) ? .escape : .otherKeyDown
            let actions = dispatch(event)
            // Escape is swallowed only when it actually cancelled a dictation. Every other
            // key-down passes through untouched, whatever the recognizer decides.
            return event == .escape && !actions.isEmpty

        case .flagsChanged where keyCode == key.keyCode:
            let nowPressed = flags.contains(key.flag)
            guard nowPressed != isPressed else { return false }
            isPressed = nowPressed

            dispatch(nowPressed ? .keyDown : .keyUp)
            return key.shouldConsumeEvent

        default:
            return false
        }
    }

    // MARK: - Gesture

    /// Feeds the recognizer, forwards what it decides, and re-arms the timer it asks for.
    @discardableResult
    private func dispatch(_ event: PushToTalkGesture.Event) -> [PushToTalkGesture.Action] {
        let actions = gesture.handle(event, at: ProcessInfo.processInfo.systemUptime)
        for action in actions { onAction?(action) }
        scheduleTick()
        return actions
    }

    private func scheduleTick() {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard let deadline = gesture.nextDeadline else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        deadlineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.dispatch(.tick)
        }
    }

    /// Forgets a gesture in progress — for when dictation ended without it (an error, the
    /// window's Stop button), so the next press starts fresh instead of finishing nothing.
    func resetGesture() {
        gesture.reset()
        deadlineTask?.cancel()
        deadlineTask = nil
    }
}
