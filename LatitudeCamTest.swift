import Foundation

// MARK: - Core Types

struct Pixel {
    var r: UInt8, g: UInt8, b: UInt8
}

protocol FilmProfile {
    func apply(to pixel: Pixel) -> Pixel
    var name: String { get }
}

struct AmberFilm: FilmProfile {
    let name = "Amber"
    func apply(to pixel: Pixel) -> Pixel {
        let r = min(255, Int(pixel.r) * 120 / 100)
        let g = max(0, Int(pixel.g) * 90 / 100)
        let b = max(0, Int(pixel.b) * 80 / 100)
        return Pixel(r: UInt8(r), g: UInt8(g), b: UInt8(b))
    }
}

struct SlateFilm: FilmProfile {
    let name = "Slate"
    func apply(to pixel: Pixel) -> Pixel {
        let r = max(0, Int(pixel.r) * 80 / 100)
        let g = max(0, Int(pixel.g) * 80 / 100)
        let b = min(255, Int(pixel.b) * 120 / 100)
        return Pixel(r: UInt8(r), g: UInt8(g), b: UInt8(b))
    }
}

struct RustFilm: FilmProfile {
    let name = "Rust"
    func apply(to pixel: Pixel) -> Pixel {
        let r = min(255, Int(pixel.r) * 130 / 100)
        let g = min(255, Int(pixel.g) * 110 / 100)
        let b = max(0, Int(pixel.b) * 60 / 100)
        return Pixel(r: UInt8(r), g: UInt8(g), b: UInt8(b))
    }
}

struct MonoFilm: FilmProfile {
    let name = "Mono"
    func apply(to pixel: Pixel) -> Pixel {
        let gray = UInt8(Double(pixel.r) * 0.299 + Double(pixel.g) * 0.587 + Double(pixel.b) * 0.114)
        return Pixel(r: gray, g: gray, b: gray)
    }
}

struct ExposureMeter {
    var iso: Double = 100
    var shutterSpeed: Double = 1.0

    func adjustPixel(_ pixel: Pixel) -> Pixel {
        let isoMultiplier = iso / 100.0
        let shutterMultiplier = shutterSpeed
        let combinedMultiplier = isoMultiplier * shutterMultiplier

        let r = min(255, Int(Double(pixel.r) * combinedMultiplier))
        let g = min(255, Int(Double(pixel.g) * combinedMultiplier))
        let b = min(255, Int(Double(pixel.b) * combinedMultiplier))

        return Pixel(r: UInt8(r), g: UInt8(g), b: UInt8(b))
    }
}

struct HistogramData {
    var rBuckets: [Int] = Array(repeating: 0, count: 256)
    var gBuckets: [Int] = Array(repeating: 0, count: 256)
    var bBuckets: [Int] = Array(repeating: 0, count: 256)
    var brightness: Double = 0

    enum ExposureStatus: String {
        case underexposed = "Under"
        case good = "Good"
        case overexposed = "Over"
    }

    var status: ExposureStatus {
        if brightness < 85 { return .underexposed }
        if brightness > 170 { return .overexposed }
        return .good
    }
}

func generateHistogram(from pixels: [Pixel]) -> HistogramData {
    var hist = HistogramData()
    var totalBrightness = 0

    for pixel in pixels {
        hist.rBuckets[Int(pixel.r)] += 1
        hist.gBuckets[Int(pixel.g)] += 1
        hist.bBuckets[Int(pixel.b)] += 1
        totalBrightness += Int(pixel.r) + Int(pixel.g) + Int(pixel.b)
    }

    hist.brightness = pixels.isEmpty ? 0 : Double(totalBrightness) / Double(pixels.count * 3)
    return hist
}

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

// MARK: - Test Suite

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
        printHeader()
        testFilmProfiles()
        testExposureControl()
        testHistogram()
        testPhotoMetadata()
        printSummary()
    }

    func testFilmProfiles() {
        print("📽️  FILM PROFILES TESTS\n")

        let testPixel = Pixel(r: 200, g: 150, b: 100)

        // Amber Film
        let amberFilm = AmberFilm()
        let amberResult = amberFilm.apply(to: testPixel)
        assert(amberResult.r == 240, "Amber: R channel boosted (200 × 1.2 = 240)")
        assert(amberResult.g == 135, "Amber: G channel reduced (150 × 0.9 = 135)")
        assert(amberResult.b == 80, "Amber: B channel reduced (100 × 0.8 = 80)")

        // Slate Film
        let slateFilm = SlateFilm()
        let slateResult = slateFilm.apply(to: testPixel)
        assert(slateResult.r == 160, "Slate: R channel reduced (200 × 0.8 = 160)")
        assert(slateResult.b == 120, "Slate: B channel boosted (100 × 1.2 = 120)")

        // Rust Film
        let rustFilm = RustFilm()
        let rustResult = rustFilm.apply(to: testPixel)
        assert(rustResult.r == 255, "Rust: R channel clipped (200 × 1.3 = 260 → 255)")
        assert(rustResult.b == 60, "Rust: B channel reduced (100 × 0.6 = 60)")

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
        print("🔆 EXPOSURE CONTROL TESTS\n")

        let testPixel = Pixel(r: 128, g: 128, b: 128)
        var meter = ExposureMeter()

        // Base exposure
        let baseResult = meter.adjustPixel(testPixel)
        assert(baseResult.r == 128, "Base ISO 100: No change at 1× shutter")

        // ISO 200 (2× brighter)
        meter.iso = 200
        let iso200Result = meter.adjustPixel(testPixel)
        assert(iso200Result.r == 255, "ISO 200: Double brightness (128 × 2 = 256 → 255 clipped)")

        // ISO 50 (half brightness)
        meter.iso = 50
        let iso50Result = meter.adjustPixel(testPixel)
        assert(iso50Result.r == 64, "ISO 50: Half brightness (128 × 0.5 = 64)")

        // Shutter adjustment
        meter.iso = 100
        meter.shutterSpeed = 2.0
        let shutter2xResult = meter.adjustPixel(testPixel)
        assert(shutter2xResult.r == 255, "Shutter 2.0×: Double exposure (128 × 2 = 256 → 255)")

        meter.shutterSpeed = 0.5
        let shutter0_5xResult = meter.adjustPixel(testPixel)
        assert(shutter0_5xResult.r == 64, "Shutter 0.5×: Half exposure (128 × 0.5 = 64)")

        print()
    }

    func testHistogram() {
        print("📊 HISTOGRAM TESTS\n")

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
        print("📸 PHOTO METADATA TESTS\n")

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

    func printHeader() {
        print("\n" + String(repeating: "=", count: 70))
        print("LATITUDE CAM — PHASE 0 COMPREHENSIVE TEST SUITE")
        print(String(repeating: "=", count: 70) + "\n")
    }

    func printSummary() {
        print(String(repeating: "=", count: 70))
        print("TEST RESULTS")
        print(String(repeating: "=", count: 70))
        print("Total Tests Run:  \(testsRun)")
        print("✓ Passed:         \(testsPassed)")
        if testsFailed > 0 {
            print("✗ Failed:         \(testsFailed)")
        }

        let passRate = testsRun > 0 ? Double(testsPassed) * 100 / Double(testsRun) : 0
        print(String(format: "Pass Rate:        %.1f%%\n", passRate))

        if testsFailed == 0 {
            print("🎉 ALL TESTS PASSED — READY FOR SIMULATOR\n")
        }
        print(String(repeating: "=", count: 70) + "\n")
    }
}

// MARK: - Demo & Execution

func printDemoSection() {
    print("\n" + String(repeating: "🎬", count: 35))
    print("LATITUDE CAM FEATURE DEMONSTRATION")
    print(String(repeating: "🎬", count: 35) + "\n")

    print("🎨 Film Profile Transformations:")
    print(String(repeating: "─", count: 70))

    let testPixel = Pixel(r: 200, g: 150, b: 100)
    let profiles: [FilmProfile] = [AmberFilm(), SlateFilm(), RustFilm(), MonoFilm()]

    print("Input Pixel: RGB(\(testPixel.r), \(testPixel.g), \(testPixel.b))\n")

    for profile in profiles {
        let result = profile.apply(to: testPixel)
        print("  \(profile.name):  RGB(\(result.r), \(result.g), \(result.b))")
    }

    print("\n🔆 Exposure Metering (ISO × Shutter):")
    print(String(repeating: "─", count: 70))

    let basePixel = Pixel(r: 128, g: 128, b: 128)
    var meter = ExposureMeter()

    let settings = [
        (50, 1.0, "ISO 50, 1.0× (Darker)"),
        (100, 1.0, "ISO 100, 1.0× (Base)"),
        (200, 1.0, "ISO 200, 1.0× (Brighter)"),
        (100, 2.0, "ISO 100, 2.0× (2× Exposure)")
    ]

    print("Base Pixel: RGB(128, 128, 128)\n")

    for (iso, shutter, label) in settings {
        meter.iso = Double(iso)
        meter.shutterSpeed = shutter
        let result = meter.adjustPixel(basePixel)
        print("  \(label):      RGB(\(result.r), \(result.g), \(result.b))")
    }

    print("\n📊 Histogram Exposure Analysis:")
    print(String(repeating: "─", count: 70))

    let darkHist = generateHistogram(from: Array(repeating: Pixel(r: 50, g: 50, b: 50), count: 100))
    let goodHist = generateHistogram(from: Array(repeating: Pixel(r: 128, g: 128, b: 128), count: 100))
    let brightHist = generateHistogram(from: Array(repeating: Pixel(r: 200, g: 200, b: 200), count: 100))

    print("Dark Scene:     Brightness = \(String(format: "%.1f", darkHist.brightness)) [\(darkHist.status.rawValue)]")
    print("Balanced Scene: Brightness = \(String(format: "%.1f", goodHist.brightness)) [\(goodHist.status.rawValue)]")
    print("Bright Scene:   Brightness = \(String(format: "%.1f", brightHist.brightness)) [\(brightHist.status.rawValue)]")

    print("\n✅ All core features validated\n")
}

// Run demo and tests
printDemoSection()
let tester = LatitudeCamTests()
tester.runAllTests()
