//
//  HapticsAndDetentTests.swift
//  LatitudeCam
//
//  A click that does not coincide with a value change is worse than no click at
//  all — it teaches the user to distrust the feedback. These pin the slider's
//  detent index to the same arithmetic the value uses.
//

import XCTest
@testable import LatitudeCam

final class DetentIndexTests: XCTestCase {

    func testIndexSpansTheFullRange() {
        XCTAssertEqual(SliderRow.detentIndex(position: 0, detents: 7), 0)
        XCTAssertEqual(SliderRow.detentIndex(position: 1, detents: 7), 6)
    }

    /// Drag gestures overshoot the track at both ends.
    func testIndexClampsOutsideTheTrack() {
        XCTAssertEqual(SliderRow.detentIndex(position: -3, detents: 7), 0)
        XCTAssertEqual(SliderRow.detentIndex(position: 4, detents: 7), 6)
    }

    func testZeroDetentsIsASmoothTrack() {
        XCTAssertEqual(SliderRow.detentIndex(position: 0.7, detents: 0), 0)
    }

    func testEveryStopIsReachable() {
        var reached = Set<Int>()
        for step in 0...1000 {
            reached.insert(SliderRow.detentIndex(position: Double(step) / 1000, detents: 7))
        }
        XCTAssertEqual(reached.count, 7, "a stop the finger cannot land on is a dead click")
    }
}

@MainActor
final class DetentValueAgreementTests: XCTestCase {

    /// The slider clicks on `detentIndex`; the readout comes from `stop()`. If
    /// they ever disagree the ISO ring buzzes without the ISO changing.
    func testISOClicksAgreeWithTheStopLadder() {
        let app = AppState()
        let detents = AppState.isoStops.count

        for step in 0...500 {
            let position = Double(step) / 500
            let index = SliderRow.detentIndex(position: position, detents: detents)
            app.iso = position
            XCTAssertEqual(app.isoValue, AppState.isoStops[index], "position \(position)")
        }
    }

    func testShutterClicksAgreeWithTheStopLadder() {
        let app = AppState()
        let detents = AppState.shutterStops.count

        for step in 0...500 {
            let position = Double(step) / 500
            let index = SliderRow.detentIndex(position: position, detents: detents)
            app.shutter = position
            XCTAssertEqual(app.shutterValue, AppState.shutterStops[index], "position \(position)")
        }
    }

    func testExposureCompensationClicksInHalfStops() {
        let app = AppState()

        app.exposureComp = 0
        XCTAssertEqual(app.evValue, -2.5, accuracy: 0.001)
        app.exposureComp = 1
        XCTAssertEqual(app.evValue, 2.5, accuracy: 0.001)
        app.exposureComp = 0.5
        XCTAssertEqual(app.evValue, 0, accuracy: 0.001)
    }

    func testExposureCompensationOnlyEverLandsOnAHalfStop() {
        let app = AppState()
        for step in 0...500 {
            app.exposureComp = Double(step) / 500
            let doubled = app.evValue * 2
            XCTAssertEqual(doubled, doubled.rounded(), accuracy: 0.0001,
                           "\(app.evValue) EV is not a half stop")
        }
    }

    func testExposureCompensationClickAndValueChangeTogether() {
        let app = AppState()
        var lastIndex = -1
        var lastValue = Double.nan

        for step in 0...500 {
            let position = Double(step) / 500
            app.exposureComp = position
            let index = SliderRow.detentIndex(position: position, detents: AppState.evDetents)

            if index != lastIndex {
                if lastIndex != -1 {
                    XCTAssertNotEqual(app.evValue, lastValue, accuracy: 0.0001,
                                      "clicked at \(position) without changing the value")
                }
                lastIndex = index
                lastValue = app.evValue
            } else if !lastValue.isNaN {
                XCTAssertEqual(app.evValue, lastValue, accuracy: 0.0001,
                               "value changed at \(position) without a click")
            }
        }
    }

    /// A fresh camera sits at no compensation, the way a body does out of the bag.
    func testDefaultCompensationIsZero() {
        XCTAssertEqual(AppState().evValue, 0, accuracy: 0.001)
        XCTAssertEqual(AppState().exposureLabel, "+0.0 EV")
    }
}

@MainActor
final class HapticsSettingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Pref.haptics)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Pref.haptics)
        super.tearDown()
    }

    func testHapticsAreOnUntilSwitchedOff() {
        XCTAssertTrue(Haptics.isEnabled)
    }

    func testSwitchingOffSilencesTheWholeSystem() {
        UserDefaults.standard.set(false, forKey: Pref.haptics)
        XCTAssertFalse(Haptics.isEnabled)
    }

    func testSwitchingBackOnRestoresIt() {
        UserDefaults.standard.set(false, forKey: Pref.haptics)
        UserDefaults.standard.set(true, forKey: Pref.haptics)
        XCTAssertTrue(Haptics.isEnabled)
    }

    /// Every haptic call has to be safe with the setting off — they are wired
    /// into gesture handlers that run regardless.
    func testEveryCueIsSafeWhileDisabled() {
        UserDefaults.standard.set(false, forKey: Pref.haptics)
        Haptics.prepare()
        Haptics.detent()
        Haptics.toggle()
        Haptics.tap()
        Haptics.shutter()
        Haptics.success()
        Haptics.blocked()
    }
}

@MainActor
final class ShutterFeedbackTests: XCTestCase {

    /// The viewfinder picks the thump or the warning off this return value, so a
    /// capture that recorded nothing must not report success.
    func testCaptureReportsFailureWithNoFrame() {
        let app = AppState()
        XCTAssertFalse(app.capture())
        XCTAssertNil(app.capturedImage)
    }
}

// MARK: - Snapping

final class DetentSnapTests: XCTestCase {

    /// A snapped thumb has to land where the lit tick is drawn, or the control
    /// shows a value it is not sitting on.
    func testCentreIsTheMidpointOfItsBand() {
        for index in 0..<7 {
            let centre = SliderRow.detentCentre(index: index, detents: 7)
            XCTAssertEqual(SliderRow.detentIndex(position: centre, detents: 7), index)
        }
    }

    func testSnappingIsStable() {
        for index in 0..<11 {
            let once = SliderRow.detentCentre(index: index, detents: 11)
            let twice = SliderRow.detentCentre(
                index: SliderRow.detentIndex(position: once, detents: 11), detents: 11
            )
            XCTAssertEqual(once, twice, accuracy: 0.0001)
        }
    }

    func testCentresStayInsideTheTrack() {
        for index in 0..<7 {
            let centre = SliderRow.detentCentre(index: index, detents: 7)
            XCTAssertGreaterThan(centre, 0)
            XCTAssertLessThan(centre, 1)
        }
    }
}


// MARK: - Command dials

@MainActor
final class DialIndexTests: XCTestCase {

    /// The dial addresses stops by index while AppState stores 0…1. A lossy
    /// round trip would make the dial drift a stop every time it is reopened.
    func testEveryDialIndexRoundTrips() {
        let app = AppState()

        // Shutter and ISO carry a leading A, so stop n sits at dial index n + 1.
        for index in AppState.shutterStops.indices {
            app.shutterIndex = index + 1
            XCTAssertEqual(app.shutterIndex, index + 1)
            XCTAssertEqual(app.shutterValue, AppState.shutterStops[index])
        }
        for index in AppState.isoStops.indices {
            app.isoIndex = index + 1
            XCTAssertEqual(app.isoIndex, index + 1)
            XCTAssertEqual(app.isoValue, AppState.isoStops[index])
        }
        for index in AppState.whiteBalanceStops.indices {
            app.whiteBalanceIndex = index
            XCTAssertEqual(app.whiteBalanceIndex, index)
            XCTAssertEqual(app.kelvinValue, Double(AppState.whiteBalanceStops[index]))
        }
        for index in 0..<AppState.evDetents {
            app.exposureIndex = index
            XCTAssertEqual(app.exposureIndex, index)
        }
    }

    /// Accessibility increment can run past either end of the barrel.
    func testDialIndexClampsAtBothEnds() {
        let app = AppState()
        app.shutterIndex = 99
        XCTAssertEqual(app.shutterIndex, AppState.shutterStops.count)
        app.shutterIndex = -4
        XCTAssertEqual(app.shutterIndex, 0, "past the slow end is A")
    }

    func testDialsReachTheRenderPipeline() {
        let app = AppState()
        app.isoIndex = AppState.isoStops.count
        XCTAssertEqual(app.cameraManager.currentSettings.iso, AppState.isoStops.last)
    }

    func testEveryDialHasALabelPerStop() {
        XCTAssertEqual(AppState.shutterLabels.count, AppState.shutterStops.count + 1)
        XCTAssertEqual(AppState.isoLabels.count, AppState.isoStops.count + 1)
        XCTAssertEqual(AppState.whiteBalanceLabels.count, AppState.whiteBalanceStops.count)
        XCTAssertEqual(AppState.exposureLabels.count, AppState.evDetents)
    }

    func testDialLabelsMatchTheirValues() {
        XCTAssertEqual(AppState.shutterLabels[1], "1/15")
        XCTAssertEqual(AppState.isoLabels[1], "50")
        XCTAssertEqual(AppState.whiteBalanceLabels.first, "2500K")
    }

    /// The middle stop of a compensation dial has to be exactly zero, and it is
    /// the one marked on the barrel so it can be found without looking.
    func testExposureDialIsSymmetricAboutZero() {
        let middle = AppState.evDetents / 2
        XCTAssertEqual(AppState.exposureLabels[middle], "+0.0")
        XCTAssertEqual(AppState.exposureLabels.first, "-2.5")
        XCTAssertEqual(AppState.exposureLabels.last, "+2.5")
    }

    func testExposureDialNeutralStopIsZeroEV() {
        let app = AppState()
        app.exposureIndex = AppState.evDetents / 2
        XCTAssertEqual(app.evValue, 0, accuracy: 0.001)
    }
}

// MARK: - Strength

@MainActor
final class HapticStrengthTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Pref.hapticStrength)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Pref.hapticStrength)
        super.tearDown()
    }

    func testDefaultsToStrong() {
        XCTAssertEqual(Haptics.strength, .strong)
    }

    /// Every option the Settings picker offers must resolve, or the row would
    /// silently fall back and the setting would do nothing.
    func testEverySettingsOptionResolves() {
        for name in Pref.hapticStrengthOptions {
            UserDefaults.standard.set(name, forKey: Pref.hapticStrength)
            XCTAssertEqual(Haptics.strength.rawValue, name)
        }
    }

    func testOptionsCoverEveryStrength() {
        XCTAssertEqual(Set(Pref.hapticStrengthOptions),
                       Set(Haptics.Strength.allCases.map(\.rawValue)))
    }

    func testUnknownStrengthFallsBackToStrong() {
        UserDefaults.standard.set("nonsense", forKey: Pref.hapticStrength)
        XCTAssertEqual(Haptics.strength, .strong)
    }

    func testLevelsIncreaseAndStayInRange() {
        let levels = [Haptics.Strength.subtle, .standard, .strong].map(\.level)
        XCTAssertLessThan(levels[0], levels[1])
        XCTAssertLessThan(levels[1], levels[2])
        for level in levels {
            XCTAssertGreaterThan(level, 0)
            XCTAssertLessThanOrEqual(level, 1)
        }
    }

    func testEveryCueIsSafeAtEveryStrength() {
        UserDefaults.standard.set(true, forKey: Pref.haptics)
        for name in Pref.hapticStrengthOptions {
            UserDefaults.standard.set(name, forKey: Pref.hapticStrength)
            Haptics.prepare(); Haptics.detent(); Haptics.toggle()
            Haptics.tap(); Haptics.shutter(); Haptics.success(); Haptics.blocked()
        }
        UserDefaults.standard.removeObject(forKey: Pref.haptics)
    }
}


// MARK: - A positions

@MainActor
final class AutoExposureDialTests: XCTestCase {

    func testAIsTheFirstStopOnBothScales() {
        XCTAssertEqual(AppState.shutterLabels.first, "A")
        XCTAssertEqual(AppState.isoLabels.first, "A")
        XCTAssertEqual(AppState.shutterLabels.count, AppState.shutterStops.count + 1)
        XCTAssertEqual(AppState.isoLabels.count, AppState.isoStops.count + 1)
    }

    func testTurningToAHandsExposureBack() {
        let app = AppState()
        app.shutterIndex = 0
        XCTAssertTrue(app.autoExposure)
        XCTAssertTrue(app.cameraManager.currentSettings.autoExposure)
        XCTAssertEqual(app.shutterLabel, "AUTO")
    }

    /// AVFoundation's continuous auto governs shutter and ISO together, so both
    /// dials have to agree — showing one on A and one on a number would be a lie.
    func testBothDialsShowAWhenAutomatic() {
        let app = AppState()
        app.isoIndex = 0
        XCTAssertEqual(app.shutterIndex, 0)
        XCTAssertEqual(app.isoIndex, 0)
    }

    func testTurningOffAReturnsToThatStop() {
        let app = AppState()
        app.shutterIndex = 0
        app.shutterIndex = 3
        XCTAssertFalse(app.autoExposure)
        XCTAssertEqual(app.shutterIndex, 3)
        XCTAssertEqual(app.shutterValue, AppState.shutterStops[2])
    }

    func testStopsStillRoundTripWithTheAOffset() {
        let app = AppState()
        for index in 1...AppState.isoStops.count {
            app.isoIndex = index
            XCTAssertEqual(app.isoIndex, index)
            XCTAssertEqual(app.isoValue, AppState.isoStops[index - 1])
        }
    }
}

// MARK: - Reset, undo, redo

@MainActor
final class ControlHistoryTests: XCTestCase {

    private func persistedKeys() -> [String] {
        ["LatitudeCam.ISO", "LatitudeCam.Shutter", "LatitudeCam.FilmProfile", "LatitudeCam.Kelvin"]
    }

    override func setUp() {
        super.setUp()
        persistedKeys().forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    func testResetReturnsEveryControlToTheDefault() {
        let app = AppState()
        app.intensity = 0.1
        app.grainOn = false
        app.isoIndex = 6

        app.resetControls()
        XCTAssertEqual(app.controls, AppState.defaultControls)
    }

    /// A reset you cannot take back is a trap — the whole point of putting it one
    /// tap from the dials is that the tap is cheap to undo.
    func testResetIsUndoable() {
        let app = AppState()
        app.intensity = 0.15
        app.halationOn = true
        let before = app.controls

        app.resetControls()
        XCTAssertTrue(app.canUndo)

        app.undoControls()
        XCTAssertEqual(app.controls, before)
    }

    func testUndoneResetCanBeRedone() {
        let app = AppState()
        app.intensity = 0.15
        app.resetControls()
        app.undoControls()
        XCTAssertTrue(app.canRedo)

        app.redoControls()
        XCTAssertEqual(app.controls, AppState.defaultControls)
    }

    func testNothingToUndoAtTheStart() {
        let app = AppState()
        XCTAssertFalse(app.canUndo)
        XCTAssertFalse(app.canRedo)
        app.undoControls()
        app.redoControls()
        XCTAssertEqual(app.controls, app.controls)
    }

    func testResettingWhenAlreadyDefaultDoesNotStackHistory() {
        let app = AppState()
        app.apply(AppState.defaultControls)
        app.resetControls()
        XCTAssertFalse(app.canUndo, "a no-op reset must not fill the undo stack")
    }

    /// A fresh change after undoing invalidates the redo branch, as everywhere else.
    func testNewChangeClearsRedo() {
        let app = AppState()
        app.intensity = 0.2
        app.resetControls()
        app.undoControls()
        XCTAssertTrue(app.canRedo)

        app.resetControls()
        XCTAssertFalse(app.canRedo)
    }

    func testSnapshotRoundTrips() {
        let app = AppState()
        app.intensity = 0.33
        app.vignetteOn = true
        app.whiteBalanceIndex = 5
        let snapshot = app.controls

        app.resetControls()
        app.apply(snapshot)
        XCTAssertEqual(app.controls, snapshot)
    }
}

// MARK: - Film knob geometry

final class FilmKnobGeometryTests: XCTestCase {

    func testWrapTakesTheShortWayRound() {
        XCTAssertEqual(FilmKnob.wrap(3, count: 4), -1, accuracy: 0.001)
        XCTAssertEqual(FilmKnob.wrap(-3, count: 4), 1, accuracy: 0.001)
        XCTAssertEqual(FilmKnob.wrap(1, count: 4), 1, accuracy: 0.001)
        XCTAssertEqual(FilmKnob.wrap(0, count: 4), 0, accuracy: 0.001)
    }

    func testWrapStaysInsideHalfATurn() {
        for delta in stride(from: -12.0, through: 12.0, by: 0.5) {
            let wrapped = FilmKnob.wrap(delta, count: 4)
            XCTAssertGreaterThanOrEqual(wrapped, -2)
            XCTAssertLessThanOrEqual(wrapped, 2)
        }
    }

    /// The loaded stock is the one you read, so it is never tilted.
    func testLoadedFrameIsUpright() {
        XCTAssertEqual(FilmKnob.tilt(for: 0), 0, accuracy: 0.001)
    }

    func testTiltIsCappedSoTheRebateStaysReadable() {
        XCTAssertEqual(FilmKnob.tilt(for: 180), 28, accuracy: 0.001)
        XCTAssertEqual(FilmKnob.tilt(for: -180), -28, accuracy: 0.001)
    }

    func testFramesShrinkAndFadeAwayFromTheApex() {
        XCTAssertGreaterThan(FilmKnob.scale(for: 0), FilmKnob.scale(for: 46))
        XCTAssertGreaterThan(FilmKnob.opacity(for: 0), FilmKnob.opacity(for: 46))
        XCTAssertGreaterThanOrEqual(FilmKnob.scale(for: 92), 0.6)
        XCTAssertGreaterThanOrEqual(FilmKnob.opacity(for: 92), 0.28)
    }

    func testApexSitsDirectlyAboveTheHub() {
        let hub = CGPoint(x: 100, y: 300)
        let apex = FilmKnob.point(hub: hub, angle: 0, radius: 116)
        XCTAssertEqual(apex.x, hub.x, accuracy: 0.001)
        XCTAssertEqual(apex.y, hub.y - 116, accuracy: 0.001)
    }
}
