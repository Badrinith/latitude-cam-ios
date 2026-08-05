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
    func testDeletingACaptureRemovesThatFrameAndNotTheOneBefore() {
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

        XCTAssertEqual(app.gallery.photos.count, 1)
        XCTAssertEqual(app.gallery.photos.first?.id, earlier, "deleted the wrong frame")
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
