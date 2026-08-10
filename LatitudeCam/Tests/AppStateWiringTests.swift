//
//  AppStateWiringTests.swift
//  LatitudeCam
//
//  Every control in the UI is a binding into AppState, and AppState is the only
//  thing that talks to the render pipeline. These tests assert that link: move a
//  control, and the camera settings change to match. A control that renders but
//  is not connected passes a snapshot test and fails here.
//

import XCTest
@testable import LatitudeCam

@MainActor
final class AppStateWiringTests: XCTestCase {

    private static let persistedKeys = [
        "LatitudeCam.ISO", "LatitudeCam.Shutter",
        "LatitudeCam.FilmProfile", "LatitudeCam.Kelvin"
    ]

    override func setUp() {
        super.setUp()
        Self.persistedKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("Gallery"))
    }

    override func tearDown() {
        Self.persistedKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - Manual focus

    /// The focus stops are deliberately *not* evenly spaced — near distances
    /// take less of the barrel's travel than far ones, as on a real lens. That
    /// is why the dial drives `focusDial` and not `focus`: a uniform dial over
    /// a non-uniform ladder lights a mark the reading disagrees with.
    func testTheFocusLadderIsNotEvenlySpaced() {
        let gaps = zip(AppState.focusStops, AppState.focusStops.dropFirst())
            .map { $1.position - $0.position }
        XCTAssertGreaterThan(gaps.count, 1)
        XCTAssertFalse(
            gaps.allSatisfy { abs($0 - gaps[0]) < 0.001 },
            "the ladder is uniform now — focusDial's indirection is no longer needed"
        )
    }

    /// Every focus stop the dial can land on reads back as itself, and the
    /// label matches — the same guarantee the other five dials have.
    func testEachFocusStopReadsBackAsItself() {
        let app = AppState()
        let stops = AppState.focusStops.count

        for index in 0..<stops {
            app.focusDial = (Double(index) + 0.5) / Double(stops)
            XCTAssertEqual(KnobMath.detent(app.focusDial, stops: stops), index,
                           "focus stop \(index) does not read back as itself")
            XCTAssertEqual(app.focusLabel, AppState.focusStops[index].label,
                           "the reading disagrees with the lit mark")
            XCTAssertFalse(app.autoFocus, "setting a distance should leave autofocus")
        }
    }

    /// And the dial hands focus back to the camera, as shutter and ISO hand
    /// back metering.
    func testFocusReturnsToAutomatic() {
        let app = AppState()
        app.focusDial = 0.9
        XCTAssertFalse(app.autoFocus)
        XCTAssertNotEqual(app.focusLabel, "AF")

        app.autoFocus = true
        XCTAssertEqual(app.focusLabel, "AF")
    }

    // MARK: - The hardware Camera Control

    /// The button's ladders must be the ones the dials index.
    ///
    /// Same trap as the engraved scales: the "A"-headed label lists are one
    /// entry longer than the stop count, and building a picker from one would
    /// put the button off by one for every stop past the first.
    func testHardwareLaddersMatchTheStopCounts() {
        let ladders = AppState().hardwareControlLadders()

        XCTAssertEqual(ladders[.shutter]?.count, AppState.shutterStops.count)
        XCTAssertEqual(ladders[.iso]?.count, AppState.isoStops.count)
        XCTAssertEqual(ladders[.aperture]?.count, AppState.apertureStops.count)
        XCTAssertEqual(ladders[.exposure]?.count, AppState.evDetents)

        XCTAssertNotEqual(ladders[.shutter]?.count, AppState.shutterLabels.count,
                          "the shutter picker is built from the A-headed list")
        XCTAssertNotEqual(ladders[.iso]?.count, AppState.isoLabels.count,
                          "the ISO picker is built from the A-headed list")
    }

    /// Four dials, because the system takes four. Five would mean one silently
    /// never reaches the button.
    func testEveryOfferedDialHasALadder() {
        let ladders = AppState().hardwareControlLadders()
        for dial in CameraControlDial.allCases {
            XCTAssertNotNil(ladders[dial], "\(dial.rawValue) is offered but has no ladder")
        }
        XCTAssertEqual(CameraControlDial.allCases.count, 4)
    }

    /// A turn of the button has to land on the same stop the dial would.
    func testTheButtonSelectsTheStopItNames() {
        let app = AppState()

        for index in 0..<AppState.shutterStops.count {
            app.applyHardwareControl(.shutter, index: index)
            XCTAssertEqual(app.shutterIndex - 1, index, "shutter stop \(index)")
            XCTAssertFalse(app.autoExposure, "the button did not leave automatic")
        }

        for index in 0..<AppState.apertureStops.count {
            app.applyHardwareControl(.aperture, index: index)
            XCTAssertEqual(app.apertureIndex, index, "aperture stop \(index)")
        }

        for index in 0..<AppState.evDetents {
            app.applyHardwareControl(.exposure, index: index)
            XCTAssertEqual(app.exposureIndex, index, "exposure stop \(index)")
        }
    }

    /// Exposure and aperture must *not* drag the camera off automatic — only
    /// the two that actually set the exposure do.
    func testApertureAndExposureLeaveMeteringAlone() {
        let app = AppState()
        app.autoExposure = true

        app.applyHardwareControl(.aperture, index: 5)
        XCTAssertTrue(app.autoExposure, "aperture should not take the camera off auto")

        app.applyHardwareControl(.exposure, index: 8)
        XCTAssertTrue(app.autoExposure, "exposure compensation should not take the camera off auto")
    }

    /// **The graceful-degradation case.** On a body with no Camera Control the
    /// published flags stay false and the on-screen dials keep working exactly
    /// as they do now. This is the one thing that cannot be checked on the
    /// owner's phone, because that phone *has* the button.
    func testNothingBreaksWithoutTheHardwareButton() {
        let app = AppState()

        XCTAssertFalse(app.cameraManager.hasHardwareControls,
                       "no controls should be claimed before a session reports the button")
        XCTAssertFalse(app.cameraManager.cameraControlActive,
                       "the HUD cannot be active on a body without the button")

        // Safe to call whether or not anything is attached — the app calls it
        // from syncCamera on every settings change.
        app.cameraManager.refreshCameraControls()

        // And the dials still work.
        app.autoExposure = false
        app.shutter = 0.9
        let high = app.shutterLabel
        app.shutter = 0.1
        XCTAssertNotEqual(app.shutterLabel, high, "the on-screen dial stopped working")
    }

    // MARK: - What the barrel reads

    /// Turning the shutter or ISO dial has to take the camera off automatic.
    ///
    /// It did not: `PlateDial` called `onEngage` at the start of every turn,
    /// but the strip never supplied one, so the dial wrote a new position while
    /// `autoExposure` stayed true — the camera kept metering for itself and the
    /// reading rendered as "AUTO" however far the dial was turned.
    func testTurningShutterOrISOLeavesAutomatic() {
        for engage in [\AppState.shutter, \AppState.iso] as [ReferenceWritableKeyPath<AppState, Double>] {
            let app = AppState()
            XCTAssertTrue(app.autoExposure, "a fresh camera meters for itself")

            // What onEngage does, followed by what the turn does.
            app.autoExposure = false
            app[keyPath: engage] = 0.8

            XCTAssertFalse(app.autoExposure)
            XCTAssertNotEqual(app.shutterLabel, "AUTO")
            XCTAssertNotEqual(app.isoLabel, "ISO A")
        }
    }

    /// Every dial's reading has to change when its dial moves. A reading that
    /// is pinned to one string — "AUTO", or the value from before the turn —
    /// looks like a dead control.
    func testEveryDialsReadingFollowsItsOwnValue() {
        let app = AppState()
        app.autoExposure = false

        func readings(_ positions: [Double],
                      set: (Double) -> Void,
                      read: () -> String) -> [String] {
            positions.map { set($0); return read() }
        }

        let low = 0.05, high = 0.95

        let shutter = readings([low, high], set: { app.shutter = $0 }, read: { app.shutterLabel })
        XCTAssertNotEqual(shutter[0], shutter[1], "shutter reads the same at both ends")

        let iso = readings([low, high], set: { app.iso = $0 }, read: { app.isoLabel })
        XCTAssertNotEqual(iso[0], iso[1], "ISO reads the same at both ends")

        let kelvin = readings([low, high], set: { app.whiteBalance = $0 }, read: { app.kelvinLabel })
        XCTAssertNotEqual(kelvin[0], kelvin[1], "white balance reads the same at both ends")

        let ev = readings([low, high], set: { app.exposureComp = $0 }, read: { app.exposureLabel })
        XCTAssertNotEqual(ev[0], ev[1], "exposure reads the same at both ends")

        let aperture = readings([low, high], set: { app.aperture = $0 }, read: { app.apertureLabel })
        XCTAssertNotEqual(aperture[0], aperture[1], "aperture reads the same at both ends")
    }

    /// And a reset has to be visible in the reading immediately — the barrel
    /// takes its text from the app rather than from what the dial was last
    /// built with, so there is no frame where it still shows the old value.
    func testAResetIsVisibleInTheReadingAtOnce() {
        let app = AppState()
        app.autoExposure = false
        app.whiteBalance = 0.95
        let moved = app.kelvinLabel

        app.whiteBalance = AppState.defaultControls.whiteBalance
        XCTAssertNotEqual(app.kelvinLabel, moved,
                          "the reading still shows the pre-reset value")

        app.aperture = 0.95
        let movedAperture = app.apertureLabel
        app.aperture = AppState.defaultControls.aperture
        XCTAssertNotEqual(app.apertureLabel, movedAperture)
    }

    // MARK: - Reset, undo, redo

    /// Every PRO control must survive the round trip through a snapshot.
    ///
    /// Aperture did not: it was missing from `ControlSnapshot` entirely, so
    /// reset left it wherever it was, undo and redo stepped straight over it,
    /// and the "already at the default" guard could not tell it had moved.
    /// This moves all five off their defaults at once and asserts the reset
    /// brings back every one — a control added to the plate but not to the
    /// snapshot fails here rather than on a device.
    func testResetReturnsEveryProControlToItsDefault() {
        let app = AppState()
        let defaults = AppState.defaultControls

        app.autoExposure = false
        app.aperture = 0.9
        app.iso = 0.9
        app.shutter = 0.9
        app.whiteBalance = 0.9
        app.exposureComp = 0.9

        app.resetControls()

        XCTAssertEqual(app.aperture, defaults.aperture, accuracy: 0.0001, "aperture")
        XCTAssertEqual(app.iso, defaults.iso, accuracy: 0.0001, "iso")
        XCTAssertEqual(app.shutter, defaults.shutter, accuracy: 0.0001, "shutter")
        XCTAssertEqual(app.whiteBalance, defaults.whiteBalance, accuracy: 0.0001, "white balance")
        XCTAssertEqual(app.exposureComp, defaults.exposureComp, accuracy: 0.0001, "exposure")
        XCTAssertEqual(app.autoExposure, defaults.autoExposure, "auto exposure")
    }

    /// The guard that makes reset a no-op has to see the same controls the
    /// reset does. With aperture outside the snapshot, moving only aperture
    /// left the app insisting it was "already at the default".
    func testMovingOnlyApertureCountsAsAChange() {
        let app = AppState()
        // Start from the defaults explicitly. A fresh AppState does *not* sit
        // there — init restores the persisted shoot settings and snaps them to
        // the nearest ladder position, so shutter and ISO land a hair off the
        // shipped numbers.
        app.apply(AppState.defaultControls)
        XCTAssertEqual(app.controls, AppState.defaultControls)

        app.aperture = 0.9
        XCTAssertNotEqual(app.controls, AppState.defaultControls,
                          "a moved aperture must register as a change")
    }

    /// Undo has to carry every control back too, not just the ones that happen
    /// to be in the struct.
    func testUndoRestoresApertureAlongWithTheRest() {
        let app = AppState()
        app.aperture = 0.75
        let before = app.aperture

        app.resetControls()
        XCTAssertNotEqual(app.aperture, before, accuracy: 0.0001)

        app.undoControls()
        XCTAssertEqual(app.aperture, before, accuracy: 0.0001,
                       "undo stepped over aperture")
    }

    // MARK: - Opening zoom

    /// The camera reports where its wide lens sits, and the app adopts that
    /// once — to move off the placeholder it starts on. It must not adopt it
    /// again later, because "later" includes every RAW capture: shooting a DNG
    /// swaps to the physical sensor and back, and republishing the lens list is
    /// part of coming back.
    ///
    /// The old guard asked `zoom == 1`, which is not a placeholder on a virtual
    /// back camera — the ultra-wide is factor 1.0 exactly. So a RAW frame shot
    /// at 0.5× came back at 1×.
    func testTheWideLensIsAdoptedOnceAndNeverReimposed() {
        let app = AppState()
        let wide: CGFloat = 2

        app.cameraManager.onLensesReady?(wide)
        XCTAssertEqual(app.zoom, Double(wide), "the placeholder should give way to the real wide factor")

        // The 0.5× lens on this body. Numerically the value the old sentinel
        // mistook for "not set yet".
        app.zoom = 1
        app.cameraManager.onLensesReady?(wide)
        XCTAssertEqual(app.zoom, 1, "a republished lens list must not move the lens the user chose")
    }

    // MARK: - Film strip

    func testSelectingFilmReachesTheRenderPipeline() {
        let app = AppState()
        for preset in FilmPreset.all {
            app.selectedFilm = preset
            XCTAssertEqual(app.cameraManager.currentSettings.filmID, preset.id)
        }
    }

    func testIntensitySliderReachesTheRenderPipeline() {
        let app = AppState()
        app.intensity = 0.25
        XCTAssertEqual(app.cameraManager.currentSettings.intensity, 0.25, accuracy: 0.001)
    }

    // MARK: - Manual controls

    func testISOSliderMapsToTheStopLadder() {
        let app = AppState()
        // Slider sits at the far right: the highest stop on the ladder.
        app.iso = 1.0
        XCTAssertEqual(app.isoValue, AppState.isoStops.last)
        XCTAssertEqual(app.cameraManager.currentSettings.iso, AppState.isoStops.last)

        app.iso = 0.0
        XCTAssertEqual(app.isoValue, AppState.isoStops.first)
        XCTAssertEqual(app.cameraManager.currentSettings.iso, AppState.isoStops.first)
    }

    func testShutterSliderMapsToTheStopLadder() {
        let app = AppState()
        app.shutter = 1.0
        XCTAssertEqual(app.shutterValue, AppState.shutterStops.last)
        XCTAssertEqual(
            app.cameraManager.currentSettings.shutterDenominator,
            AppState.shutterStops.last
        )
    }

    /// White balance now clicks between named lighting temperatures rather than
    /// sweeping continuously, so the dial reads round numbers at every stop.
    func testWhiteBalanceDialMapsToNamedTemperatures() {
        let app = AppState()
        app.whiteBalance = 0
        XCTAssertEqual(app.kelvinValue, Double(AppState.whiteBalanceStops.first!))
        XCTAssertEqual(app.cameraManager.currentSettings.kelvin, app.kelvinValue, accuracy: 0.001)

        app.whiteBalance = 1
        XCTAssertEqual(app.kelvinValue, Double(AppState.whiteBalanceStops.last!))
        XCTAssertEqual(app.cameraManager.currentSettings.kelvin, app.kelvinValue, accuracy: 0.001)
    }

    func testEveryWhiteBalanceStopIsAWholeHundredKelvin() {
        for stop in AppState.whiteBalanceStops {
            XCTAssertEqual(stop % 100, 0, "\(stop)K would render as an odd readout")
        }
    }

    func testExposureCompensationIsBipolarAroundZero() {
        let app = AppState()
        app.exposureComp = 0.5
        XCTAssertEqual(app.evValue, 0, accuracy: 0.001)
        XCTAssertEqual(app.cameraManager.currentSettings.ev, 0, accuracy: 0.001)

        app.exposureComp = 1.0
        XCTAssertGreaterThan(app.cameraManager.currentSettings.ev, 0)

        app.exposureComp = 0.0
        XCTAssertLessThan(app.cameraManager.currentSettings.ev, 0)
    }

    /// A viewfinder's job is to show the scene. Grain is a look you ask for, not
    /// something the camera does to you before you have chosen it.
    func testGrainIsOffUntilAskedFor() {
        XCTAssertFalse(AppState().grainOn)
    }

    // MARK: - Look toggles

    func testLookTogglesReachTheRenderPipeline() {
        let app = AppState()

        app.grainOn = true
        XCTAssertTrue(app.cameraManager.currentSettings.grain)
        app.grainOn = false
        XCTAssertFalse(app.cameraManager.currentSettings.grain)

        app.halationOn = true
        XCTAssertTrue(app.cameraManager.currentSettings.halation)

        app.vignetteOn = true
        XCTAssertTrue(app.cameraManager.currentSettings.vignette)

        app.focusPeaking = false
        XCTAssertFalse(app.cameraManager.currentSettings.focusPeaking)
    }

    // MARK: - Labels

    func testHUDLabelsTrackTheirControls() {
        let app = AppState()
        // Exposure is automatic by default, so the readouts say so until a dial is
        // taken off A. Reading the stops back requires opting into manual first.
        app.autoExposure = false
        app.iso = 1.0
        app.shutter = 1.0
        app.exposureComp = 0.5

        XCTAssertEqual(app.isoLabel, "ISO \(AppState.isoStops.last!)")
        XCTAssertEqual(app.shutterLabel, "1/\(AppState.shutterStops.last!)")
        XCTAssertEqual(app.exposureLabel, "+0.0 EV")
    }

    /// The default that stops the viewfinder sitting several stops under the
    /// stock camera indoors: the sensor meters the scene until told otherwise.
    func testExposureIsAutomaticUntilADialLeavesA() {
        let app = AppState()
        XCTAssertTrue(app.autoExposure)
        XCTAssertEqual(app.shutterLabel, "AUTO")
        XCTAssertEqual(app.isoLabel, "ISO A")
        XCTAssertTrue(app.cameraManager.currentSettings.autoExposure)

        // Index 0 is A on both ladders, so anything above it is manual.
        app.shutterIndex = 3
        XCTAssertFalse(app.autoExposure)
        XCTAssertFalse(app.cameraManager.currentSettings.autoExposure)
    }

    func testStopLadderNeverIndexesOutOfBounds() {
        let app = AppState()
        // Positions outside 0…1 arrive from drag gestures near the track edges.
        XCTAssertEqual(app.stop(AppState.isoStops, at: -5), AppState.isoStops.first)
        XCTAssertEqual(app.stop(AppState.isoStops, at: 5), AppState.isoStops.last)
    }

    // MARK: - Shutter, review, and the roll

    func testCaptureWithNoFrameExplainsItselfAndStaysPut() {
        let app = AppState()
        app.go(.viewfinder)
        app.capture()

        XCTAssertNil(app.capturedImage)
        XCTAssertEqual(app.screen, .viewfinder, "must not push an empty Review screen")
        XCTAssertNotNil(app.lastSaveMessage)
    }

    func testSavingWritesTheCurrentShootSettings() {
        let app = AppState()
        app.selectedFilm = FilmPreset.all.first { $0.id == "rust" }!
        app.iso = 1.0
        app.shutter = 1.0
        app.capturedImage = UIImage(systemName: "camera") ?? UIImage()

        app.saveCapturedPhoto()

        let settled = expectation(description: "gallery updated")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        let photo = app.gallery.photos.first
        XCTAssertEqual(photo?.filmID, "rust")
        XCTAssertEqual(photo?.iso, AppState.isoStops.last)
        XCTAssertEqual(photo?.shutterDenominator, AppState.shutterStops.last)
    }

    func testDeleteClearsTheFrameAndReturnsToTheViewfinder() {
        let app = AppState()
        app.capturedImage = UIImage(systemName: "camera") ?? UIImage()
        app.go(.review)

        app.deleteCapture()

        XCTAssertNil(app.capturedImage)
        XCTAssertEqual(app.screen, .viewfinder)
    }

    func testKeepingLeavesTheFrameOnTheRoll() {
        let app = AppState()
        app.capturedImage = UIImage(systemName: "camera") ?? UIImage()
        app.saveCapturedPhoto()
        drain()

        let before = app.gallery.photos.count
        app.keepCapture()
        drain()

        XCTAssertEqual(app.gallery.photos.count, before, "keeping must not remove anything")
        XCTAssertNil(app.capturedImage)
        XCTAssertEqual(app.screen, .viewfinder)
    }

    /// The shutter writes to the roll, and Review's delete has to take back
    /// *that* frame. Reading `photos.first` right after `addPhoto` returned the
    /// previous photo, because the insert hops to the main queue first — so
    /// deleting a rejected shot removed the one before it.
    ///
    /// Removal itself now goes through Apple Photos and lands only once Photos
    /// confirms it, which these unmirrored frames never reach — so what is
    /// pinned here is the half that bug lived in: whichever frame delete aims
    /// at, the *earlier* one must survive. It did not, once.
    func testDeletingACaptureNeverTakesTheFrameBefore() {
        let app = AppState()

        app.capturedImage = UIImage(systemName: "camera") ?? UIImage()
        app.saveCapturedPhoto()
        drain()
        guard let earlier = app.gallery.photos.first?.id else { return XCTFail("no first frame") }

        app.capturedImage = UIImage(systemName: "camera.fill") ?? UIImage()
        app.saveCapturedPhoto()
        drain()
        XCTAssertEqual(app.gallery.photos.count, 2)

        app.deleteCapture()
        drain()

        XCTAssertTrue(app.gallery.photos.contains { $0.id == earlier },
                      "delete reached back and took the previous frame")
    }

    /// Review has to hand the viewfinder back either way. Leaving the rejected
    /// frame on screen because Photos would not take it strands the user on a
    /// review screen with no way forward.
    func testDeletingACaptureReturnsToTheViewfinderEvenWhenPhotosCannotDelete() {
        let app = AppState()

        app.capturedImage = UIImage(systemName: "camera") ?? UIImage()
        app.saveCapturedPhoto()
        drain()

        app.deleteCapture()
        drain()

        XCTAssertNil(app.capturedImage)
        XCTAssertEqual(app.screen, .viewfinder)
    }

    private func drain() {
        let settled = expectation(description: "main queue drained")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }

    func testSavingNothingIsANoOp() {
        let app = AppState()
        app.capturedImage = nil
        app.saveCapturedPhoto()

        let settled = expectation(description: "gallery settled")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        XCTAssertTrue(app.gallery.photos.isEmpty)
    }

    // MARK: - Restore

    func testLaunchAdoptsThePersistedFilmAndExposure() {
        let first = AppState()
        first.selectedFilm = FilmPreset.all.first { $0.id == "mono" }!
        first.iso = 1.0

        // Relaunch.
        let second = AppState()
        XCTAssertEqual(second.selectedFilm.id, "mono")
        XCTAssertEqual(second.isoValue, AppState.isoStops.last)
        XCTAssertEqual(second.cameraManager.currentSettings.filmID, "mono")
    }
}

// MARK: - Pro mode

final class ProModeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Pref.proMode)
    }

    @MainActor
    func testManualControlsAreHiddenUntilAskedFor() {
        let app = AppState()
        XCTAssertFalse(app.proMode, "a camera should open ready to shoot, not ready to be configured")
        XCTAssertTrue(app.autoExposure)
        XCTAssertTrue(app.autoFocus)
    }

    /// The failure this guards against: a manual shutter still running behind a
    /// control that is no longer on screen, with no way to see or undo it.
    @MainActor
    func testLeavingProModeHandsTheCameraBack() {
        let app = AppState()
        app.proMode = true
        app.shutterIndex = 5
        app.focusIndex = 3
        app.metering = "LOCK"
        XCTAssertFalse(app.autoExposure)
        XCTAssertFalse(app.autoFocus)

        app.proMode = false
        XCTAssertTrue(app.autoExposure)
        XCTAssertTrue(app.autoFocus)
        XCTAssertEqual(app.metering, "MATRIX")
        XCTAssertTrue(app.cameraManager.currentSettings.autoExposure)
        XCTAssertTrue(app.cameraManager.currentSettings.autoFocus)
    }

    @MainActor
    func testProModeIsRemembered() {
        let app = AppState()
        app.proMode = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Pref.proMode))
        XCTAssertTrue(AppState().proMode, "a fresh launch should find it still on")
    }

    @MainActor
    func testResetReturnsEveryManualControlToDefault() {
        let app = AppState()
        app.proMode = true
        app.shutterIndex = 6
        app.isoIndex = 2
        app.whiteBalanceIndex = 0
        app.exposureIndex = 9
        app.focusIndex = 2
        app.metering = "SPOT"
        XCTAssertNotEqual(app.controls, AppState.defaultControls)

        app.resetControls()
        XCTAssertEqual(app.controls, AppState.defaultControls)
        XCTAssertTrue(app.canUndo, "reset has to be recoverable in one tap")

        app.undoControls()
        XCTAssertEqual(app.metering, "SPOT", "undo must bring the whole setup back")
    }
}
