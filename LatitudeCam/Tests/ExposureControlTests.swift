//
//  ExposureControlTests.swift
//  LatitudeCam
//
//  Test-Driven Development: Exposure Control
//  RED: Tests that will fail until we implement exposure adjustment
//

import XCTest
@testable import LatitudeCam

final class ExposureControlTests: XCTestCase {
    
    // MARK: - ISO Control Tests
    
    func testISOControlExists() {
        let iso = ISOControl(baseISO: 100)
        XCTAssertNotNil(iso)
    }
    
    func testISO100HasNoAdjustment() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let iso = ISOControl(baseISO: 100)
        let result = iso.adjust(pixel, toISO: 100)
        
        // Base ISO should not change pixel
        XCTAssertEqual(result.r, pixel.r)
        XCTAssertEqual(result.g, pixel.g)
        XCTAssertEqual(result.b, pixel.b)
    }
    
    func testISO200DoublesLight() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let iso = ISOControl(baseISO: 100)
        let result = iso.adjust(pixel, toISO: 200)
        
        // ISO 200 is 2x more sensitive than ISO 100
        XCTAssertEqual(result.r, 200)
        XCTAssertEqual(result.g, 200)
        XCTAssertEqual(result.b, 200)
    }
    
    func testISO400QuadruplesLight() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let iso = ISOControl(baseISO: 100)
        let result = iso.adjust(pixel, toISO: 400)
        
        // ISO 400 is 4x more sensitive than ISO 100
        XCTAssertEqual(result.r, 255)  // Clamped to 400, but max is 255
        XCTAssertEqual(result.g, 255)
        XCTAssertEqual(result.b, 255)
    }
    
    func testISO50HalvesLight() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let iso = ISOControl(baseISO: 100)
        let result = iso.adjust(pixel, toISO: 50)
        
        // ISO 50 is 0.5x sensitivity
        XCTAssertEqual(result.r, 50)
        XCTAssertEqual(result.g, 50)
        XCTAssertEqual(result.b, 50)
    }
    
    func testISOPreservesColorBalance() {
        // Needs 2x headroom: a channel that clips at 255 cannot preserve hue.
        let pixel = Pixel(r: 120, g: 60, b: 30)  // Orange
        let iso = ISOControl(baseISO: 100)
        let result = iso.adjust(pixel, toISO: 200)
        
        // ISO should brighten all channels equally (preserve hue)
        let ratio_r_g = Double(result.r) / Double(result.g)
        let ratio_g_b = Double(result.g) / Double(result.b)
        
        let original_ratio_r_g = Double(pixel.r) / Double(pixel.g)
        let original_ratio_g_b = Double(pixel.g) / Double(pixel.b)
        
        // Ratios should be approximately the same (within rounding)
        XCTAssertEqual(ratio_r_g, original_ratio_r_g, accuracy: 0.1)
        XCTAssertEqual(ratio_g_b, original_ratio_g_b, accuracy: 0.1)
    }
    
    // MARK: - Shutter Speed Tests
    
    func testShutterControlExists() {
        let shutter = ShutterControl(baseShutter: 1.0)
        XCTAssertNotNil(shutter)
    }
    
    func testShutterBaseValueNoAdjustment() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let shutter = ShutterControl(baseShutter: 1.0)
        let result = shutter.adjust(pixel, exposureTime: 1.0)
        
        // Base shutter (1.0) should not change pixel
        XCTAssertEqual(result.r, pixel.r)
        XCTAssertEqual(result.g, pixel.g)
        XCTAssertEqual(result.b, pixel.b)
    }
    
    func testShutterDoubleExposureTime() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let shutter = ShutterControl(baseShutter: 1.0)
        let result = shutter.adjust(pixel, exposureTime: 2.0)
        
        // 2x exposure time = 2x more light
        XCTAssertEqual(result.r, 200)
        XCTAssertEqual(result.g, 200)
        XCTAssertEqual(result.b, 200)
    }
    
    func testShutterHalfExposureTime() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let shutter = ShutterControl(baseShutter: 1.0)
        let result = shutter.adjust(pixel, exposureTime: 0.5)
        
        // 0.5x exposure = 0.5x light
        XCTAssertEqual(result.r, 50)
        XCTAssertEqual(result.g, 50)
        XCTAssertEqual(result.b, 50)
    }
    
    func testShutterPreservesColorBalance() {
        // Needs 2x headroom: a channel that clips at 255 cannot preserve hue.
        let pixel = Pixel(r: 120, g: 60, b: 30)  // Orange
        let shutter = ShutterControl(baseShutter: 1.0)
        let result = shutter.adjust(pixel, exposureTime: 2.0)
        
        // Color ratios should be preserved
        let ratio_r_g = Double(result.r) / Double(result.g)
        let ratio_g_b = Double(result.g) / Double(result.b)
        
        let original_ratio_r_g = Double(pixel.r) / Double(pixel.g)
        let original_ratio_g_b = Double(pixel.g) / Double(pixel.b)
        
        XCTAssertEqual(ratio_r_g, original_ratio_r_g, accuracy: 0.1)
        XCTAssertEqual(ratio_g_b, original_ratio_g_b, accuracy: 0.1)
    }
    
    // MARK: - Combined Exposure Tests
    
    func testISOAndShutterCombine() {
        let pixel = Pixel(r: 50, g: 50, b: 50)
        
        // ISO 200 (2x) + Shutter 2.0 (2x) = 4x total
        let iso = ISOControl(baseISO: 100)
        let step1 = iso.adjust(pixel, toISO: 200)  // 100
        
        let shutter = ShutterControl(baseShutter: 1.0)
        let step2 = shutter.adjust(step1, exposureTime: 2.0)  // 200
        
        XCTAssertEqual(step2.r, 200)
        XCTAssertEqual(step2.g, 200)
        XCTAssertEqual(step2.b, 200)
    }
    
    func testCombinedExposurePreservesColor() {
        // ISO 2x then shutter 2x = 4x total, so this needs 4x headroom.
        let pixel = Pixel(r: 60, g: 30, b: 15)
        
        let iso = ISOControl(baseISO: 100)
        let step1 = iso.adjust(pixel, toISO: 200)
        
        let shutter = ShutterControl(baseShutter: 1.0)
        let step2 = shutter.adjust(step1, exposureTime: 2.0)
        
        // Final ratios should match original
        let ratio_r_g = Double(step2.r) / Double(step2.g)
        let ratio_g_b = Double(step2.g) / Double(step2.b)
        
        let original_ratio_r_g = Double(pixel.r) / Double(pixel.g)
        let original_ratio_g_b = Double(pixel.g) / Double(pixel.b)
        
        XCTAssertEqual(ratio_r_g, original_ratio_r_g, accuracy: 0.1)
        XCTAssertEqual(ratio_g_b, original_ratio_g_b, accuracy: 0.1)
    }
}
