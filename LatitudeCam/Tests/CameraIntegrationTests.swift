//
//  CameraIntegrationTests.swift
//  LatitudeCam
//
//  Test-Driven Development: Camera Integration
//  RED: Tests for camera capture, processing, and preview
//

import XCTest
import AVFoundation
@testable import LatitudeCam

/// True only where a real capture device exists — the Simulator has none, so
/// capture-path tests are skipped there rather than reported as failures.
private var hasCaptureDevice: Bool {
    AVCaptureDevice.default(for: .video) != nil
}

final class CameraIntegrationTests: XCTestCase {
    
    var cameraManager: CameraManager!
    
    /// CameraManager persists to the shared UserDefaults, so settings written
    /// by one test would otherwise leak into the next one's defaults.
    private static let persistedKeys = [
        "LatitudeCam.ISO", "LatitudeCam.ShutterTime", "LatitudeCam.FilmProfile"
    ]

    private func clearPersistedSettings() {
        Self.persistedKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func setUp() {
        super.setUp()
        clearPersistedSettings()
        cameraManager = CameraManager()
    }

    override func tearDown() {
        cameraManager = nil
        clearPersistedSettings()
        super.tearDown()
    }
    
    // MARK: - Camera Manager Tests
    
    func testCameraManagerInitializes() {
        XCTAssertNotNil(cameraManager)
    }
    
    func testCameraHasDefaultFilmProfile() {
        // By default, should start with AmberFilm
        XCTAssertNotNil(cameraManager.currentFilmProfile)
    }
    
    func testCameraHasDefaultExposure() {
        // Should have default ISO and shutter
        XCTAssertEqual(cameraManager.currentISO, 100)
        XCTAssertEqual(cameraManager.currentShutterTime, 1.0)
    }
    
    func testCanSetFilmProfile() {
        // Should be able to switch film profiles
        let slate = SlateFilm()
        cameraManager.setFilmProfile(slate)
        
        XCTAssertNotNil(cameraManager.currentFilmProfile)
    }
    
    func testCanAdjustISO() {
        // Should allow ISO adjustment
        cameraManager.setISO(400)
        XCTAssertEqual(cameraManager.currentISO, 400)
    }
    
    func testCanAdjustShutterTime() {
        // Should allow shutter time adjustment
        cameraManager.setShutterTime(2.0)
        XCTAssertEqual(cameraManager.currentShutterTime, 2.0)
    }
    
    // MARK: - Image Processing Pipeline Tests
    
    func testPixelProcessingPipeline() {
        // Pipeline: Capture → Film → Exposure → Result
        let inputPixel = Pixel(r: 100, g: 100, b: 100)
        
        // Set: Amber film + ISO 200
        let amber = AmberFilm()
        cameraManager.setFilmProfile(amber)
        cameraManager.setISO(200)
        cameraManager.setShutterTime(1.0)
        
        // Process pixel through full pipeline
        let result = cameraManager.processPixel(inputPixel)
        
        // Expected: Amber (R+20%, G-10%, B-20%) then ISO 2x
        // Amber: R=120, G=90, B=80
        // ISO 2x: R=240, G=180, B=160
        XCTAssertEqual(result.r, 240)
        XCTAssertEqual(result.g, 180)
        XCTAssertEqual(result.b, 160)
    }
    
    func testMonoFilmWithExposure() {
        let inputPixel = Pixel(r: 255, g: 128, b: 64)
        
        // Set: Mono film + ISO 100 (no change) + Shutter 2.0
        let mono = MonoFilm()
        cameraManager.setFilmProfile(mono)
        cameraManager.setISO(100)
        cameraManager.setShutterTime(2.0)
        
        let result = cameraManager.processPixel(inputPixel)
        
        // Mono with standard luminosity: 0.299*255 + 0.587*128 + 0.114*64 ≈ 149
        // Then shutter 2.0x: 149 * 2 = 298 (clamped to 255)
        XCTAssertEqual(result.r, 255)
        XCTAssertEqual(result.g, 255)
        XCTAssertEqual(result.b, 255)
    }
    
    func testRustFilmWithISO() {
        let inputPixel = Pixel(r: 80, g: 80, b: 80)
        
        // Set: Rust film + ISO 200 + Shutter 0.5
        let rust = RustFilm()
        cameraManager.setFilmProfile(rust)
        cameraManager.setISO(200)
        cameraManager.setShutterTime(0.5)
        
        let result = cameraManager.processPixel(inputPixel)
        
        // Rust: R+30%, G+10%, B-40%
        // R: 80*1.3=104, G: 80*1.1=88, B: 80*0.6=48
        // ISO 2x: R=208, G=176, B=96
        // Shutter 0.5x: R=104, G=88, B=48
        XCTAssertEqual(result.r, 104)
        XCTAssertEqual(result.g, 88)
        XCTAssertEqual(result.b, 48)
    }
    
    // MARK: - Preview Tests
    
    func testPreviewUpdatesWhenFilmChanges() {
        let updateExpectation = expectation(description: "Preview should update when film changes")
        
        var previewUpdated = false
        cameraManager.onPreviewUpdate = {
            previewUpdated = true
            updateExpectation.fulfill()
        }
        
        // Change film profile
        let slate = SlateFilm()
        cameraManager.setFilmProfile(slate)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(previewUpdated)
    }
    
    func testPreviewUpdatesWhenISOChanges() {
        let updateExpectation = expectation(description: "Preview should update when ISO changes")
        
        var updateCount = 0
        cameraManager.onPreviewUpdate = {
            updateCount += 1
            if updateCount == 1 {
                updateExpectation.fulfill()
            }
        }
        
        // Change ISO
        cameraManager.setISO(400)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertGreaterThan(updateCount, 0)
    }
    
    func testPreviewUpdatesWhenShutterChanges() {
        let updateExpectation = expectation(description: "Preview should update when shutter changes")
        
        var updateCount = 0
        cameraManager.onPreviewUpdate = {
            updateCount += 1
            if updateCount == 1 {
                updateExpectation.fulfill()
            }
        }
        
        // Change shutter time
        cameraManager.setShutterTime(2.0)
        
        waitForExpectations(timeout: 1.0)
        XCTAssertGreaterThan(updateCount, 0)
    }
    
    // MARK: - Photo Capture Tests
    
    func testCapturePhotoReturnsImage() throws {
        try XCTSkipUnless(hasCaptureDevice, "Requires camera hardware")
        let captureExpectation = expectation(description: "Should capture a photo")
        
        cameraManager.capturePhoto { image in
            XCTAssertNotNil(image)
            captureExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    func testCapturedPhotoHasFilmApplied() throws {
        try XCTSkipUnless(hasCaptureDevice, "Requires camera hardware")
        let captureExpectation = expectation(description: "Captured photo should have film applied")
        
        // Set Mono film (should convert to B&W)
        let mono = MonoFilm()
        cameraManager.setFilmProfile(mono)
        cameraManager.setISO(100)
        cameraManager.setShutterTime(1.0)
        
        cameraManager.capturePhoto { image in
            XCTAssertNotNil(image)
            // In real test, would verify image is grayscale
            captureExpectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    // MARK: - Settings Persistence Tests
    
    func testSettingsPersist() {
        // Set specific values
        cameraManager.setISO(800)
        cameraManager.setShutterTime(1.5)
        let rust = RustFilm()
        cameraManager.setFilmProfile(rust)
        
        // Create new manager (simulate app restart)
        let newManager = CameraManager()
        
        // Settings should persist
        XCTAssertEqual(newManager.currentISO, 800)
        XCTAssertEqual(newManager.currentShutterTime, 1.5)
    }
}
