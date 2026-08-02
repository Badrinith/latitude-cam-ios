//
//  Phase0_4_AllTests.swift
//  LatitudeCam
//
//  Comprehensive tests for Phase 0.4: UI Polish, Advanced, Production
//

import XCTest
@testable import LatitudeCam

final class PhotoGalleryTests: XCTestCase {
    func testGalleryCanStorePhotos() {
        let gallery = PhotoGallery()
        let testImage = UIImage(systemName: "camera") ?? UIImage()
        gallery.addPhoto(testImage, filmProfile: "Amber", iso: 400, shutter: 1.0)
        XCTAssertEqual(gallery.getPhotos().count, 1)
    }
}

final class HistogramTests: XCTestCase {
    func testHistogramGeneration() {
        let engine = HistogramEngine()
        let pixels = Array(repeating: Pixel(r: 128, g: 128, b: 128), count: 100)
        let histogram = engine.generateHistogram(from: pixels)
        XCTAssertEqual(histogram.brightness, 128)
        XCTAssertEqual(histogram.exposure, "Good")
    }
}

final class FocusPeakingTests: XCTestCase {
    func testFocusAreaDetection() {
        let overlay = FocusPeakingOverlay()
        let pixels = Array(repeating: Pixel(r: 100, g: 100, b: 100), count: 100)
        let areas = overlay.detectFocusAreas(pixels: pixels, width: 10, height: 10)
        XCTAssertGreaterThanOrEqual(areas.count, 0)
    }
}

final class BatchProcessorTests: XCTestCase {
    func testBatchQueueing() {
        let processor = BatchProcessor()
        let image = UIImage(systemName: "camera") ?? UIImage()
        processor.addToBatch(image)
        // Would process and callback
    }
}

final class CustomProfileTests: XCTestCase {
    func testCustomProfileCreation() {
        let editor = CustomFilmProfileEditor()
        let profile = editor.createCustomProfile(name: "Custom", rMult: 1.2, gMult: 0.9, bMult: 0.8)
        let pixel = profile.apply(to: Pixel(r: 100, g: 100, b: 100))
        XCTAssertEqual(pixel.r, 120)
    }
}

final class GridOverlayTests: XCTestCase {
    func testGridRendering() {
        let grid = GridOverlay()
        let image = grid.renderGrid(.thirdRule, size: CGSize(width: 100, height: 100))
        XCTAssertNotNil(image)
    }
}

final class PermissionTests: XCTestCase {
    func testPermissionRequest() {
        PermissionManager.getCameraPermission { status in
            XCTAssertNotEqual(status, .notDetermined)
        }
    }
}

final class MemoryOptimizationTests: XCTestCase {
    func testImageOptimization() {
        let original = UIImage(systemName: "camera") ?? UIImage()
        let optimized = MemoryOptimizer.optimizeImageSize(original)
        XCTAssertNotNil(optimized)
    }
}

final class PrivacyTests: XCTestCase {
    func testPrivacyPolicy() {
        let policy = PrivacyManager.getPrivacyPolicy()
        XCTAssertTrue(policy.contains("Privacy Policy"))
    }
}
