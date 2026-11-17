import Foundation
import Testing

import MurmurCore

/// Every timing edge of the gesture, driven by explicit times so the recognizer never has to
/// read a clock — that is the whole reason it exists as a value type.
struct PushToTalkGestureTests {
    @Test("hold to talk: begin on press, reveal while held, finish on release")
    func hold() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.phase == .pressed(since: 0, revealed: false))
        #expect(gesture.nextDeadline == PushToTalkGesture.tapThreshold)

        #expect(gesture.handle(.tick, at: 0.25) == [.reveal])
        #expect(gesture.phase == .pressed(since: 0, revealed: true))
        #expect(gesture.nextDeadline == nil)

        #expect(gesture.handle(.keyUp, at: 1.0) == [.finish])
        #expect(gesture.phase == .idle)
        #expect(gesture.nextDeadline == nil)
    }

    @Test("a hold released without any tick still finishes")
    func holdWithoutTick() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.handle(.keyUp, at: 0.4) == [.finish])
        #expect(gesture.phase == .idle)
    }

    @Test("a tick before the threshold does nothing")
    func earlyTick() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.handle(.tick, at: 0.1) == [])
        #expect(gesture.phase == .pressed(since: 0, revealed: false))
        #expect(gesture.nextDeadline == PushToTalkGesture.tapThreshold)
    }

    @Test("a second tick after the reveal does nothing")
    func secondTick() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.handle(.tick, at: 0.3) == [.reveal])
        #expect(gesture.handle(.tick, at: 0.5) == [])
        #expect(gesture.phase == .pressed(since: 0, revealed: true))
    }

    @Test("a lone tap cancels once the double-tap window expires")
    func loneTap() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.handle(.keyUp, at: 0.1) == [])
        #expect(gesture.phase == .awaitingSecondTap(releasedAt: 0.1))

        // Computed from the same constants so the exact boundary cannot flip on rounding.
        let deadline = 0.1 + PushToTalkGesture.doubleTapWindow
        #expect(gesture.nextDeadline == deadline)

        #expect(gesture.handle(.tick, at: 0.3) == [])
        #expect(gesture.phase == .awaitingSecondTap(releasedAt: 0.1))

        #expect(gesture.handle(.tick, at: deadline) == [.cancel])
        #expect(gesture.phase == .idle)
        #expect(gesture.nextDeadline == nil)
    }

    @Test("double-tap locks hands-free until the next press finishes it")
    func doubleTapLocks() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.handle(.keyUp, at: 0.1) == [])
        #expect(gesture.handle(.keyDown, at: 0.3) == [.lock])
        #expect(gesture.phase == .locked)
        #expect(gesture.isHandsFree)
        #expect(gesture.nextDeadline == nil)

        // The release that ends the second tap is ignored: recording continues.
        #expect(gesture.handle(.keyUp, at: 0.4) == [])
        #expect(gesture.isHandsFree)

        // The next press ends hands-free, and its release lands in idle and is ignored.
        #expect(gesture.handle(.keyDown, at: 3.0) == [.finish])
        #expect(gesture.phase == .idle)
        #expect(!gesture.isHandsFree)
        #expect(gesture.handle(.keyUp, at: 3.1) == [])
        #expect(gesture.phase == .idle)
    }

    @Test("escape cancels hands-free")
    func escapeCancelsHandsFree() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.handle(.keyUp, at: 0.1) == [])
        #expect(gesture.handle(.keyDown, at: 0.3) == [.lock])

        #expect(gesture.handle(.escape, at: 2) == [.cancel])
        #expect(gesture.phase == .idle)
        #expect(!gesture.isHandsFree)
    }

    @Test("typing while hands-free is ignored")
    func typingWhileLocked() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.handle(.keyUp, at: 0.1) == [])
        #expect(gesture.handle(.keyDown, at: 0.3) == [.lock])

        #expect(gesture.handle(.otherKeyDown, at: 1) == [])
        #expect(gesture.isHandsFree)
        #expect(gesture.handle(.tick, at: 1) == [])
        #expect(gesture.isHandsFree)
    }

    @Test("a key combo while held cancels")
    func comboWhileHeld() {
        var combo = PushToTalkGesture()
        #expect(combo.handle(.keyDown, at: 0) == [.begin])
        #expect(combo.handle(.otherKeyDown, at: 0.5) == [.cancel])
        #expect(combo.phase == .idle)

        var comboEscape = PushToTalkGesture()
        #expect(comboEscape.handle(.keyDown, at: 0) == [.begin])
        #expect(comboEscape.handle(.escape, at: 0.5) == [.cancel])
        #expect(comboEscape.phase == .idle)
    }

    @Test("another key between the two taps cancels")
    func otherKeyBetweenTaps() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.handle(.keyUp, at: 0.1) == [])
        #expect(gesture.handle(.otherKeyDown, at: 0.2) == [.cancel])
        #expect(gesture.phase == .idle)

        var escaped = PushToTalkGesture()
        #expect(escaped.handle(.keyDown, at: 0) == [.begin])
        #expect(escaped.handle(.keyUp, at: 0.1) == [])
        #expect(escaped.handle(.escape, at: 0.2) == [.cancel])
        #expect(escaped.phase == .idle)
    }

    @Test("a late second press cancels the first tap and starts a new one")
    func lateSecondPress() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.handle(.keyUp, at: 0.1) == [])
        #expect(gesture.handle(.keyDown, at: 0.5) == [.cancel, .begin])
        #expect(gesture.phase == .pressed(since: 0.5, revealed: false))
        #expect(gesture.nextDeadline == 0.5 + PushToTalkGesture.tapThreshold)
    }

    @Test("a repeated keyDown while pressed is ignored")
    func repeatedKeyDown() {
        var gesture = PushToTalkGesture()

        #expect(gesture.handle(.keyDown, at: 0) == [.begin])
        #expect(gesture.handle(.keyDown, at: 0.1) == [])
        #expect(gesture.phase == .pressed(since: 0, revealed: false))
    }

    @Test("idle ignores everything except keyDown")
    func idleIgnoresOtherEvents() {
        var gesture = PushToTalkGesture()

        for event in [PushToTalkGesture.Event.keyUp, .otherKeyDown, .escape, .tick] {
            #expect(gesture.handle(event, at: 1) == [], "\(event) should not act while idle")
            #expect(gesture.phase == .idle)
            #expect(gesture.nextDeadline == nil)
        }
    }

    @Test("reset returns to idle from locked, awaiting a second tap, and pressed")
    func reset() {
        var locked = PushToTalkGesture()
        #expect(locked.handle(.keyDown, at: 0) == [.begin])
        #expect(locked.handle(.keyUp, at: 0.1) == [])
        #expect(locked.handle(.keyDown, at: 0.3) == [.lock])

        locked.reset()
        #expect(locked.phase == .idle)
        #expect(!locked.isHandsFree)
        #expect(locked.nextDeadline == nil)

        var awaiting = PushToTalkGesture()
        #expect(awaiting.handle(.keyDown, at: 0) == [.begin])
        #expect(awaiting.handle(.keyUp, at: 0.1) == [])

        awaiting.reset()
        #expect(awaiting.phase == .idle)
        #expect(awaiting.nextDeadline == nil)

        var pressed = PushToTalkGesture()
        #expect(pressed.handle(.keyDown, at: 0) == [.begin])

        pressed.reset()
        #expect(pressed.phase == .idle)
        #expect(pressed.nextDeadline == nil)
    }

    @Test("exact boundaries count as hold and as a late second press")
    func boundaries() {
        var hold = PushToTalkGesture()
        #expect(hold.handle(.keyDown, at: 1.0) == [.begin])
        #expect(hold.handle(.keyUp, at: 1.25) == [.finish])
        #expect(hold.phase == .idle)

        var doubleTap = PushToTalkGesture()
        #expect(doubleTap.handle(.keyDown, at: 0) == [.begin])
        #expect(doubleTap.handle(.keyUp, at: 0.1) == [])
        #expect(doubleTap.handle(.keyDown, at: 0.1 + PushToTalkGesture.doubleTapWindow) == [.cancel, .begin])
        #expect(doubleTap.phase == .pressed(since: 0.1 + PushToTalkGesture.doubleTapWindow, revealed: false))
    }
}
