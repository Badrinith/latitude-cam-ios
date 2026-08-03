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

    // MARK: - Look toggles

    func testLookTogglesReachTheRenderPipeline() {
        let app = AppState()

        app.grainOn = false
        XCTAssertFalse(app.cameraManager.currentSettings.grain)
        app.grainOn = true
        XCTAssertTrue(app.cameraManager.currentSettings.grain)

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
        app.iso = 1.0
        app.shutter = 1.0
        app.exposureComp = 0.5

        XCTAssertEqual(app.isoLabel, "ISO \(AppState.isoStops.last!)")
        XCTAssertEqual(app.shutterLabel, "1/\(AppState.shutterStops.last!)")
        XCTAssertEqual(app.exposureLabel, "+0.0 EV")
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

    func testDiscardClearsTheFrameAndReturnsToTheViewfinder() {
        let app = AppState()
        app.capturedImage = UIImage(systemName: "camera") ?? UIImage()
        app.go(.review)

        app.discardCapture()

        XCTAssertNil(app.capturedImage)
        XCTAssertEqual(app.screen, .viewfinder)
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
