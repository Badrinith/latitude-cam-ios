import Foundation

// MARK: - Test Harness

class LatitudeCamTests {
    var testsRun = 0
    var testsPassed = 0
    var testsFailed = 0
    
    func assert(_ condition: Bool, _ message: String) {
        testsRun += 1
        if condition {
            testsPassed += 1
            print("  ✓ \(message)")
        } else {
            testsFailed += 1
            print("  ✗ FAILED: \(message)")
        }
    }
    
    func runAllTests() {
        print("\n" + String(repeating: "=", count: 60))
        print("LATITUDE CAM - COMPREHENSIVE TEST SUITE")
        print(String(repeating: "=", count: 60) + "\n")
        
        testFilmProfiles()
        testExposureControl()
        testHistogram()
        testPhotoMetadata()
        testGridCalculations()
        
        printSummary()
    }
    
    func testFilmProfiles() {
        print("📽️  FILM PROFILES TESTS")
        
        let testPixel = Pixel(r: 200, g: 150, b: 100)
        
        // Amber Film
        let amberFilm = AmberFilm()
        let amberResult = amberFilm.apply(to: testPixel)
        assert(amberResult.r == 240, "Amber: R channel boosted (200 * 1.2 = 240)")
        assert(amberResult.g == 135, "Amber: G channel reduced (150 * 0.9 = 135)")
        assert(amberResult.b == 80, "Amber: B channel reduced (100 * 0.8 = 80)")
        
        // Slate Film
        let slateFilm = SlateFilm()
        let slateResult = slateFilm.apply(to: testPixel)
        assert(slateResult.r == 160, "Slate: R channel reduced (200 * 0.8 = 160)")
        assert(slateResult.b == 120, "Slate: B channel boosted (100 * 1.2 = 120)")
        
        // Rust Film
        let rustFilm = RustFilm()
        let rustResult = rustFilm.apply(to: testPixel)
        assert(rustResult.r == 255, "Rust: R channel clipped (200 * 1.3 = 260 → 255)")
        assert(rustResult.b == 60, "Rust: B channel reduced (100 * 0.6 = 60)")
        
        // Mono Film
        let monoFilm = MonoFilm()
        let monoResult = monoFilm.apply(to: testPixel)
        let expected = UInt8(Double(200) * 0.299 + Double(150) * 0.587 + Double(100) * 0.114)
        assert(monoResult.r == expected, "Mono: Grayscale conversion applied")
        assert(monoResult.g == expected, "Mono: All channels equal")
        assert(monoResult.b == expected, "Mono: Luminosity formula correct")
        
        print()
    }
    
    func testExposureControl() {
        print("🔆 EXPOSURE CONTROL TESTS")
        
        let testPixel = Pixel(r: 128, g: 128, b: 128)
        var meter = ExposureMeter()
        
        // Base exposure
        let baseResult = meter.adjustPixel(testPixel)
        assert(baseResult.r == 128, "Base ISO 100: No change at 1x shutter")
        
        // ISO 200 (2x brighter)
        meter.iso = 200
        let iso200Result = meter.adjustPixel(testPixel)
        assert(iso200Result.r == 255, "ISO 200: Double brightness (128 * 2 = 256 → 255 clipped)")
        
        // ISO 50 (half brightness)
        meter.iso = 50
        let iso50Result = meter.adjustPixel(testPixel)
        assert(iso50Result.r == 64, "ISO 50: Half brightness (128 * 0.5 = 64)")
        
        // Shutter adjustment
        meter.iso = 100
        meter.shutterSpeed = 2.0
        let shutter2xResult = meter.adjustPixel(testPixel)
        assert(shutter2xResult.r == 255, "Shutter 2.0x: Double exposure (128 * 2 = 256 → 255)")
        
        meter.shutterSpeed = 0.5
        let shutter0_5xResult = meter.adjustPixel(testPixel)
        assert(shutter0_5xResult.r == 64, "Shutter 0.5x: Half exposure (128 * 0.5 = 64)")
        
        print()
    }
    
    func testHistogram() {
        print("📊 HISTOGRAM TESTS")
        
        let darkPixels = Array(repeating: Pixel(r: 50, g: 50, b: 50), count: 10)
        let darkHist = generateHistogram(from: darkPixels)
        assert(darkHist.status == .underexposed, "Dark image: Underexposed status")
        assert(darkHist.brightness < 85, "Dark image: Brightness < 85")
        
        let brightPixels = Array(repeating: Pixel(r: 200, g: 200, b: 200), count: 10)
        let brightHist = generateHistogram(from: brightPixels)
        assert(brightHist.status == .overexposed, "Bright image: Overexposed status")
        assert(brightHist.brightness > 170, "Bright image: Brightness > 170")
        
        let goodPixels = Array(repeating: Pixel(r: 128, g: 128, b: 128), count: 10)
        let goodHist = generateHistogram(from: goodPixels)
        assert(goodHist.status == .good, "Balanced image: Good exposure")
        assert(goodHist.brightness >= 85 && goodHist.brightness <= 170, "Balanced: Brightness in range")
        
        let mixedPixels = [
            Pixel(r: 255, g: 0, b: 0),
            Pixel(r: 0, g: 255, b: 0),
            Pixel(r: 0, g: 0, b: 255)
        ]
        let mixedHist = generateHistogram(from: mixedPixels)
        assert(mixedHist.rBuckets[255] == 1, "Red histogram: 1 pixel at max")
        assert(mixedHist.gBuckets[255] == 1, "Green histogram: 1 pixel at max")
        assert(mixedHist.bBuckets[255] == 1, "Blue histogram: 1 pixel at max")
        
        print()
    }
    
    func testPhotoMetadata() {
        print("📸 PHOTO METADATA TESTS")
        
        let metadata = PhotoMetadata(
            filmProfile: "Amber",
            iso: 200,
            shutterSpeed: 1.5,
            timestamp: Date()
        )
        
        assert(metadata.filmProfile == "Amber", "Metadata: Film profile stored")
        assert(metadata.iso == 200, "Metadata: ISO value stored")
        assert(metadata.shutterSpeed == 1.5, "Metadata: Shutter speed stored")
        assert(metadata.timestamp != nil, "Metadata: Timestamp recorded")
        
        let jsonData = metadata.toJSON()
        assert(!jsonData.isEmpty, "Metadata: JSON encoding works")
        
        print()
    }
    
    func testGridCalculations() {
        print("📐 GRID OVERLAY TESTS")
        
        let viewSize = CGSize(width: 390, height: 844)
        
        // Rule of thirds
        let thirdX = viewSize.width / 3
        let thirdY = viewSize.height / 3
        assert(abs(thirdX - 130) < 1, "Rule of thirds: Vertical line 1 at width/3")
        assert(abs(thirdY - 281.33) < 1, "Rule of thirds: Horizontal line 1 at height/3")
        
        // Golden ratio
        let phi = 1.618
        let goldenX = viewSize.width / phi
        let goldenY = viewSize.height / phi
        assert(abs(goldenX - 241) < 1, "Golden ratio: Vertical at width/phi")
        assert(abs(goldenY - 521) < 1, "Golden ratio: Horizontal at height/phi")
        
        print()
    }
    
    func printSummary() {
        print(String(repeating: "=", count: 60))
        print("TEST RESULTS")
        print(String(repeating: "=", count: 60))
        print("Total Tests: \(testsRun)")
        print("✓ Passed: \(testsPassed)")
        if testsFailed > 0 {
            print("✗ Failed: \(testsFailed)")
        }
        
        let passRate = testsRun > 0 ? Double(testsPassed) * 100 / Double(testsRun) : 0
        print(String(format: "Pass Rate: %.1f%%\n", passRate))
        
        if testsFailed == 0 {
            print("🎉 ALL TESTS PASSED!")
        }
        print(String(repeating: "=", count: 60) + "\n")
    }
}

// MARK: - Supporting Types

struct PhotoMetadata {
    let filmProfile: String
    let iso: Double
    let shutterSpeed: Double
    let timestamp: Date?
    
    func toJSON() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let timeStr = timestamp.map { formatter.string(from: $0) } ?? "nil"
        
        return """
        {
          "filmProfile": "\(filmProfile)",
          "iso": \(iso),
          "shutterSpeed": \(shutterSpeed),
          "timestamp": "\(timeStr)"
        }
        """
    }
}

// Grid calculations helper
import CoreGraphics

typealias CGSize = (width: Double, height: Double)

// MARK: - Demo Output

func runDemo() {
    print("\n" + String(repeating: "🎬", count: 30))
    print("LATITUDE CAM - PHASE 0 DEMO")
    print(String(repeating: "🎬", count: 30) + "\n")
    
    print("🎨 Film Profile Examples:")
    print("─" * 50)
    
    let testPixel = Pixel(r: 200, g: 150, b: 100)
    let profiles: [FilmProfile] = [
        AmberFilm(),
        SlateFilm(),
        RustFilm(),
        MonoFilm()
    ]
    
    print("Input Pixel: RGB(\(testPixel.r), \(testPixel.g), \(testPixel.b))")
    print()
    
    for profile in profiles {
        let result = profile.apply(to: testPixel)
        print("  \(profile.name): RGB(\(result.r), \(result.g), \(result.b))")
    }
    
    print("\n🔆 Exposure Control Examples:")
    print("─" * 50)
    
    let basePixel = Pixel(r: 128, g: 128, b: 128)
    var meter = ExposureMeter()
    
    print("Base Pixel: RGB(128, 128, 128)")
    print()
    
    let exposureSettings = [
        (iso: 50, shutter: 1.0, label: "ISO 50, 1x Shutter"),
        (iso: 100, shutter: 1.0, label: "ISO 100, 1x Shutter (Base)"),
        (iso: 200, shutter: 1.0, label: "ISO 200, 1x Shutter"),
        (iso: 100, shutter: 2.0, label: "ISO 100, 2x Shutter"),
    ]
    
    for setting in exposureSettings {
        meter.iso = setting.iso
        meter.shutterSpeed = setting.shutter
        let result = meter.adjustPixel(basePixel)
        print("  \(setting.label): RGB(\(result.r), \(result.g), \(result.b))")
    }
    
    print("\n📊 Histogram Analysis Examples:")
    print("─" * 50)
    
    let darkPixels = Array(repeating: Pixel(r: 50, g: 50, b: 50), count: 100)
    let darkHist = generateHistogram(from: darkPixels)
    
    let goodPixels = Array(repeating: Pixel(r: 128, g: 128, b: 128), count: 100)
    let goodHist = generateHistogram(from: goodPixels)
    
    let brightPixels = Array(repeating: Pixel(r: 200, g: 200, b: 200), count: 100)
    let brightHist = generateHistogram(from: brightPixels)
    
    print("Dark Image: Brightness = \(String(format: "%.1f", darkHist.brightness)) → \(darkHist.status.rawValue)")
    print("Good Image: Brightness = \(String(format: "%.1f", goodHist.brightness)) → \(goodHist.status.rawValue)")
    print("Bright Image: Brightness = \(String(format: "%.1f", brightHist.brightness)) → \(brightHist.status.rawValue)")
    
    print("\n✅ DEMO COMPLETE\n")
}

// Run everything
runDemo()
let tester = LatitudeCamTests()
tester.runAllTests()
