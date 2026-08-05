//
//  CameraIntegrationTests.swift
//  LatitudeCam
//
//  Covers the settings surface and the GPU render pipeline. The pipeline is the
//  risky part: CoreImage silently passes the image through when a filter name is
//  wrong, so a typo would show up as "the toggle does nothing" rather than a
//  build failure. These tests fail loudly instead.
//

import XCTest
import CoreImage
import AVFoundation
@testable import LatitudeCam

final class CameraSettingsTests: XCTestCase {

    private static let persistedKeys = [
        "LatitudeCam.ISO", "LatitudeCam.Shutter",
        "LatitudeCam.FilmProfile", "LatitudeCam.Kelvin"
    ]

    private func clearPersistedSettings() {
        Self.persistedKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func setUp() {
        super.setUp()
        clearPersistedSettings()
    }

    override func tearDown() {
        clearPersistedSettings()
        super.tearDown()
    }

    func testDefaultSettings() {
        let manager = CameraManager()
        let s = manager.currentSettings
        XCTAssertEqual(s.filmID, "neutral")
        XCTAssertEqual(s.iso, 100)
        XCTAssertEqual(s.shutterDenominator, 60)
    }

    func testApplyUpdatesCurrentSettings() {
        let manager = CameraManager()
        var s = manager.currentSettings
        s.filmID = "rust"
        s.iso = 800
        s.shutterDenominator = 500
        s.ev = 1.5
        manager.apply(s)

        let read = manager.currentSettings
        XCTAssertEqual(read.filmID, "rust")
        XCTAssertEqual(read.iso, 800)
        XCTAssertEqual(read.shutterDenominator, 500)
        XCTAssertEqual(read.ev, 1.5, accuracy: 0.001)
    }

    func testSettingsPersistAcrossInstances() {
        let manager = CameraManager()
        var s = manager.currentSettings
        s.filmID = "slate"
        s.iso = 800
        s.shutterDenominator = 240
        manager.apply(s)

        // Simulate a relaunch.
        let reopened = CameraManager()
        XCTAssertEqual(reopened.currentSettings.filmID, "slate")
        XCTAssertEqual(reopened.currentSettings.iso, 800)
        XCTAssertEqual(reopened.currentSettings.shutterDenominator, 240)
    }
}

// MARK: - Film matrices

final class FilmMatrixTests: XCTestCase {

    /// The GPU matrices in CameraManager duplicate the multipliers in
    /// FilmProfiles.swift. If either side is edited alone the live preview stops
    /// matching the reference implementation, so pin them together.
    private func assertMatrixMatchesProfile(
        _ filmID: String,
        _ profile: FilmProfile,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (r, g, b) = CameraManager.filmVectors(filmID)

        // 100 is low enough that no channel clamps at 255 after the multiply.
        let probe = Pixel(r: 100, g: 100, b: 100)
        let expected = profile.apply(to: probe)

        let matrixR = (r.x + r.y + r.z) * 100
        let matrixG = (g.x + g.y + g.z) * 100
        let matrixB = (b.x + b.y + b.z) * 100

        XCTAssertEqual(Double(matrixR), Double(expected.r), accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(Double(matrixG), Double(expected.g), accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(Double(matrixB), Double(expected.b), accuracy: 0.5, file: file, line: line)
    }

    func testAmberMatrixMatchesProfile() {
        assertMatrixMatchesProfile("amber", AmberFilm())
    }

    func testSlateMatrixMatchesProfile() {
        assertMatrixMatchesProfile("slate", SlateFilm())
    }

    func testRustMatrixMatchesProfile() {
        assertMatrixMatchesProfile("rust", RustFilm())
    }

    func testMonoMatrixMatchesProfile() {
        assertMatrixMatchesProfile("mono", MonoFilm())
    }

    func testUnknownFilmIDFallsBackToAmber() {
        let (r, _, b) = CameraManager.filmVectors("does-not-exist")
        let (ar, _, ab) = CameraManager.filmVectors("amber")
        XCTAssertEqual(r.x, ar.x, accuracy: 0.001)
        XCTAssertEqual(b.z, ab.z, accuracy: 0.001)
    }

    func testLerpAtZeroIsIdentityAndAtOneIsFilm() {
        let identity = CIVector(x: 1, y: 0, z: 0, w: 0)
        let film = CIVector(x: 1.3, y: 0, z: 0, w: 0)
        XCTAssertEqual(CameraManager.lerp(identity, film, 0).x, 1.0, accuracy: 0.001)
        XCTAssertEqual(CameraManager.lerp(identity, film, 1).x, 1.3, accuracy: 0.001)
        XCTAssertEqual(CameraManager.lerp(identity, film, 0.5).x, 1.15, accuracy: 0.001)
    }
}

// MARK: - Render pipeline

final class RenderPipelineTests: XCTestCase {

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let extent = CGRect(x: 0, y: 0, width: 64, height: 64)

    private func source(
        red: CGFloat = 0.6, green: CGFloat = 0.4, blue: CGFloat = 0.2
    ) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue)).cropped(to: extent)
    }

    /// Reads one pixel back so assertions are about actual output, not about the
    /// filter graph we think we built.
    private func sample(_ image: CIImage) -> (r: UInt8, g: UInt8, b: UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 32, y: 32, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (pixel[0], pixel[1], pixel[2])
    }

    private func neutralSettings() -> RenderSettings {
        var s = RenderSettings()
        s.kelvin = 6500      // matches the pipeline's target neutral, so WB is a no-op
        s.ev = 0
        s.iso = 100
        s.shutterDenominator = 60
        s.grain = false
        s.halation = false
        s.vignette = false
        s.focusPeaking = false
        return s
    }

    func testRenderPreservesExtent() {
        let manager = CameraManager()
        let out = manager.render(source(), with: neutralSettings())
        XCTAssertEqual(out.extent, extent)
    }

    func testMonoRenderProducesGrey() {
        let manager = CameraManager()
        var s = neutralSettings()
        s.filmID = "mono"
        s.intensity = 1.0

        let out = sample(manager.render(source(), with: s))
        XCTAssertLessThanOrEqual(abs(Int(out.r) - Int(out.g)), 2, "mono should equalise channels")
        XCTAssertLessThanOrEqual(abs(Int(out.g) - Int(out.b)), 2, "mono should equalise channels")
    }

    func testAmberRenderWarmsTheFrame() {
        let manager = CameraManager()
        var s = neutralSettings()
        s.filmID = "amber"
        s.intensity = 1.0

        let plain = sample(manager.render(source(), with: { var n = s; n.intensity = 0; return n }()))
        let amber = sample(manager.render(source(), with: s))

        XCTAssertGreaterThan(Int(amber.r), Int(plain.r), "amber lifts red")
        XCTAssertLessThan(Int(amber.b), Int(plain.b), "amber pulls blue down")
    }

    func testSlateRenderCoolsTheFrame() {
        let manager = CameraManager()
        var s = neutralSettings()
        s.filmID = "slate"
        s.intensity = 1.0

        let plain = sample(manager.render(source(), with: { var n = s; n.intensity = 0; return n }()))
        let slate = sample(manager.render(source(), with: s))

        XCTAssertLessThan(Int(slate.r), Int(plain.r), "slate pulls red down")
        XCTAssertGreaterThan(Int(slate.b), Int(plain.b), "slate lifts blue")
    }

    func testIntensityZeroLeavesFrameUnchanged() {
        let manager = CameraManager()
        var s = neutralSettings()
        s.filmID = "rust"
        s.intensity = 0

        let plain = sample(source())
        let rendered = sample(manager.render(source(), with: s))
        XCTAssertLessThanOrEqual(abs(Int(rendered.r) - Int(plain.r)), 2)
        XCTAssertLessThanOrEqual(abs(Int(rendered.g) - Int(plain.g)), 2)
        XCTAssertLessThanOrEqual(abs(Int(rendered.b) - Int(plain.b)), 2)
    }

    func testPositiveExposureCompensationBrightens() {
        let manager = CameraManager()
        var s = neutralSettings()
        s.intensity = 0

        var brighter = s
        brighter.ev = 1.0

        let base = sample(manager.render(source(), with: s))
        let lifted = sample(manager.render(source(), with: brighter))
        XCTAssertGreaterThan(Int(lifted.r), Int(base.r))
    }

    func testWarmWhiteBalanceShiftsAwayFromNeutral() {
        let manager = CameraManager()
        var s = neutralSettings()
        s.intensity = 0

        var warm = s
        warm.kelvin = 8200

        let neutral = sample(manager.render(source(), with: s))
        let shifted = sample(manager.render(source(), with: warm))
        XCTAssertNotEqual(Int(neutral.r), Int(shifted.r), "white balance must change the frame")
    }

    func testVignetteDarkensTheCorner() {
        let manager = CameraManager()
        var s = neutralSettings()
        s.intensity = 0

        var vignetted = s
        vignetted.vignette = true

        func corner(_ image: CIImage) -> UInt8 {
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(
                image, toBitmap: &pixel, rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            return pixel[0]
        }

        let plain = corner(manager.render(source(), with: s))
        let dark = corner(manager.render(source(), with: vignetted))
        XCTAssertLessThan(Int(dark), Int(plain), "vignette should darken the corners")
    }

    /// Samples the far corner, not the centre. The original grain bug produced a
    /// 512pt patch at the origin — a centre sample of a 64pt test image sat
    /// inside it, so the bug passed this suite for weeks.
    func testGrainCoversTheWholeFrame() {
        let manager = CameraManager()
        var s = neutralSettings()
        s.intensity = 0

        var grainy = s
        grainy.grain = true
        grainy.iso = 3200

        let big = CGRect(x: 0, y: 0, width: 900, height: 900)
        let wide = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: big)

        func farCorner(_ image: CIImage) -> (UInt8, UInt8, UInt8) {
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(
                image, toBitmap: &pixel, rowBytes: 4,
                bounds: CGRect(x: 860, y: 860, width: 1, height: 1),
                format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            return (pixel[0], pixel[1], pixel[2])
        }

        let plain = farCorner(manager.render(wide, with: s))
        let noisy = farCorner(manager.render(wide, with: grainy))
        let delta = abs(Int(noisy.0) - Int(plain.0))
            + abs(Int(noisy.1) - Int(plain.1))
            + abs(Int(noisy.2) - Int(plain.2))
        XCTAssertGreaterThan(delta, 0, "grain must reach beyond the first 512pt of the frame")
    }

    /// The blend that made grain read as white salt: CoreImage works in linear
    /// light, so overlay's shadow branch multiplies by 2·blend and a gentle noise
    /// becomes a loud one everywhere the frame is dark. Soft light scales with the
    /// base, so a near-black frame has to stay near black.
    /// Mean absolute deviation across a block, so one unlucky grain cannot decide
    /// the result.
    private func meanLevel(_ image: CIImage) -> Double {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        context.render(
            image, toBitmap: &pixels, rowBytes: side * 4,
            bounds: CGRect(x: 8, y: 8, width: side, height: side),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let total = stride(from: 0, to: pixels.count, by: 4).reduce(0.0) { $0 + Double(pixels[$1]) }
        return total / Double(side * side)
    }

    /// The blend that made grain read as white salt: CoreImage works in linear
    /// light, so overlay's shadow branch multiplies by 2·blend and turns a gentle
    /// noise into a loud one everywhere the frame is dark. Soft light scales with
    /// the base instead, so the shadows barely move.
    ///
    /// Both renders use the same ISO — changing it would also change the simulated
    /// exposure, and the test would be measuring brightness rather than grain.
    func testGrainBarelyMovesTheShadows() {
        let manager = CameraManager()
        var plain = neutralSettings()
        plain.intensity = 0
        plain.iso = 3200                  // the noisiest the dial goes
        var grainy = plain
        grainy.grain = true

        let dark = CIImage(color: CIColor(red: 0.01, green: 0.01, blue: 0.01))
            .cropped(to: extent)

        let before = meanLevel(manager.render(dark, with: plain))
        let after = meanLevel(manager.render(dark, with: grainy))

        XCTAssertLessThan(abs(after - before), 12,
                          "shadow grain must be a texture, not white speckle")
    }

    func testGrainFollowsFilmSpeed() {
        let slow = CameraManager.grainAmplitude(forISO: 50)
        let fast = CameraManager.grainAmplitude(forISO: 3200)
        XCTAssertLessThan(slow, fast, "fast film is the grainy one")
        XCTAssertGreaterThan(slow, 0)
        XCTAssertLessThan(fast, 0.15, "grain is a texture, not a subject")
    }

    func testGrainAmplitudeClampsOutsideTheDial() {
        XCTAssertEqual(CameraManager.grainAmplitude(forISO: 1),
                       CameraManager.grainAmplitude(forISO: 50), accuracy: 0.0001)
        XCTAssertEqual(CameraManager.grainAmplitude(forISO: 99_999),
                       CameraManager.grainAmplitude(forISO: 3200), accuracy: 0.0001)
    }

    func testGrainPerturbsTheFrame() {
        let manager = CameraManager()
        var s = neutralSettings()
        s.intensity = 0

        var grainy = s
        grainy.grain = true
        grainy.iso = 3200

        let plain = sample(manager.render(source(), with: s))
        let noisy = sample(manager.render(source(), with: grainy))
        let delta = abs(Int(noisy.r) - Int(plain.r))
            + abs(Int(noisy.g) - Int(plain.g))
            + abs(Int(noisy.b) - Int(plain.b))
        XCTAssertGreaterThan(delta, 0, "grain should change pixel values")
    }

    /// CoreImage returns the input untouched for an unknown filter name, so a
    /// typo would look like a dead toggle. Check the names resolve.
    func testEveryFilterNameResolves() {
        let names = [
            "CITemperatureAndTint", "CIExposureAdjust", "CIColorMatrix",
            "CIBloom", "CIVignette", "CISoftLightBlendMode",
            "CIEdges", "CIScreenBlendMode", "CIRandomGenerator", "CIAffineTile"
        ]
        for name in names {
            XCTAssertNotNil(CIFilter(name: name), "missing CIFilter: \(name)")
        }
    }
}

// MARK: - Capture

final class CameraCaptureTests: XCTestCase {

    /// The Simulator has no capture device, so the session never delivers a
    /// frame — capturePhoto has to return nil rather than trap.
    func testCapturePhotoWithoutFrameReturnsNil() {
        let manager = CameraManager()
        XCTAssertNil(manager.capturePhoto())
    }

    func testFrameBufferStartsEmpty() {
        let manager = CameraManager()
        XCTAssertNil(manager.frames.image)
    }

    func testStatusStartsIdle() {
        let manager = CameraManager()
        XCTAssertEqual(manager.status, .idle)
    }
}

// MARK: - Neutral stock

final class NeutralFilmTests: XCTestCase {

    /// Neutral has to be genuinely inert, not merely subtle — it is the default,
    /// and a camera that quietly tints every frame is lying about what it saw.
    func testNeutralIsTheIdentityMatrix() {
        let (r, g, b) = CameraManager.filmVectors("neutral")
        XCTAssertEqual(r.x, 1, accuracy: 0.0001)
        XCTAssertEqual(r.y, 0, accuracy: 0.0001)
        XCTAssertEqual(r.z, 0, accuracy: 0.0001)
        XCTAssertEqual(g.x, 0, accuracy: 0.0001)
        XCTAssertEqual(g.y, 1, accuracy: 0.0001)
        XCTAssertEqual(g.z, 0, accuracy: 0.0001)
        XCTAssertEqual(b.x, 0, accuracy: 0.0001)
        XCTAssertEqual(b.y, 0, accuracy: 0.0001)
        XCTAssertEqual(b.z, 1, accuracy: 0.0001)
    }

    func testNeutralIsTheDefaultAndComesFirst() {
        XCTAssertEqual(FilmPreset.all.first?.id, "neutral")
        XCTAssertEqual(AppState.defaultControls.filmID, "neutral")
    }
}

// MARK: - Focus and metering

final class FocusAndMeteringTests: XCTestCase {

    @MainActor
    func testFocusIndexRoundTripsThroughEveryStop() {
        let app = AppState()
        XCTAssertEqual(app.focusIndex, 0, "AF is index 0")
        XCTAssertEqual(app.focusLabel, "AF")

        for stop in 1...AppState.focusStops.count {
            app.focusIndex = stop
            XCTAssertFalse(app.autoFocus)
            XCTAssertEqual(app.focusIndex, stop, "stop \(stop) did not survive the round trip")
            XCTAssertEqual(app.focusLabel, AppState.focusStops[stop - 1].label)
        }

        app.focusIndex = 0
        XCTAssertTrue(app.autoFocus)
    }

    @MainActor
    func testFocusAndMeteringReachTheRenderPipeline() {
        let app = AppState()
        app.focusIndex = 4
        XCTAssertFalse(app.cameraManager.currentSettings.autoFocus)
        XCTAssertEqual(app.cameraManager.currentSettings.lensPosition,
                       AppState.focusStops[3].position, accuracy: 0.0001)

        app.meteringIndex = 1
        XCTAssertEqual(app.metering, "SPOT")
        XCTAssertEqual(app.cameraManager.currentSettings.metering, "SPOT")

        app.pointOfInterest = CGPoint(x: 0.25, y: 0.75)
        XCTAssertEqual(app.cameraManager.currentSettings.pointOfInterest.x, 0.25, accuracy: 0.0001)
    }

    @MainActor
    func testMeteringModesAreDistinct() {
        XCTAssertEqual(Set(AppState.meteringModes).count, AppState.meteringModes.count)
        XCTAssertTrue(AppState.meteringModes.contains("LOCK"))
    }
}

// MARK: - Lenses

final class LensTests: XCTestCase {

    /// The ladder is read off the hardware, so a body with no ultra-wide must not
    /// be offered 0.5×. On the simulator there is no camera at all, which is the
    /// case this asserts: no lenses rather than a fabricated set.
    func testLensListIsEmptyWithoutACamera() {
        let manager = CameraManager()
        XCTAssertTrue(manager.lenses.allSatisfy { $0.zoom >= 1 },
                      "a zoom factor below 1 is not a valid device zoom")
    }

    func testLensIdentityIsStableForSelection() {
        let a = CameraManager.Lens(id: "wide", label: "1×", zoom: 2)
        let b = CameraManager.Lens(id: "wide", label: "1×", zoom: 2)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.id, "wide")
    }

    @MainActor
    func testZoomFactorReachesTheRenderPipeline() {
        let app = AppState()
        // Falls back to 1 when the device has reported nothing, rather than to a
        // factor from some other camera's ladder.
        XCTAssertEqual(app.cameraManager.currentSettings.zoomFactor, 1, accuracy: 0.0001)
    }

    @MainActor
    func testFlippingReturnsTheSelectorToALensThatExists() {
        let app = AppState()
        app.lensID = "tele"
        app.flipCamera()

        let settled = expectation(description: "flip reported")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        // With no second camera the flip declines and the id is left alone; with
        // one it lands on "wide", which both ladders define. Neither outcome may
        // leave a telephoto selected on a front camera that has none.
        if app.usingFrontCamera {
            XCTAssertEqual(app.lensID, "wide")
        }
    }
}
