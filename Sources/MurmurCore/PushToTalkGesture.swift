import Foundation

/// Turns push-to-talk key events into dictation actions.
///
/// Hold the key to talk and release to finish; tap twice quickly to lock hands-free. A lone
/// tap, or any other key pressed meanwhile, means the user was not dictating after all.
/// A pure value with no clock and no I/O, so every timing edge is testable.
public struct PushToTalkGesture: Sendable, Equatable {
    public enum Event: Sendable, Equatable {
        /// The push-to-talk key went down.
        case keyDown
        /// The push-to-talk key came up.
        case keyUp
        /// Any other key was pressed, except Escape.
        case otherKeyDown
        /// Escape was pressed.
        case escape
        /// `nextDeadline` has passed.
        case tick
    }

    public enum Action: Sendable, Equatable {
        /// Start capturing. Sent on the very first press so no syllable is lost.
        case begin
        /// The press is a deliberate hold: show the HUD.
        case reveal
        /// Hands-free mode engaged: keep recording after the key is released.
        case lock
        /// Stop, transcribe and type.
        case finish
        /// Stop and discard.
        case cancel
    }

    public enum Phase: Sendable, Equatable {
        case idle
        case pressed(since: TimeInterval, revealed: Bool)
        case awaitingSecondTap(releasedAt: TimeInterval)
        case locked
    }

    /// A press released sooner than this is a tap, not a hold.
    public static let tapThreshold: TimeInterval = 0.25
    /// How long after a tap's release a second press still counts as a double-tap.
    public static let doubleTapWindow: TimeInterval = 0.35

    public private(set) var phase: Phase = .idle

    public init() {}

    public var isHandsFree: Bool { phase == .locked }

    /// When the caller should send `.tick`, or nil if no timer is needed.
    public var nextDeadline: TimeInterval? {
        switch phase {
        case let .pressed(since, revealed):
            revealed ? nil : since + Self.tapThreshold
        case let .awaitingSecondTap(releasedAt):
            releasedAt + Self.doubleTapWindow
        case .idle, .locked:
            nil
        }
    }

    /// Back to idle without emitting anything — for when dictation ended some other way
    /// (an error, the window's Stop button).
    public mutating func reset() { phase = .idle }

    public mutating func handle(_ event: Event, at time: TimeInterval) -> [Action] {
        switch (phase, event) {
        case (.idle, .keyDown):
            phase = .pressed(since: time, revealed: false)
            return [.begin]

        case let (.pressed(since, _), .keyUp):
            // Long enough to be a hold, even if the reveal tick never arrived.
            guard time - since < Self.tapThreshold else {
                phase = .idle
                return [.finish]
            }
            phase = .awaitingSecondTap(releasedAt: time)
            return []

        case let (.pressed(since, revealed), .tick) where !revealed && time - since >= Self.tapThreshold:
            phase = .pressed(since: since, revealed: true)
            return [.reveal]

        case (.pressed, .otherKeyDown), (.pressed, .escape):
            phase = .idle
            return [.cancel]

        case let (.awaitingSecondTap(releasedAt), .keyDown):
            // A late second press means the expiry tick was dropped: cancel the first tap
            // and treat this as a fresh one rather than losing the press entirely.
            guard time - releasedAt < Self.doubleTapWindow else {
                phase = .pressed(since: time, revealed: false)
                return [.cancel, .begin]
            }
            phase = .locked
            return [.lock]

        case let (.awaitingSecondTap(releasedAt), .tick) where time - releasedAt >= Self.doubleTapWindow:
            phase = .idle
            return [.cancel]

        case (.awaitingSecondTap, .otherKeyDown), (.awaitingSecondTap, .escape):
            phase = .idle
            return [.cancel]

        case (.locked, .keyDown):
            phase = .idle
            return [.finish]

        case (.locked, .escape):
            phase = .idle
            return [.cancel]

        default:
            return []
        }
    }
}
