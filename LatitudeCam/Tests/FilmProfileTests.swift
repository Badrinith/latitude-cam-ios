//
//  FilmProfileTests.swift
//  LatitudeCam
//
//  Test-Driven Development: Film Profiles
//  RED: Tests that will fail until we implement the film profiles
//

import XCTest
@testable import LatitudeCam

final class FilmProfileTests: XCTestCase {
    
    // MARK: - Pixel Model Tests
    
    func testPixelInitialization() {
        let pixel = Pixel(r: 100, g: 150, b: 200)
        XCTAssertEqual(pixel.r, 100)
        XCTAssertEqual(pixel.g, 150)
        XCTAssertEqual(pixel.b, 200)
    }
    
    func testPixelClampsToValidRange() {
        let tooHigh = Pixel(r: 300, g: 150, b: 50)
        let tooLow = Pixel(r: -10, g: 150, b: 50)
        
        XCTAssertEqual(tooHigh.r, 255)
        XCTAssertEqual(tooLow.r, 0)
    }
    
    // MARK: - Amber Film Tests
    
    func testAmberFilmIncreasesRed() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let amber = AmberFilm()
        let result = amber.apply(to: pixel)
        
        XCTAssertGreaterThan(result.r, pixel.r, "Amber should increase red channel")
    }
    
    func testAmberFilmDecreasesBlue() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let amber = AmberFilm()
        let result = amber.apply(to: pixel)
        
        XCTAssertLessThan(result.b, pixel.b, "Amber should decrease blue channel")
    }
    
    func testAmberFilmExactAdjustment() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let amber = AmberFilm()
        let result = amber.apply(to: pixel)
        
        XCTAssertEqual(result.r, 120, "Red: +20%")
        XCTAssertEqual(result.g, 90, "Green: -10%")
        XCTAssertEqual(result.b, 80, "Blue: -20%")
    }
    
    // MARK: - Slate Film Tests
    
    func testSlateFilmDesaturates() {
        let pixel = Pixel(r: 200, g: 100, b: 50)
        let slate = SlateFilm()
        let result = slate.apply(to: pixel)
        
        XCTAssertLessThan(result.r, pixel.r, "Slate should desaturate reds")
    }
    
    func testSlateFilmAddsCoolTone() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let slate = SlateFilm()
        let result = slate.apply(to: pixel)
        
        XCTAssertGreaterThan(result.b, pixel.b, "Slate should add cool (blue) tone")
    }
    
    func testSlateFilmExactAdjustment() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let slate = SlateFilm()
        let result = slate.apply(to: pixel)
        
        XCTAssertEqual(result.r, 80, "Red: -20%")
        XCTAssertEqual(result.g, 80, "Green: -20%")
        XCTAssertEqual(result.b, 120, "Blue: +20%")
    }
    
    // MARK: - Rust Film Tests
    
    func testRustFilmAddsWarmth() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let rust = RustFilm()
        let result = rust.apply(to: pixel)
        
        XCTAssertGreaterThan(result.r, pixel.r, "Rust should increase red for warmth")
    }
    
    func testRustFilmReducesBlue() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let rust = RustFilm()
        let result = rust.apply(to: pixel)
        
        XCTAssertLessThan(result.b, pixel.b, "Rust should reduce blue")
    }
    
    func testRustFilmExactAdjustment() {
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let rust = RustFilm()
        let result = rust.apply(to: pixel)
        
        XCTAssertEqual(result.r, 130, "Red: +30%")
        XCTAssertEqual(result.g, 110, "Green: +10%")
        XCTAssertEqual(result.b, 60, "Blue: -40%")
    }
    
    // MARK: - Mono Film Tests
    
    func testMonoConvertsToGrayscale() {
        let pixel = Pixel(r: 200, g: 100, b: 50)
        let mono = MonoFilm()
        let result = mono.apply(to: pixel)
        
        XCTAssertEqual(result.r, result.g, "Mono: R should equal G")
        XCTAssertEqual(result.g, result.b, "Mono: G should equal B")
    }
    
    func testMonoUsesProperLuminosity() {
        // Standard luminosity: 0.299*R + 0.587*G + 0.114*B
        let pixel = Pixel(r: 100, g: 100, b: 100)
        let mono = MonoFilm()
        let result = mono.apply(to: pixel)
        
        XCTAssertEqual(result.r, 100, "Mono of equal channels should preserve value")
    }
    
    func testMonoWithDifferentChannels() {
        let pixel = Pixel(r: 255, g: 0, b: 0) // Pure red
        let mono = MonoFilm()
        let result = mono.apply(to: pixel)
        
        // Using luminosity: 0.299*255 = 76
        XCTAssertEqual(result.r, 76)
        XCTAssertEqual(result.g, 76)
        XCTAssertEqual(result.b, 76)
    }
}
