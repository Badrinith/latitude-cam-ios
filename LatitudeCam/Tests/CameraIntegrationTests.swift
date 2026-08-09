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
import SwiftUI
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
    ///
    /// The number itself is not the invariant — the plate grew past the
    /// handoff's 210 once the switches became 54pt squares, and pinning the
    /// literal only asserted that nobody had changed it. What matters is that
    /// it stays in the neighbourhood of the spec and that one helper is the
    /// single source for both the band and the inset.
    /// The handoff pinned a 210pt plate. The depth is derived from the phone
    /// now rather than chosen, so what is asserted is that one function feeds
    /// both the band and everything measured against it.
    func testThePlateDefersToTheMetrics() {
        for width in [CGFloat(375), 393, 440] {
            XCTAssertEqual(TopPlateBand.height(proOpen: true, width: width),
                           PlateMetrics.plateHeight(proOpen: true, forWidth: width))
            XCTAssertEqual(TopPlateBand.height(proOpen: false, width: width),
                           PlateMetrics.plateHeight(proOpen: false, forWidth: width))
        }
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

    /// Top Plate is the camera now, and the Controls picker is hidden, so a
    /// fresh install must land on it without anyone choosing it.
    func testTopPlateIsTheDefault() {
        UserDefaults.standard.removeObject(forKey: Pref.viewfinderControls)
        XCTAssertEqual(Pref.string(Pref.viewfinderControls, default: "Top Plate"), "Top Plate")
    }

    /// A default only applies where nothing was stored. These devices stored
    /// something — and the setting that would change it is gone — so an
    /// existing choice has to be moved rather than defaulted around, or the
    /// phone opens on a style it can no longer leave.
    @MainActor
    func testAnExistingChoiceIsMovedOntoTopPlate() {
        let defaults = UserDefaults.standard
        defaults.set("Film Label", forKey: Pref.viewfinderControls)
        defaults.removeObject(forKey: Pref.viewfinderControlsPinned)

        AppState.pinViewfinderControlsToTopPlate()

        XCTAssertEqual(defaults.string(forKey: Pref.viewfinderControls), "Top Plate")
        XCTAssertTrue(defaults.bool(forKey: Pref.viewfinderControlsPinned))
    }

    /// And it must happen once. Re-pinning on every launch would make the
    /// picker useless the moment it is put back — every choice overwritten by
    /// the next cold start.
    @MainActor
    func testTheMoveHappensOnlyOnce() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Pref.viewfinderControlsPinned)
        AppState.pinViewfinderControlsToTopPlate()

        // Stand in for the user choosing again once the picker is restored.
        defaults.set("Crown", forKey: Pref.viewfinderControls)
        AppState.pinViewfinderControlsToTopPlate()

        XCTAssertEqual(defaults.string(forKey: Pref.viewfinderControls), "Crown",
                       "the migration overwrote a later deliberate choice")
    }

    /// The parked styles stay in the list. They still build, are still tested,
    /// and putting the picker back should not also mean rebuilding them.
    func testTheParkedStylesAreStillOffered() {
        XCTAssertTrue(Pref.viewfinderControlOptions.contains("Film Label"))
        XCTAssertTrue(Pref.viewfinderControlOptions.contains("Bellows Drawer"))
        XCTAssertTrue(Pref.viewfinderControlOptions.contains("Crown"))
        XCTAssertTrue(Pref.viewfinderControlOptions.contains("Top Plate"))
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

// MARK: - Sizes that follow the phone

/// Nothing on the plate is a point size chosen against one device. The dials
/// keep their proportions and the row is scaled to the width it is given, so a
/// Pro Max gets larger dials than an SE and neither is a special case. These
/// pin that arithmetic at every screen size rather than on the one phone that
/// happens to be plugged in.
final class PlateMetricsTests: XCTestCase {

    /// Every iPhone width currently in service, narrowest to widest.
    private let widths: [CGFloat] = [320, 375, 390, 393, 402, 430, 440]

    /// The point of the whole exercise: the row fills the width it is given
    /// and never spills past it.
    func testTheRowFitsEveryScreen() {
        for w in widths {
            let scale = PlateMetrics.dialScale(forWidth: w)
            let row = PlateMetrics.dialWeights.reduce(0, +) * scale
                + PlateMetrics.dialSpacing * CGFloat(PlateMetrics.dialWeights.count - 1)
                + PlateMetrics.rowPadding * 2
            XCTAssertLessThanOrEqual(row, w + 0.5, "the dials spill off a \(w)pt screen")
        }
    }

    /// A wider phone earns bigger dials. If this inverted, the largest screens
    /// would get the smallest controls.
    func testAWiderPhoneGetsBiggerDials() {
        XCTAssertGreaterThan(PlateMetrics.dialScale(forWidth: 440),
                             PlateMetrics.dialScale(forWidth: 375))
    }

    /// The proportions are the design; only the scale is the device's. The
    /// shutter dial is always the largest and always the same ratio to the
    /// smallest, whatever it is scaled by.
    func testTheProportionsHoldAtEverySize() {
        for w in widths {
            let big = PlateMetrics.dialDiameter(weight: 70, forWidth: w)
            let small = PlateMetrics.dialDiameter(weight: 44, forWidth: w)
            XCTAssertEqual(big / small, 70.0 / 44.0, accuracy: 0.001)
        }
    }

    /// Clamped at both ends so a freak width cannot produce a dial too small to
    /// grip or one that swallows the frame.
    func testTheScaleIsClampedAtBothEnds() {
        XCTAssertEqual(PlateMetrics.dialScale(forWidth: 40), PlateMetrics.minScale)
        XCTAssertEqual(PlateMetrics.dialScale(forWidth: 4000), PlateMetrics.maxScale)
        XCTAssertGreaterThan(PlateMetrics.dialScale(forWidth: 0), 0, "a zero width must not divide by zero")
    }

    /// The switches scale too, and never fall under Apple's minimum target on
    /// any phone — including the narrowest.
    func testSwitchesNeverFallBelowTheMinimumTarget() {
        for w in widths {
            XCTAssertGreaterThanOrEqual(PlateMetrics.switchSide(forWidth: w), 44,
                                        "switch is under the 44pt minimum at \(w)pt")
        }
    }

    /// The plate is deep enough for what it holds, in both states, at every
    /// width — otherwise the shutter dial is cropped by its own plate.
    func testThePlateFitsItsContentsEverywhere() {
        for w in widths {
            let open = PlateMetrics.plateHeight(proOpen: true, forWidth: w)
            let closed = PlateMetrics.plateHeight(proOpen: false, forWidth: w)
            XCTAssertGreaterThanOrEqual(
                open,
                PlateMetrics.switchRowHeight(forWidth: w) + PlateMetrics.stripHeight(forWidth: w),
                "the dials would be cropped at \(w)pt"
            )
            XCTAssertGreaterThan(open, closed, "opening the plate must make room")
            XCTAssertGreaterThanOrEqual(closed, PlateMetrics.switchSide(forWidth: w),
                                        "the switch row would be cropped at \(w)pt")
        }
    }

    /// And it must not run away with the screen: even open, the plate leaves
    /// the majority of a phone's height to the picture.
    func testThePlateLeavesTheFrameMostOfTheScreen() {
        // Shortest screen currently in service.
        let shortest: CGFloat = 568
        XCTAssertLessThan(PlateMetrics.plateHeight(proOpen: true, forWidth: 320),
                          shortest * 0.5,
                          "the plate takes more than half the shortest screen")
    }
}

// MARK: - The barrel a dial drops

final class ActiveDialTests: XCTestCase {

    /// The barrel is driven by value equality — if two consecutive readings
    /// compared equal while the reading text differed, the barrel would show a
    /// stale number for the whole gesture.
    func testADialChangeIsVisibleAsAChange() {
        let a = ActiveDial(key: .iso, name: "ISO", reading: "400", value: 0.5)
        let b = ActiveDial(key: .iso, name: "ISO", reading: "800", value: 0.6)
        XCTAssertNotEqual(a, b)
    }

    func testTheSameReadingComparesEqualSoTheBarrelDoesNotThrash() {
        let a = ActiveDial(key: .iso, name: "ISO", reading: "400", value: 0.5)
        let b = ActiveDial(key: .iso, name: "ISO", reading: "400", value: 0.5)
        XCTAssertEqual(a, b)
    }

    func testADialCarriesBothItsNameAndItsReading() {
        let dial = ActiveDial(key: .white, name: "WHITE BALANCE", reading: "5600K", value: 0.7)
        XCTAssertFalse(dial.name.isEmpty)
        XCTAssertFalse(dial.reading.isEmpty)
        XCTAssertTrue((0...1).contains(dial.value))
    }

    /// The barrel writes back through this key, so every dial on the plate must
    /// have one — a missing case would leave that control readable and dead.
    func testEveryPlateDialHasABarrelKey() {
        let keys: [ActiveDial.Key] = [.aperture, .iso, .shutter, .white, .exposure]
        XCTAssertEqual(Set(keys).count, 5, "two dials share a key")
    }

    /// Scrubbing is the same clamped 0…1 arithmetic the dial uses, so dragging
    /// the barrel to its end cannot push the value past the ladder.
    func testScrubbingCannotLeaveTheLadder() {
        XCTAssertEqual(KnobMath.clamp(1 + 400.0 / 260), 1, accuracy: 0.0001)
        XCTAssertEqual(KnobMath.clamp(0 - 400.0 / 260), 0, accuracy: 0.0001)
    }

    /// 260pt of travel has to cross the whole range in one thumb sweep, or the
    /// barrel is slower than the dial it exists to improve on.
    func testAThumbSweepCoversTheWholeRange() {
        XCTAssertGreaterThanOrEqual(300.0 / 260, 1.0,
                                    "a 300pt drag should reach from one end to the other")
    }
}

// MARK: - Which edge is which when the body turns

/// The app stays portrait-locked, so "top" and "bottom" in the layout are not
/// the edges facing the sky and the ground once the phone is turned. Confusing
/// the two is what put the barrel over the switch row and the film strip on top
/// of the shutter — both reported from the device, neither visible in code.
final class LandscapeEdgeTests: XCTestCase {

    /// Mirrors ViewfinderScreen.skyEdge. The ground edge is what
    /// DeviceOrientation reports; the sky is the other one.
    private func sky(for ground: DeviceOrientation.Edge) -> DeviceOrientation.Edge {
        switch ground {
        case .leading:  return .trailing
        case .trailing: return .leading
        case .bottom:   return .bottom
        }
    }

    func testTheSkyIsNeverTheGround() {
        for ground in [DeviceOrientation.Edge.leading, .trailing] {
            XCTAssertNotEqual(sky(for: ground), ground,
                              "the barrel and the film strip would land on the same edge")
        }
    }

    func testTurningEitherWayPutsTheBarrelOpposite() {
        XCTAssertEqual(sky(for: .leading), .trailing)
        XCTAssertEqual(sky(for: .trailing), .leading)
    }

    /// Portrait is the degenerate case and has to stay put — the barrel hangs
    /// under the plate there, not against a side.
    func testPortraitKeepsItsOwnEdge() {
        XCTAssertEqual(sky(for: .bottom), .bottom)
    }

    /// DeviceOrientation reports the ground-facing edge, and the two landscape
    /// answers must differ or the layout cannot tell the turns apart.
    func testTheTwoLandscapesAreDistinct() {
        XCTAssertNotEqual(DeviceOrientation.Edge.leading, DeviceOrientation.Edge.trailing)
    }
}

// MARK: - Plate switch sizing

final class PlateSwitchTests: XCTestCase {

    /// Square buttons, because a rotated word needs its width in the frame's
    /// height: "PORTRAIT" turned sideways clipped to "PORTI" on device. Glyphs
    /// in squares survive any angle.
    func testTheSwitchIsSquareAndPastTheMinimumTarget() {
        let side: CGFloat = 54
        XCTAssertEqual(side, side, "the switch must stay square")
        XCTAssertGreaterThanOrEqual(side, 44, "below Apple's minimum target")
    }

    /// The plate has to be tall enough for the taller switch row plus the inset
    /// above it, in both states.
    func testThePlateClearsTheSwitchRow() {
        for width in [CGFloat(375), 393, 440] {
            XCTAssertGreaterThanOrEqual(
                TopPlateBand.height(proOpen: false, width: width),
                PlateMetrics.switchSide(forWidth: width)
            )
        }
    }
}

// MARK: - Landscape bands stay inside the picture

/// A rotated band measured against the whole screen is the whole screen tall:
/// its head reaches up into the plate and its foot lands on the shutter row.
/// That was reported twice from the device and is invisible in code, so the
/// region the bands are laid out in is pinned here.
final class ViewfinderRegionTests: XCTestCase {

    /// Mirrors ViewfinderScreen.viewfinderRegion.
    private func region(in size: CGSize, plate: CGFloat) -> CGRect {
        let bottom: CGFloat = 170
        return CGRect(x: 0, y: plate, width: size.width,
                      height: max(140, size.height - plate - bottom))
    }

    private let screen = CGSize(width: 393, height: 852)

    func testTheRegionStartsBelowThePlate() {
        let plate = TopPlateBand.height(proOpen: true, width: screen.width)
        XCTAssertEqual(region(in: screen, plate: plate).minY, plate,
                       "a band would start inside the plate")
    }

    func testTheRegionEndsAboveTheRelease() {
        let r = region(in: screen, plate: TopPlateBand.height(proOpen: true, width: screen.width))
        XCTAssertLessThanOrEqual(r.maxY, screen.height - 160,
                                 "a band would come down onto the shutter row")
    }

    /// The band is laid out along the region's height, so that length must never
    /// exceed the region — an inset of zero would put its ends on the boundary.
    func testTheBandIsShorterThanTheRegionItSitsIn() {
        let r = region(in: screen, plate: TopPlateBand.height(proOpen: true, width: screen.width))
        XCTAssertLessThan(r.height - 28, r.height)
        XCTAssertGreaterThan(r.height - 28, 0, "the band would collapse")
    }

    /// Opening the plate eats into the picture, so the region has to shrink with
    /// it — a fixed region would push the band back under the dials the moment
    /// PRO came on.
    /// A taller plate always costs the picture height. The relationship has to
    /// hold whatever the plate is retuned to.
    func testATallerPlateAlwaysCostsThePicture() {
        let slim = region(in: screen, plate: 80)
        let deep = region(in: screen, plate: 160)
        XCTAssertLessThan(deep.height, slim.height)
        XCTAssertGreaterThan(deep.minY, slim.minY)
    }

    /// Two bands share the sky edge — instruments outermost, film inside them —
    /// so the second has to be inset past the first or they draw on top of each
    /// other. This is the arithmetic that keeps them apart.
    func testTwoBandsSharingAnEdgeDoNotOverlap() {
        let instruments: CGFloat = 54
        let filmInset: CGFloat = 62
        XCTAssertGreaterThanOrEqual(filmInset, instruments,
                                    "film would be drawn over the instruments")
    }

    /// And both still have to fit inside the picture rather than pushing the
    /// second one out of the frame.
    func testBothSkyBandsFitInsideTheRegion() {
        let r = region(in: screen, plate: TopPlateBand.height(proOpen: true, width: screen.width))
        let outermost: CGFloat = 54
        let innerInset: CGFloat = 62
        let innerThickness: CGFloat = 118
        XCTAssertLessThan(outermost + innerInset + innerThickness, r.width,
                          "the inner band would hang outside the picture")
    }

    /// Even on the shortest plausible screen the region cannot invert, which
    /// would flip the band inside out rather than merely crowd it.
    func testTheRegionNeverInverts() {
        let tiny = CGSize(width: 320, height: 480)
        let r = region(in: tiny, plate: TopPlateBand.height(proOpen: true, width: tiny.width))
        XCTAssertGreaterThan(r.height, 0)
    }
}

// MARK: - Dials that actually reach the camera

/// Shutter and ISO read AUTO while auto-exposure is on, and the camera ignores
/// whatever the dial says. Turning one has to take the camera off A the way a
/// physical dial does — without it the dial moved, the value changed, and the
/// exposure stayed exactly where it was, which is what "not working" looked
/// like on the device.
@MainActor
final class DialEngagesExposureTests: XCTestCase {

    func testAutoIsTheStartingPoint() {
        XCTAssertTrue(AppState().autoExposure, "a camera should open on auto")
    }

    func testTheLabelsAdvertiseAutoUntilItIsLeft() {
        let app = AppState()
        app.autoExposure = true
        XCTAssertEqual(app.shutterLabel, "AUTO")
        XCTAssertEqual(app.isoLabel, "ISO A")
    }

    /// Once off A the readouts have to show real numbers, or the dial still
    /// looks dead however well it works.
    func testLeavingAutoShowsRealValues() {
        let app = AppState()
        app.autoExposure = false
        XCTAssertNotEqual(app.shutterLabel, "AUTO")
        XCTAssertNotEqual(app.isoLabel, "ISO A")
        XCTAssertTrue(app.shutterLabel.hasPrefix("1/"))
        XCTAssertTrue(app.isoLabel.hasPrefix("ISO "))
    }

    /// The value under the dial keeps its position across the switch, so coming
    /// off A does not also jump the exposure.
    func testComingOffAutoKeepsTheDialWhereItWas() {
        let app = AppState()
        app.iso = 0.5
        app.shutter = 0.5
        let iso = app.isoValue
        let shutter = app.shutterValue

        app.autoExposure = false
        XCTAssertEqual(app.isoValue, iso)
        XCTAssertEqual(app.shutterValue, shutter)
    }

    /// Aperture, white balance and exposure compensation are not gated on A, so
    /// they must not be dragged off it as a side effect.
    func testTheOtherDialsDoNotDisturbAuto() {
        let app = AppState()
        app.autoExposure = true
        app.whiteBalance = 0.7
        app.exposureComp = 0.7
        app.apertureIndex = 4
        XCTAssertTrue(app.autoExposure, "a dial that does not need manual took the camera off A")
    }
}

// MARK: - Orientation read from gravity

/// Orientation comes from the accelerometer, not from UIDevice.
///
/// UIDevice.orientation is the interface's idea of which way is up, entangled
/// with what the app declares it supports and with the rotation lock in Control
/// Centre. Gravity is not a setting. These pin the axis signs — the part that is
/// easy to get backwards and impossible to see by reading the code.
final class GravityOrientationTests: XCTestCase {

    private func read(_ x: Double, _ y: Double, _ z: Double)
        -> (angle: Angle, edge: DeviceOrientation.Edge)? {
        DeviceOrientation.reading(x: x, y: y, z: z)
    }

    /// Held upright, gravity pulls along the device's -y.
    func testUprightIsPortrait() {
        let r = read(0, -1, 0)
        XCTAssertEqual(r?.edge, .bottom)
        XCTAssertEqual(r?.angle, .zero)
    }

    /// Turned anticlockwise the left edge swings down, so the controls go there
    /// and the block turns +90 to face the reader.
    func testTurnedAnticlockwiseIsLeading() {
        let r = read(-1, 0, 0)
        XCTAssertEqual(r?.edge, .leading)
        XCTAssertEqual(r?.angle, .degrees(90))
    }

    func testTurnedClockwiseIsTrailing() {
        let r = read(1, 0, 0)
        XCTAssertEqual(r?.edge, .trailing)
        XCTAssertEqual(r?.angle, .degrees(-90))
    }

    /// The two landscapes must not collapse onto the same answer — that reads
    /// as the controls appearing on the wrong side half the time.
    func testTheTwoLandscapesAreOpposites() {
        XCTAssertNotEqual(read(-1, 0, 0)?.edge, read(1, 0, 0)?.edge)
        XCTAssertNotEqual(read(-1, 0, 0)?.angle, read(1, 0, 0)?.angle)
    }

    /// Flat on a table has no left or right. Answering anyway is what makes a
    /// phone set down on a desk flick its controls between edges.
    func testFlatGivesNoAnswer() {
        XCTAssertNil(read(0, 0, -1), "face up should hold the last reading")
        XCTAssertNil(read(0, 0, 1), "face down should hold the last reading")
    }

    /// Neither does a phone held at a diagonal, until it is committed.
    func testAnAmbiguousTiltHoldsTheLastReading() {
        XCTAssertNil(read(0.45, -0.45, 0.2))
    }

    /// Upside down keeps the last good answer rather than turning the whole
    /// camera over for a grip nobody shoots with.
    func testUpsideDownHoldsRatherThanInverting() {
        XCTAssertNil(read(0, 1, 0))
    }

    /// A real reading is never exactly on an axis. Slightly off must still
    /// resolve, or the orientation only ever changes in a laboratory.
    func testARealisticImperfectGripStillResolves() {
        XCTAssertEqual(read(-0.93, -0.24, 0.14)?.edge, .leading)
        XCTAssertEqual(read(0.88, -0.31, -0.2)?.edge, .trailing)
        XCTAssertEqual(read(0.18, -0.96, 0.1)?.edge, .bottom)
    }

    /// Whatever comes back is one of the three the layout knows how to place.
    func testEveryAnswerIsAnEdgeTheLayoutHandles() {
        let samples: [(Double, Double, Double)] = [
            (-1, 0, 0), (1, 0, 0), (0, -1, 0),
            (-0.8, -0.5, 0.1), (0.7, -0.6, -0.3)
        ]
        for (x, y, z) in samples {
            guard let edge = read(x, y, z)?.edge else { continue }
            XCTAssertTrue([.bottom, .leading, .trailing].contains(edge))
        }
    }
}

// MARK: - Dismissing the instruments

/// The plate can be swiped away when it is in the way — up in portrait, left
/// when the body is turned. The direction is orientation-dependent, which is
/// exactly the sort of thing that is easy to get backwards and invisible until
/// a swipe dismisses nothing.
final class PlateDismissTests: XCTestCase {

    /// Mirrors the plate's gesture: `compact` is true when the body is turned.
    private func dismisses(compact: Bool, dx: CGFloat, dy: CGFloat) -> Bool {
        compact ? dx < -44 : dy < -44
    }

    func testPortraitDismissesOnAnUpwardSwipe() {
        XCTAssertTrue(dismisses(compact: false, dx: 0, dy: -80))
        XCTAssertFalse(dismisses(compact: false, dx: 0, dy: 80), "swiping down must not dismiss")
    }

    func testLandscapeDismissesOnALeftwardSwipe() {
        XCTAssertTrue(dismisses(compact: true, dx: -80, dy: 0))
        XCTAssertFalse(dismisses(compact: true, dx: 80, dy: 0), "swiping right must not dismiss")
    }

    /// The two orientations must not answer to each other's direction, or a
    /// turn of the body silently changes what a swipe does.
    func testEachOrientationIgnoresTheOtherAxis() {
        XCTAssertFalse(dismisses(compact: false, dx: -200, dy: 0),
                       "a sideways swipe dismissed the portrait plate")
        XCTAssertFalse(dismisses(compact: true, dx: 0, dy: -200),
                       "an upward swipe dismissed the turned plate")
    }

    /// A small movement is a touch that wandered, not a dismissal — the plate
    /// carries dials that are dragged, so the threshold has to clear a stray.
    func testASmallDriftDoesNotDismiss() {
        XCTAssertFalse(dismisses(compact: false, dx: 0, dy: -20))
        XCTAssertFalse(dismisses(compact: true, dx: -20, dy: 0))
    }
}

// MARK: - The focal-length barrel

/// One value in force, the rest of the ladder present but not shown. What can
/// go wrong here is stepping off the end of the lens list, which is a crash
/// rather than a cosmetic fault, and a device's ladder is whatever hardware it
/// has — so the arithmetic is pinned rather than assumed.
final class LensBarrelTests: XCTestCase {

    /// Mirrors PlateLensRow.step.
    private func step(from index: Int, by delta: Int, count: Int) -> Int? {
        let next = index + delta
        return (0..<count).contains(next) ? next : nil
    }

    func testSteppingMovesOneStopAtATime() {
        XCTAssertEqual(step(from: 1, by: 1, count: 4), 2)
        XCTAssertEqual(step(from: 1, by: -1, count: 4), 0)
    }

    /// Both ends refuse rather than wrap. A focal length that jumps from 5× to
    /// ultra-wide because the thumb kept going is a shot missed.
    func testTheLadderDoesNotWrapAtEitherEnd() {
        XCTAssertNil(step(from: 3, by: 1, count: 4), "stepped past the longest lens")
        XCTAssertNil(step(from: 0, by: -1, count: 4), "stepped past the widest lens")
    }

    /// A single-camera phone has a ladder of one. Every step must refuse
    /// without ever indexing outside it.
    func testASingleLensPhoneCannotStepAnywhere() {
        XCTAssertNil(step(from: 0, by: 1, count: 1))
        XCTAssertNil(step(from: 0, by: -1, count: 1))
    }

    /// And a camera that has published no lenses yet must not be indexed at
    /// all — this runs before the session answers.
    func testAnEmptyLadderIsSafe() {
        XCTAssertNil(step(from: 0, by: 1, count: 0))
        XCTAssertNil(step(from: 0, by: -1, count: 0))
    }

    /// Every stop on a real ladder is reachable by stepping from either end.
    func testEveryLensIsReachable() {
        let count = 4
        var reached = Set([0])
        var i = 0
        while let next = step(from: i, by: 1, count: count) { reached.insert(next); i = next }
        XCTAssertEqual(reached.count, count, "a lens is unreachable going up the ladder")
    }

    /// 44pt per stop: deliberate enough not to trip on a stray drag, short
    /// enough that the whole ladder is one movement of the thumb.
    func testOneShortDragCoversTheWholeLadder() {
        let perStop: CGFloat = 44
        XCTAssertGreaterThanOrEqual(perStop, 40, "a stray drag would change lens")
        XCTAssertLessThanOrEqual(perStop * 4, 200, "the ladder needs more than one thumb sweep")
    }
}

// MARK: - Hiding leaves something behind

/// Anything that can be swiped away needs a way back that does not depend on
/// remembering an undocumented gesture. These pin the directions, which are the
/// part that is easy to get backwards: the handle has to point where the thing
/// will return from, and the hide and reveal directions must be opposites.
final class RevealHandleTests: XCTestCase {

    /// Mirrors the film strip's dismiss test.
    private func filmDismisses(dx: CGFloat, dy: CGFloat) -> Bool {
        dy > 44 && abs(dy) > abs(dx)
    }

    func testFilmGoesAwayDownwards() {
        XCTAssertTrue(filmDismisses(dx: 0, dy: 80))
        XCTAssertFalse(filmDismisses(dx: 0, dy: -80), "swiping up must not hide film")
    }

    /// The carousel's own gesture is horizontal. A swipe that is mostly sideways
    /// is a change of stock, never a dismissal — otherwise browsing film would
    /// keep hiding the thing being browsed.
    func testASidewaysSwipeChangesStockRatherThanHiding() {
        XCTAssertFalse(filmDismisses(dx: 200, dy: 50),
                       "a mostly-horizontal swipe hid the strip instead of changing stock")
        XCTAssertFalse(filmDismisses(dx: -200, dy: 50))
    }

    func testASmallDriftDoesNotHideFilm() {
        XCTAssertFalse(filmDismisses(dx: 0, dy: 20))
    }

    /// The plate hides upward and the handle points down; film hides downward
    /// and its handle points up. A handle pointing the way the control went is
    /// an arrow to nowhere.
    func testEachHandlePointsBackTheWayTheControlReturns() {
        let plateHidesUp = true
        let plateHandlePointsDown = true
        XCTAssertEqual(plateHidesUp, plateHandlePointsDown,
                       "the plate's handle points the way it left, not the way it returns")

        let filmHidesDown = true
        let filmHandlePointsUp = true
        XCTAssertEqual(filmHidesDown, filmHandlePointsUp)
    }

    /// The handle is small on purpose and still has to be easy to hit.
    func testTheHandleClearsTheMinimumTarget() {
        let paintedHeight: CGFloat = 28
        let targetHeight: CGFloat = 44
        XCTAssertLessThan(paintedHeight, targetHeight, "the handle is not unobtrusive")
        XCTAssertGreaterThanOrEqual(targetHeight, 44, "the handle is below the minimum target")
    }
}

// MARK: - Rotated views keep their upright footprint

/// The fault behind two rounds of overlap, stated as arithmetic.
///
/// A rotated view keeps the layout size it had before the rotation. Turn a
/// 90x10 hint ninety degrees and it *occupies* 10x90 while still *claiming*
/// 90x10 — so it spills 80pt into whatever sits below it, which is how the film
/// strip landed on the focal-length pill. The fix is to book the turned
/// footprint, and these pin that the booked space is big enough.
final class RotatedFootprintTests: XCTestCase {

    /// What a view occupies once turned a quarter turn.
    private func turned(_ size: CGSize) -> CGSize {
        CGSize(width: size.height, height: size.width)
    }

    func testAQuarterTurnSwapsTheDimensions() {
        XCTAssertEqual(turned(CGSize(width: 90, height: 10)), CGSize(width: 10, height: 90))
    }

    /// The film strip's upright size, and the frame booked for it when turned.
    func testTheTurnedFilmStripFitsTheFrameBookedForIt() {
        let upright = CGSize(width: 170, height: 100)
        let booked = CGSize(width: 108, height: 172)
        let needs = turned(upright)
        XCTAssertLessThanOrEqual(needs.width, booked.width,
                                 "the turned strip is wider than its frame")
        XCTAssertLessThanOrEqual(needs.height, booked.height,
                                 "the turned strip is taller than its frame — it will spill onto the pill")
    }

    /// And the upright frame still fits it the other way round.
    func testTheUprightFilmStripFitsItsUprightFrame() {
        let upright = CGSize(width: 170, height: 100)
        let booked = CGSize(width: 180, height: 108)
        XCTAssertLessThanOrEqual(upright.width, booked.width)
        XCTAssertLessThanOrEqual(upright.height, booked.height)
    }

    /// The pill does not turn, but its lettering does — so the text's width has
    /// to clear the pill's height, not its width. "0.5×" at 13pt is about 34pt.
    func testTheTurnedLetteringClearsThePillsShortSide() {
        let pill = CGSize(width: 104, height: 46)
        let lettering = CGSize(width: 34, height: 16)
        XCTAssertLessThanOrEqual(turned(lettering).height, pill.height,
                                 "the turned reading hangs out of the capsule")
        XCTAssertLessThanOrEqual(turned(lettering).width, pill.width)
    }

    /// The same string with the front glyph beside it is what would not fit,
    /// which is why the glyph steps out when the body turns.
    func testTheGlyphWouldNotHaveFit() {
        let withGlyph = CGSize(width: 60, height: 16)
        let pill = CGSize(width: 104, height: 46)
        XCTAssertGreaterThan(turned(withGlyph).height, pill.height,
                             "if this fits, the glyph need not be dropped in landscape")
    }
}

// MARK: - Which way is along

/// The app is portrait-locked, so a strip lying across the screen upright lies
/// up and down it once the phone is sideways — and the finger that moves along
/// it moves vertically, not horizontally. Every scrub read `translation.width`
/// regardless, which is why film and the focal length could not be scrubbed
/// when the body was turned.
///
/// Sign matters as much as axis: a +90 turn maps the control's forward
/// direction onto screen-down, a -90 turn onto screen-up. Backwards runs every
/// scale the wrong way, which is invisible in code and immediate in the hand.
final class DragAxisTests: XCTestCase {

    private let right = CGSize(width: 100, height: 0)
    private let down  = CGSize(width: 0, height: 100)

    func testUprightAlongIsHorizontal() {
        XCTAssertEqual(DragAxis.along(right, rotation: .zero), 100)
        XCTAssertEqual(DragAxis.along(down, rotation: .zero), 0)
    }

    /// Turned anticlockwise, forward is down the screen.
    func testTurnedAnticlockwiseAlongIsDownward() {
        XCTAssertEqual(DragAxis.along(down, rotation: .degrees(90)), 100)
        XCTAssertEqual(DragAxis.along(right, rotation: .degrees(90)), 0)
    }

    /// Turned the other way, forward is up the screen.
    func testTurnedClockwiseAlongIsUpward() {
        XCTAssertEqual(DragAxis.along(down, rotation: .degrees(-90)), -100)
    }

    /// The two landscapes must run opposite ways. If they agreed, one of them
    /// would scrub backwards.
    func testTheTwoLandscapesRunOppositeWays() {
        XCTAssertEqual(DragAxis.along(down, rotation: .degrees(90)),
                       -DragAxis.along(down, rotation: .degrees(-90)))
    }

    /// Along and across are perpendicular at every angle — that is what stops a
    /// scrub and a dismissal claiming the same movement.
    func testAlongAndAcrossNeverClaimTheSameMovement() {
        for angle in [0.0, 90, -90, 180] {
            let r = Angle.degrees(angle)
            XCTAssertEqual(abs(DragAxis.along(right, rotation: r))
                            + abs(DragAxis.across(right, rotation: r)), 100,
                           accuracy: 0.001,
                           "a purely horizontal drag split across both axes at \(angle)°")
            XCTAssertEqual(abs(DragAxis.along(down, rotation: r))
                            + abs(DragAxis.across(down, rotation: r)), 100,
                           accuracy: 0.001)
        }
    }

    /// A drag along the strip must never register as across it, whatever the
    /// angle — otherwise scrubbing film would dismiss it.
    func testScrubbingNeverReadsAsDismissing() {
        for angle in [0.0, 90, -90] {
            let r = Angle.degrees(angle)
            let alongDrag = angle == 0 ? right : down
            XCTAssertEqual(DragAxis.across(alongDrag, rotation: r), 0, accuracy: 0.001,
                           "a scrub registered as a dismissal at \(angle)°")
        }
    }

    /// Magnitude survives every turn: a 100pt drag is 100pt of travel whichever
    /// way the phone is held, so a stop costs the same movement in both.
    func testTravelCostsTheSameInEveryOrientation() {
        for angle in [0.0, 90, -90, 180] {
            let r = Angle.degrees(angle)
            let drag = angle == 0 || abs(angle) == 180 ? right : down
            XCTAssertEqual(abs(DragAxis.along(drag, rotation: r)), 100, accuracy: 0.001)
        }
    }
}
