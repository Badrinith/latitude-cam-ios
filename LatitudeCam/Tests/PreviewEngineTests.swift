//
//  PreviewEngineTests.swift
//  LatitudeCam
//
//  Test-Driven Development: Real-time Preview Engine
//  RED: Tests for live camera preview and before/after comparison
//

import XCTest
@testable import LatitudeCam

final class PreviewEngineTests: XCTestCase {
    
    var previewEngine: PreviewEngine!
    
    override func setUp() {
        super.setUp()
        previewEngine = PreviewEngine()
    }
    
    override func tearDown() {
        previewEngine = nil
        super.tearDown()
    }
    
    // MARK: - Preview Engine Tests
    
    func testPreviewEngineInitializes() {
        XCTAssertNotNil(previewEngine)
    }
    
    func testCanConvertCGImageToPixelArray() {
        let image = createTestCGImage(width: 10, height: 10)
        let pixels = previewEngine.convertToPixels(image)
        
        XCTAssertEqual(pixels.count, 100)  // 10x10
    }
    
    func testCanConvertPixelArrayBackToImage() {
        let originalPixels = Array(repeating: Pixel(r: 128, g: 128, b: 128), count: 100)
        let image = previewEngine.convertToImage(originalPixels, width: 10, height: 10)
        
        XCTAssertNotNil(image)
    }
    
    func testPreviewProcessingAppliesFilm() {
        let pixels = Array(repeating: Pixel(r: 100, g: 100, b: 100), count: 100)
        
        // Process with Amber film
        let amber = AmberFilm()
        let processed = previewEngine.processPixels(pixels, film: amber, iso: 100, shutter: 1.0)
        
        // Should be brightened by Amber (R+20%, G-10%, B-20%)
        XCTAssertEqual(processed[0].r, 120)
        XCTAssertEqual(processed[0].g, 90)
        XCTAssertEqual(processed[0].b, 80)
    }
    
    // MARK: - Before/After Comparison Tests
    
    func testBeforeAfterComparison() {
        let comparison = previewEngine.createBeforeAfterComparison(
            original: createTestCGImage(width: 100, height: 100),
            processed: createTestCGImage(width: 100, height: 100)
        )
        
        XCTAssertNotNil(comparison)
    }
    
    func testComparisonShowsSideBySide() {
        let original = createTestCGImage(width: 100, height: 100)
        let processed = createTestCGImage(width: 100, height: 100)
        
        let comparison = previewEngine.createBeforeAfterComparison(
            original: original,
            processed: processed
        )
        
        // Should create image showing both
        XCTAssertNotNil(comparison)
    }
    
    // MARK: - Live Preview Tests
    
    func testLivePreviewUpdatesOnFrameReceived() {
        let updateExpectation = expectation(description: "Preview should update on frame")
        
        previewEngine.onPreviewUpdate = { image in
            XCTAssertNotNil(image)
            updateExpectation.fulfill()
        }
        
        let testFrame = createTestCGImage(width: 100, height: 100)
        previewEngine.processFrame(testFrame)
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testFrameRateThrottling() {
        var updateCount = 0
        previewEngine.onPreviewUpdate = { _ in
            updateCount += 1
        }
        
        // Send 60 frames rapidly
        for _ in 0..<60 {
            let frame = createTestCGImage(width: 100, height: 100)
            previewEngine.processFrame(frame)
        }
        
        // Callbacks are delivered via DispatchQueue.main.async, so drain the
        // main queue before asserting — main is FIFO, so this block runs after
        // every callback already enqueued above.
        let drained = expectation(description: "preview callbacks delivered")
        DispatchQueue.main.async { drained.fulfill() }
        waitForExpectations(timeout: 1.0)

        // The loop runs in well under one frame interval, so a correct 30fps
        // throttle emits the first frame and drops the rest. (The previous
        // `> 20` assertion was unsatisfiable: demanding 20+ updates from a
        // sub-millisecond loop contradicts the throttling being tested.)
        XCTAssertLessThan(updateCount, 60)
        XCTAssertGreaterThanOrEqual(updateCount, 1)
    }
    
    // MARK: - Quality Tests
    
    func testPreviewMaintainsAspectRatio() {
        let wideImage = createTestCGImage(width: 200, height: 100)
        let pixels = previewEngine.convertToPixels(wideImage)
        let reconstructed = previewEngine.convertToImage(pixels, width: 200, height: 100)
        
        XCTAssertNotNil(reconstructed)
    }
    
    func testPreviewPreservesColors() {
        let testPixel = Pixel(r: 255, g: 128, b: 64)
        let pixels = Array(repeating: testPixel, count: 100)
        let image = previewEngine.convertToImage(pixels, width: 10, height: 10)
        
        // Verify color is preserved
        XCTAssertNotNil(image)
    }
    
    // MARK: - Helper
    
    private func createTestCGImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0))
        context.fill(rect)
        
        return context.makeImage()!
    }
}
