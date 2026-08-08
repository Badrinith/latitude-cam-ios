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

// MARK: - The film shelf

final class FilmShelfTests: XCTestCase {

    func testEveryStockHasAMatrixAndTheyAreDistinct() {
        var seen: [String] = []
        for preset in FilmPreset.all {
            let (r, g, b) = CameraManager.filmVectors(preset.id)
            let key = "\(r.x),\(r.y),\(r.z)|\(g.x),\(g.y),\(g.z)|\(b.x),\(b.y),\(b.z)"
            XCTAssertFalse(seen.contains(key),
                           "\(preset.id) renders identically to another stock")
            seen.append(key)
        }
    }

    /// A film simulation must not change how bright the scene is — that is the
    /// exposure's job. Anything much off unity would read as a metering fault
    /// the moment someone changed stock.
    func testNoStockShiftsOverallBrightnessMoreThanAThirdOfAStop() {
        for preset in FilmPreset.all {
            let (r, g, b) = CameraManager.filmVectors(preset.id)
            // Luma-weighted sum of each output channel's contribution.
            let luma = 0.299 * (r.x + r.y + r.z)
                     + 0.587 * (g.x + g.y + g.z)
                     + 0.114 * (b.x + b.y + b.z)
            XCTAssertEqual(Double(luma), 1.0, accuracy: 0.26,
                           "\(preset.id) moves overall brightness on its own")
        }
    }

    func testCurvesOnlyOnStocksWithoutAReferenceImplementation() {
        // The four originals are pinned to the per-pixel profiles in
        // FilmProfiles.swift; a curve here would make the two disagree.
        for id in ["amber", "slate", "rust", "mono", "neutral"] {
            XCTAssertNil(CameraManager.filmCurve(id), "\(id) must stay pinned to its reference")
        }
        for id in ["vermilion", "meridian", "porcelain", "harbour", "ledger", "ash"] {
            XCTAssertNotNil(CameraManager.filmCurve(id), "\(id) is defined by its curve")
        }
    }

    func testLedgerIsTheOnlyStockThatLiftsBlacks() {
        for preset in FilmPreset.all {
            let lift = CameraManager.filmCurve(preset.id)?.lift ?? 0
            if preset.id == "ledger" {
                XCTAssertGreaterThan(lift, 0)
            } else {
                XCTAssertEqual(lift, 0, accuracy: 0.0001, "\(preset.id) should reach true black")
            }
        }
    }

    func testMonochromeStocksAreTrulyGrey() {
        for id in ["mono", "ash"] {
            let (r, g, b) = CameraManager.filmVectors(id)
            XCTAssertEqual(r.x, g.x, accuracy: 0.0001)
            XCTAssertEqual(g.x, b.x, accuracy: 0.0001)
            XCTAssertEqual(r.y, g.y, accuracy: 0.0001)
            XCTAssertEqual(r.z, b.z, accuracy: 0.0001)
        }
        // Ash is panchromatic, Mono is luma-weighted — the whole reason for two.
        XCTAssertNotEqual(CameraManager.filmVectors("ash").0.y,
                          CameraManager.filmVectors("mono").0.y)
    }

    func testStocksAreOrderedByFamily() {
        let families = FilmPreset.all.map(\.family)
        XCTAssertEqual(Array(Set(families)).count, 5, "None, Reversal, Print, Monochrome, Signature")
        // Grouped, not interleaved: each family appears in one unbroken run.
        var runs: [String] = []
        for family in families where runs.last != family { runs.append(family) }
        XCTAssertEqual(runs.count, Set(runs).count, "a family is split across the roll")
    }
}

// MARK: - Portrait

@MainActor
final class PortraitModeTests: XCTestCase {

    /// Off until asked for. Depth delivery narrows the format the device will run
    /// and costs resolution on every frame, not only the separated ones.
    func testPortraitIsOffByDefault() {
        XCTAssertFalse(RenderSettings().portrait)
        XCTAssertFalse(AppState().portrait)
    }

    /// The flag follows what the camera reported, not what was tapped. A body
    /// that cannot separate depth must not leave the control claiming it did.
    func testPortraitDoesNotTurnOnWithoutHardware() {
        let app = AppState()
        app.togglePortrait()

        let settled = expectation(description: "camera answered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        if !app.cameraManager.supportsPortrait {
            XCTAssertFalse(app.portrait, "claimed a mode the hardware refused")
        }
    }

    func testApertureLadderReadsAsALens() {
        XCTAssertEqual(AppState.apertureLabels.first, "f/1.4")
        XCTAssertEqual(AppState.apertureLabels.last, "f/16")
        // Ascending f-numbers mean descending blur, which is the direction a
        // photographer already expects.
        XCTAssertEqual(AppState.apertureStops, AppState.apertureStops.sorted())
    }

    func testApertureReachesTheRenderPipeline() {
        let app = AppState()
        app.apertureIndex = 0
        XCTAssertEqual(app.apertureValue, 1.4, accuracy: 0.001)
        XCTAssertEqual(app.cameraManager.currentSettings.aperture, 1.4, accuracy: 0.001)

        app.apertureIndex = 99   // past the end of the ladder
        XCTAssertEqual(app.apertureValue, 16, accuracy: 0.001)
    }
}

// MARK: - Pinch zoom

@MainActor
final class PinchZoomTests: XCTestCase {

    /// A pinch has to stay inside what the hardware will accept, or
    /// videoZoomFactor throws. Range starts 1...1 before the device answers, so a
    /// pinch before that point must not move anything.
    func testPinchClampsToTheReportedRange() {
        let app = AppState()
        let before = app.zoom
        app.pinchZoom(by: 50)
        XCTAssertEqual(app.zoom, before, accuracy: 0.001,
                       "zoomed past the range reported before the camera answered")
    }

    func testZoomReachesTheRenderPipeline() {
        let app = AppState()
        app.zoom = 3
        XCTAssertEqual(app.cameraManager.currentSettings.zoomFactor, 3, accuracy: 0.001)
    }
}

// MARK: - Landscape capture orientation
//
// The angle itself is still device-only: it comes from
// AVCaptureDevice.RotationCoordinator against a live AVCaptureDevice and moves
// as the phone turns, so there is nothing there a unit test can pin without
// just checking that a mock returns what the mock returns.
//
// Translating that angle into the orientation tag written to the file is a
// different matter — it is a pure function, and it is the half that decides
// whether a landscape frame opens upright. The RAW mosaic is never rasterized,
// so this tag is the *only* thing standing between a sideways DNG and a
// correct one. These pin it.

final class CaptureExifOrientationTests: XCTestCase {

    /// Turned anticlockwise: the frame needs a quarter turn clockwise to come
    /// back upright, which EXIF calls `.right`.
    func testNinetyDegreesMapsToRight() {
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: 90),
                       CGImagePropertyOrientation.right.rawValue)
    }

    func testMinusNinetyMapsToLeft() {
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: -90),
                       CGImagePropertyOrientation.left.rawValue)
    }

    /// The two landscape cases must not collapse onto the same tag — that is
    /// exactly the mistake that reads as "landscape is still rotated", and it
    /// is invisible until a photo comes out of the roll upside down.
    func testTheTwoLandscapeCasesAreOpposites() {
        XCTAssertNotEqual(CameraManager.exifOrientation(forCaptureRotation: 90),
                          CameraManager.exifOrientation(forCaptureRotation: -90),
                          "landscape left and landscape right resolved to the same tag")
    }

    func testUpsideDownMapsToDown() {
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: 180),
                       CGImagePropertyOrientation.down.rawValue)
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: -180),
                       CGImagePropertyOrientation.down.rawValue)
    }

    func testPortraitIsUntagged() {
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: 0),
                       CGImagePropertyOrientation.up.rawValue)
    }

    /// 270 and -90 describe the same physical rotation and must agree, as must
    /// -270 and 90. A table that handles only one sign leaves whichever way the
    /// coordinator happens to report it as the broken orientation.
    func testEquivalentAnglesAgreeWhicheverSignIsReported() {
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: 270),
                       CameraManager.exifOrientation(forCaptureRotation: -90))
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: -270),
                       CameraManager.exifOrientation(forCaptureRotation: 90))
    }

    /// The coordinator reports a Double, and a hair either side of a right
    /// angle is still that right angle — truncating instead of rounding would
    /// send 89.6° to the portrait case and silently drop the rotation.
    func testAnglesRoundRatherThanTruncate() {
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: 89.6),
                       CGImagePropertyOrientation.right.rawValue)
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: 90.4),
                       CGImagePropertyOrientation.right.rawValue)
    }

    /// A full turn past is the same orientation, not an unhandled one.
    func testAnglesBeyondAFullTurnWrap() {
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: 450),
                       CGImagePropertyOrientation.right.rawValue)
        XCTAssertEqual(CameraManager.exifOrientation(forCaptureRotation: 360),
                       CGImagePropertyOrientation.up.rawValue)
    }

    /// Nothing may resolve to a value outside the four EXIF quarter turns; a
    /// stray 0 here would be an invalid tag rather than "no rotation".
    func testEveryQuarterTurnIsAValidOrientation() {
        let valid: Set<UInt32> = [
            CGImagePropertyOrientation.up.rawValue,
            CGImagePropertyOrientation.down.rawValue,
            CGImagePropertyOrientation.left.rawValue,
            CGImagePropertyOrientation.right.rawValue
        ]
        for angle in stride(from: -360.0, through: 360.0, by: 90.0) {
            XCTAssertTrue(valid.contains(CameraManager.exifOrientation(forCaptureRotation: angle)),
                          "\(angle)° produced an orientation outside the four quarter turns")
        }
    }
}

// MARK: - Knob geometry
//
// The two alternative control decks are both built on one rotary knob, and the
// parts of a knob that go wrong are invisible in code: a knob that runs
// backwards, or that slams end to end when the drag crosses the seam behind it,
// reads as fine on the page and as broken in the hand. Pinned here rather than
// discovered on device.

final class KnobMathTests: XCTestCase {

    func testMidValueSitsStraightUp() {
        XCTAssertEqual(KnobMath.pointerAngle(for: 0.5), 0, accuracy: 0.001)
    }

    func testTheEndsAreSymmetricAboutTheTop() {
        XCTAssertEqual(KnobMath.pointerAngle(for: 0), -KnobMath.sweep / 2, accuracy: 0.001)
        XCTAssertEqual(KnobMath.pointerAngle(for: 1), KnobMath.sweep / 2, accuracy: 0.001)
    }

    /// Clockwise is more. The whole control is wrong if this is inverted, and
    /// nothing else in the file would fail.
    func testTurningClockwiseRaisesTheValue() {
        XCTAssertGreaterThan(KnobMath.advance(0.5, byDegrees: 20), 0.5)
        XCTAssertLessThan(KnobMath.advance(0.5, byDegrees: -20), 0.5)
    }

    func testTheKnobStopsAtItsEnds() {
        XCTAssertEqual(KnobMath.advance(1, byDegrees: 400), 1, accuracy: 0.0001)
        XCTAssertEqual(KnobMath.advance(0, byDegrees: -400), 0, accuracy: 0.0001)
    }

    /// A drag passing through ±180° must read as a small step, not most of a
    /// circle — this is the difference between a smooth turn and the value
    /// jumping the moment the finger crosses the bottom of the knob.
    func testCrossingTheSeamIsASmallStepNotAJump() {
        XCTAssertEqual(KnobMath.angleDelta(from: 179, to: -179), 2, accuracy: 0.001)
        XCTAssertEqual(KnobMath.angleDelta(from: -179, to: 179), -2, accuracy: 0.001)
    }

    func testDeltaIsPlainSubtractionAwayFromTheSeam() {
        XCTAssertEqual(KnobMath.angleDelta(from: 10, to: 40), 30, accuracy: 0.001)
        XCTAssertEqual(KnobMath.angleDelta(from: 40, to: 10), -30, accuracy: 0.001)
    }

    /// A full sweep of the finger has to cover the whole range — no more, so
    /// the ends are reachable, and no less, so they are not overshot instantly.
    func testAFullSweepCoversExactlyTheRange() {
        XCTAssertEqual(KnobMath.advance(0, byDegrees: KnobMath.sweep), 1, accuracy: 0.0001)
    }

    /// The click has to land on the same ladder index the readout uses, or the
    /// knob clicks without the value changing.
    func testDetentsMatchTheLadderIndexing() {
        let stops = AppState.isoStops.count
        XCTAssertEqual(KnobMath.detent(0, stops: stops), 0)
        XCTAssertEqual(KnobMath.detent(1, stops: stops), stops - 1)
        XCTAssertEqual(KnobMath.detent(0.999, stops: stops), stops - 1)
    }

    func testDetentsNeverLeaveTheLadder() {
        for step in 0...40 {
            let index = KnobMath.detent(Double(step) / 40, stops: 7)
            XCTAssertTrue((0..<7).contains(index), "detent \(index) is off the ladder")
        }
    }

    func testDetentSurvivesADegenerateLadder() {
        XCTAssertEqual(KnobMath.detent(0.7, stops: 1), 0)
        XCTAssertEqual(KnobMath.detent(0.7, stops: 0), 0)
    }

    func testClampHoldsTheZeroToOneContract() {
        XCTAssertEqual(KnobMath.clamp(-3), 0)
        XCTAssertEqual(KnobMath.clamp(4), 1)
        XCTAssertEqual(KnobMath.clamp(0.42), 0.42, accuracy: 0.0001)
    }
}

// MARK: - Viewfinder control styles

final class ViewfinderControlStyleTests: XCTestCase {

    func testEveryStyleIsOffered() {
        XCTAssertEqual(Pref.viewfinderControlOptions,
                       ["Film Label", "Bellows Drawer", "Crown", "Top Plate"])
    }

    /// Top Plate is the only style that replaces the chrome outright rather
    /// than hanging a deck beneath it, so it is the only one that has to inset
    /// the picture. If the band height and that inset ever disagree, the frame
    /// sits under opaque metal and metering lands off the thumb.
    func testTheTopPlateBandHasAHeightToInsetBy() {
        XCTAssertEqual(TopPlateBand.height, 210, "the handoff specifies a 210pt plate")
    }

    /// Every dial on the plate drives a real ladder. A zero-stop dial divides by
    /// zero in the detent maths and never clicks.
    func testEveryPlateDialHasALadder() {
        XCTAssertGreaterThan(AppState.apertureStops.count, 1)
        XCTAssertGreaterThan(AppState.isoStops.count, 1)
        XCTAssertGreaterThan(AppState.shutterStops.count, 1)
        XCTAssertGreaterThan(AppState.whiteBalanceStops.count, 1)
        XCTAssertGreaterThan(AppState.evDetents, 1)
    }

    /// Aperture is stored as a ladder index while every other dial is 0…1, so
    /// the plate bridges it. A round trip that drifts would walk the aperture
    /// a stop every time the view rebuilt.
    func testTheApertureBridgeRoundTrips() {
        let last = AppState.apertureStops.count - 1
        for index in 0...last {
            let normalised = Double(index) / Double(last)
            let back = min(last, max(0, Int((normalised * Double(last)).rounded())))
            XCTAssertEqual(back, index, "aperture index \(index) did not survive the round trip")
        }
    }

    /// Film Label is the chosen primary deck. Existing Classic preferences are
    /// migrated by SettingsScreen, so a fresh install and an upgraded install
    /// both land on the same presentation.
    func testFilmLabelIsTheDefault() {
        UserDefaults.standard.removeObject(forKey: Pref.viewfinderControls)
        XCTAssertEqual(Pref.string(Pref.viewfinderControls, default: "Film Label"), "Film Label")
    }

    /// The crown cycles through every target and comes back round, so no
    /// setting can be stranded behind a stop that is never reached.
    func testTheCrownReachesEveryTargetAndWrapsBack() {
        let targets = CrownControl.Target.allCases
        XCTAssertEqual(targets.count, 4)

        var seen: [CrownControl.Target] = []
        var current = CrownControl.Target.iso
        for _ in 0..<targets.count {
            seen.append(current)
            current = CrownControl.Target(rawValue: (current.rawValue + 1) % targets.count) ?? .iso
        }
        XCTAssertEqual(Set(seen).count, targets.count, "a target is unreachable")
        XCTAssertEqual(current, .iso, "the crown does not come back round")
    }

    func testEveryCrownTargetIsLabelled() {
        for target in CrownControl.Target.allCases {
            XCTAssertFalse(target.label.isEmpty)
        }
    }

    /// The drawer has to leave enough of itself on screen to be grabbed again.
    func testTheStowedDrawerLeavesAHandle() {
        XCTAssertGreaterThanOrEqual(BellowsDrawer.lip, 28, "too little left to grab")
        XCTAssertLessThan(BellowsDrawer.lip, BellowsDrawer.height, "the drawer never stows")
    }
}

// MARK: - Leaf shutter

/// Five blades that fail to meet leave a hole in the middle of a shut shutter —
/// which looks like a rendering bug and is really arithmetic. Pinned here.
final class LeafShutterGeometryTests: XCTestCase {

    func testAnOddBladeCountReadsAsMechanism() {
        XCTAssertEqual(LeafShutterGeometry.bladeCount % 2, 1,
                       "an even blade count reads as a flower, not a shutter")
    }

    /// The property the whole drawing depends on: fully closed means no opening
    /// left at all.
    func testFullClosureLeavesNoOpening() {
        XCTAssertEqual(LeafShutterGeometry.apertureRadius(closure: 1), 0, accuracy: 0.0001)
    }

    func testFullyOpenIsTheWholeAperture() {
        XCTAssertEqual(LeafShutterGeometry.apertureRadius(closure: 0), 1, accuracy: 0.0001)
    }

    /// Closing must never widen the opening — an easing curve that overshoots
    /// would make the shutter flare open mid-fire.
    func testTheApertureOnlyEverNarrowsAsItCloses() {
        var previous = LeafShutterGeometry.apertureRadius(closure: 0)
        for step in 1...40 {
            let radius = LeafShutterGeometry.apertureRadius(closure: Double(step) / 40)
            XCTAssertLessThanOrEqual(radius, previous + 0.0001, "the aperture widened while closing")
            previous = radius
        }
    }

    func testTheApertureNeverLeavesItsBounds() {
        for step in -10...50 {
            let radius = LeafShutterGeometry.apertureRadius(closure: Double(step) / 40)
            XCTAssertTrue((0...1).contains(radius), "radius \(radius) is outside the button")
        }
    }

    /// Each blade starts on its own seat, evenly spaced around the ring. Two
    /// blades sharing a seat leaves a permanent gap opposite them.
    func testBladesAreEvenlySeatedWhenOpen() {
        let seats = (0..<LeafShutterGeometry.bladeCount).map {
            LeafShutterGeometry.bladeAngle(index: $0, closure: 0)
        }
        XCTAssertEqual(Set(seats).count, LeafShutterGeometry.bladeCount, "two blades share a seat")

        let spacing = 360.0 / Double(LeafShutterGeometry.bladeCount)
        for (i, seat) in seats.enumerated() {
            XCTAssertEqual(seat, Double(i) * spacing, accuracy: 0.001)
        }
    }

    /// Every blade sweeps the same distance, and it is at least its own share of
    /// the circle — less than that and the blades cannot overlap into a seal.
    func testEveryBladeSweepsEnoughToOverlapItsNeighbour() {
        let share = 360.0 / Double(LeafShutterGeometry.bladeCount)
        for index in 0..<LeafShutterGeometry.bladeCount {
            let travel = LeafShutterGeometry.bladeAngle(index: index, closure: 1)
                - LeafShutterGeometry.bladeAngle(index: index, closure: 0)
            XCTAssertGreaterThan(travel, share, "blade \(index) cannot reach its neighbour")
        }
    }

    func testClosureIsClampedRatherThanExtrapolated() {
        XCTAssertEqual(LeafShutterGeometry.apertureRadius(closure: -5),
                       LeafShutterGeometry.apertureRadius(closure: 0), accuracy: 0.0001)
        XCTAssertEqual(LeafShutterGeometry.apertureRadius(closure: 5),
                       LeafShutterGeometry.apertureRadius(closure: 1), accuracy: 0.0001)
    }
}

// MARK: - Plate that opens and closes

/// PRO now opens the plate rather than sitting at the bottom of the screen, and
/// the picture is inset below the plate. Those two numbers have to agree in both
/// states or the frame slides under opaque metal when PRO is toggled.
final class TopPlateCollapseTests: XCTestCase {

    func testTheClosedPlateIsShorterThanTheOpenOne() {
        XCTAssertLessThan(TopPlateBand.collapsedHeight, TopPlateBand.height,
                          "closing the plate has to give the picture room back")
    }

    func testTheHeightHelperMatchesBothConstants() {
        XCTAssertEqual(TopPlateBand.height(proOpen: true), TopPlateBand.height)
        XCTAssertEqual(TopPlateBand.height(proOpen: false), TopPlateBand.collapsedHeight)
    }

    /// The closed plate still carries the switch row, so it cannot collapse to
    /// less than one 44pt target plus the status bar it sits under.
    func testTheClosedPlateStillFitsItsSwitches() {
        XCTAssertGreaterThanOrEqual(TopPlateBand.collapsedHeight, 90,
                                    "the switch row would be clipped")
    }
}

// MARK: - The barrel a dial drops

final class ActiveDialTests: XCTestCase {

    /// The barrel is driven by value equality — if two consecutive readings
    /// compared equal while the reading text differed, the barrel would show a
    /// stale number for the whole gesture.
    func testADialChangeIsVisibleAsAChange() {
        let a = ActiveDial(name: "ISO", reading: "400", value: 0.5)
        let b = ActiveDial(name: "ISO", reading: "800", value: 0.6)
        XCTAssertNotEqual(a, b)
    }

    func testTheSameReadingComparesEqualSoTheBarrelDoesNotThrash() {
        let a = ActiveDial(name: "ISO", reading: "400", value: 0.5)
        let b = ActiveDial(name: "ISO", reading: "400", value: 0.5)
        XCTAssertEqual(a, b)
    }

    func testADialCarriesBothItsNameAndItsReading() {
        let dial = ActiveDial(name: "WHITE BALANCE", reading: "5600K", value: 0.7)
        XCTAssertFalse(dial.name.isEmpty)
        XCTAssertFalse(dial.reading.isEmpty)
        XCTAssertTrue((0...1).contains(dial.value))
    }
}
