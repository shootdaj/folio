import Testing
@testable import FolioCore

/// Following a press without trusting that its button-up event arrives. Mission Control, Exposé or a
/// Space switch can take the release, so a loop must also stop when the button is no longer down.
@Suite struct PressTrackingTests {
    @Test func keepsFollowingWhileTheButtonIsDown() {
        #expect(!PressTracking.shouldStop(pressedButtons: 0b001, button: 0, idle: 10, limit: nil))
        #expect(!PressTracking.shouldStop(pressedButtons: 0b010, button: 1, idle: 0.5, limit: 3))
    }

    @Test func stopsWhenTheButtonWasReleasedOutsideTheApp() {
        #expect(PressTracking.shouldStop(pressedButtons: 0, button: 0, idle: 0, limit: nil))
        // The right button is followed by its own bit: the left one held does not keep it alive.
        #expect(PressTracking.shouldStop(pressedButtons: 0b001, button: 1, idle: 0, limit: nil))
    }

    @Test func anIdleLimitEndsAPressThatSitsStill() {
        #expect(PressTracking.shouldStop(pressedButtons: 0b001, button: 0, idle: 3, limit: 3))
        #expect(!PressTracking.shouldStop(pressedButtons: 0b001, button: 0, idle: 2.9, limit: 3))
    }

    @Test func withNoLimitAPressCanSitStillAsLongAsTheButtonIsDown() {
        // A marquee or a pane resize held still for a minute is still a drag.
        #expect(!PressTracking.shouldStop(pressedButtons: 0b001, button: 0, idle: 60, limit: nil))
    }
}
