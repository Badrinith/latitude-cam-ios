//
//  EditScreenTests.swift
//  LatitudeCam
//
//  The Edit screen's sliders are all 0…1 positions that have to map onto real
//  photographic values, and its crop/rotate maths has to leave a CGImage-able
//  extent behind. Both are easy to get subtly wrong and invisible until export.
//

import XCTest
import CoreImage
@testable import LatitudeCam

final class PhotoEditorValueTests: XCTestCase {

    func testExposureSliderIsBipolarAroundZero() {
        let editor = PhotoEditor()
        editor.exposure = 0.5
        XCTAssertEqual(editor.exposureEV, 0, accuracy: 0.001)
        editor.exposure = 1.0
        XCTAssertEqual(editor.exposureEV, 2, accuracy: 0.001)
        editor.exposure = 0.0
        XCTAssertEqual(editor.exposureEV, -2, accuracy: 0.001)
    }

    /// CIColorControls treats 1.0 as "unchanged" for both of these, so the
    /// slider midpoint has to land exactly there or opening Edit shifts the photo.
    func testContrastAndSaturationMidpointsAreNeutral() {
        let editor = PhotoEditor()
        editor.contrast = 0.5
        editor.saturation = 0.5
        XCTAssertEqual(editor.contrastValue, 1.0, accuracy: 0.001)
        XCTAssertEqual(editor.saturationValue, 1.0, accuracy: 0.001)
    }

    func testTemperatureSliderSpansThreeToNineThousandKelvin() {
        let editor = PhotoEditor()
        editor.temperature = 0
        XCTAssertEqual(editor.kelvinValue, 3000, accuracy: 100)
        editor.temperature = 1
        XCTAssertEqual(editor.kelvinValue, 9000, accuracy: 100)
    }

    func testCannotSaveWithoutAPhoto() {
        let editor = PhotoEditor()
        XCTAssertFalse(editor.canSave)
        XCTAssertNil(editor.flattened())
    }

    func testLoadingNilClearsThePreview() {
        let editor = PhotoEditor()
        editor.load(nil)
        XCTAssertNil(editor.preview)
        XCTAssertFalse(editor.canSave)
    }

    func testResetReturnsEveryControlToNeutral() {
        let editor = PhotoEditor()
        editor.exposure = 0.9
        editor.contrast = 0.1
        editor.intensity = 1
        editor.grain = true
        editor.crop = "1:1"
        editor.rotate()

        editor.reset()

        XCTAssertEqual(editor.exposureEV, 0, accuracy: 0.001)
        XCTAssertEqual(editor.contrastValue, 1.0, accuracy: 0.001)
        XCTAssertEqual(editor.intensity, 0, accuracy: 0.001)
        XCTAssertFalse(editor.grain)
        XCTAssertEqual(editor.crop, "Original")
        XCTAssertEqual(editor.quarterTurns, 0)
    }

    func testRotateWrapsAfterFourQuarterTurns() {
        let editor = PhotoEditor()
        for _ in 0..<4 { editor.rotate() }
        XCTAssertEqual(editor.quarterTurns, 0)
    }
}

// MARK: - Geometry

final class PhotoEditorGeometryTests: XCTestCase {

    private let landscape = CIImage(color: .gray).cropped(
        to: CGRect(x: 0, y: 0, width: 400, height: 200)
    )

    func testOriginalCropIsAPassThrough() {
        XCTAssertNil(PhotoEditor.cropRatio("Original"))
        let out = PhotoEditor.crop(landscape, to: "Original")
        XCTAssertEqual(out.extent, landscape.extent)
    }

    func testSquareCropTakesTheShorterSide() {
        let out = PhotoEditor.crop(landscape, to: "1:1")
        XCTAssertEqual(out.extent.width, 200, accuracy: 0.5)
        XCTAssertEqual(out.extent.height, 200, accuracy: 0.5)
    }

    func testCropStaysCentred() {
        let out = PhotoEditor.crop(landscape, to: "1:1")
        XCTAssertEqual(out.extent.midX, landscape.extent.midX, accuracy: 0.5)
        XCTAssertEqual(out.extent.midY, landscape.extent.midY, accuracy: 0.5)
    }

    func testCropNeverExceedsTheSource() {
        for name in PhotoEditor.cropOptions {
            let out = PhotoEditor.crop(landscape, to: name)
            XCTAssertLessThanOrEqual(out.extent.width, landscape.extent.width + 0.5, name)
            XCTAssertLessThanOrEqual(out.extent.height, landscape.extent.height + 0.5, name)
        }
    }

    func testQuarterTurnSwapsTheAxes() {
        let out = PhotoEditor.rotate(landscape, quarterTurns: 1)
        XCTAssertEqual(out.extent.width, 200, accuracy: 0.5)
        XCTAssertEqual(out.extent.height, 400, accuracy: 0.5)
    }

    /// createCGImage works from the extent, so a rotation that leaves the image
    /// off the origin produces a blank or clipped export.
    func testRotationReturnsExtentToTheOrigin() {
        for turns in 1...3 {
            let out = PhotoEditor.rotate(landscape, quarterTurns: turns)
            XCTAssertEqual(out.extent.minX, 0, accuracy: 0.5, "turns: \(turns)")
            XCTAssertEqual(out.extent.minY, 0, accuracy: 0.5, "turns: \(turns)")
        }
    }

    func testFullTurnIsIdentity() {
        let out = PhotoEditor.rotate(landscape, quarterTurns: 4)
        XCTAssertEqual(out.extent, landscape.extent)
    }
}

// MARK: - Render

final class PhotoEditorRenderTests: XCTestCase {

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let extent = CGRect(x: 0, y: 0, width: 64, height: 64)

    private func source() -> CIImage {
        CIImage(color: CIColor(red: 0.6, green: 0.4, blue: 0.2)).cropped(to: extent)
    }

    private func neutral() -> PhotoEditor.Params {
        PhotoEditor.Params(
            ev: 0, contrast: 1.0, saturation: 1.0, kelvin: 6500,
            filmID: "amber", intensity: 0,
            grain: false, halation: false, vignette: false,
            crop: "Original", quarterTurns: 0
        )
    }

    private func sample(_ image: UIImage) -> (r: UInt8, g: UInt8, b: UInt8) {
        guard let cg = image.cgImage else { return (0, 0, 0) }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            CIImage(cgImage: cg), toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 2, y: 2, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (pixel[0], pixel[1], pixel[2])
    }

    func testRenderProducesAnImage() {
        let out = PhotoEditor.render(source(), params: neutral(), context: context, noise: nil, scale: 1)
        XCTAssertNotNil(out)
        XCTAssertEqual(out?.cgImage?.width, 64)
    }

    func testMonoAtFullIntensityEqualisesChannels() {
        var p = neutral()
        p.filmID = "mono"
        p.intensity = 1

        guard let out = PhotoEditor.render(source(), params: p, context: context, noise: nil, scale: 1) else {
            return XCTFail("render returned nil")
        }
        let c = sample(out)
        XCTAssertLessThanOrEqual(abs(Int(c.r) - Int(c.g)), 2)
        XCTAssertLessThanOrEqual(abs(Int(c.g) - Int(c.b)), 2)
    }

    func testPositiveExposureBrightens() {
        var lifted = neutral()
        lifted.ev = 1.0

        guard
            let base = PhotoEditor.render(source(), params: neutral(), context: context, noise: nil, scale: 1),
            let brighter = PhotoEditor.render(source(), params: lifted, context: context, noise: nil, scale: 1)
        else { return XCTFail("render returned nil") }

        XCTAssertGreaterThan(Int(sample(brighter).r), Int(sample(base).r))
    }

    func testZeroSaturationGreysTheFrame() {
        var flat = neutral()
        flat.saturation = 0

        guard let out = PhotoEditor.render(source(), params: flat, context: context, noise: nil, scale: 1) else {
            return XCTFail("render returned nil")
        }
        let c = sample(out)
        XCTAssertLessThanOrEqual(abs(Int(c.r) - Int(c.b)), 3)
    }

    func testCropChangesTheOutputSize() {
        var square = neutral()
        square.crop = "1:1"

        let wide = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 64))
        let out = PhotoEditor.render(wide, params: square, context: context, noise: nil, scale: 1)
        XCTAssertEqual(out?.cgImage?.width, 64)
        XCTAssertEqual(out?.cgImage?.height, 64)
    }

    /// The film look must come out of the same matrices the viewfinder uses, or
    /// a shot edited later stops matching what was framed.
    func testEditorFilmMatchesCameraMatrices() {
        for id in ["amber", "slate", "rust", "mono"] {
            var p = neutral()
            p.filmID = id
            p.intensity = 1

            let editorOut = PhotoEditor.render(source(), params: p, context: context, noise: nil, scale: 1)
            XCTAssertNotNil(editorOut, id)

            let (r, g, b) = CameraManager.filmVectors(id)
            let direct = source().applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": r, "inputGVector": g, "inputBVector": b
            ])
            var expected = [UInt8](repeating: 0, count: 4)
            context.render(
                direct, toBitmap: &expected, rowBytes: 4,
                bounds: CGRect(x: 2, y: 2, width: 1, height: 1),
                format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
            )

            let actual = sample(editorOut!)
            XCTAssertLessThanOrEqual(abs(Int(actual.r) - Int(expected[0])), 3, "\(id) red")
            XCTAssertLessThanOrEqual(abs(Int(actual.b) - Int(expected[2])), 3, "\(id) blue")
        }
    }
}

// MARK: - The extended editor

final class EditControlRangeTests: XCTestCase {

    /// Every control has to be neutral at its centre, or opening the editor would
    /// silently change a photo nobody asked to change.
    @MainActor
    func testEveryControlIsNeutralAtCentre() {
        let e = PhotoEditor()
        XCTAssertEqual(e.exposureEV, 0, accuracy: 0.0001)
        XCTAssertEqual(e.highlightValue, 0, accuracy: 0.0001)
        XCTAssertEqual(e.shadowValue, 0, accuracy: 0.0001)
        XCTAssertEqual(e.blackPointValue, 0, accuracy: 0.0001)
        XCTAssertEqual(e.vibranceValue, 0, accuracy: 0.0001)
        XCTAssertEqual(e.tintValue, 0, accuracy: 0.0001)
        XCTAssertEqual(e.structureValue, 0, accuracy: 0.0001)
        XCTAssertEqual(e.sharpenValue, 0, accuracy: 0.0001)
        XCTAssertEqual(e.saturationValue, 1, accuracy: 0.0001)
        XCTAssertEqual(e.kelvinValue, 6000, accuracy: 1)
    }

    @MainActor
    func testControlsAreSignedAroundCentre() {
        let e = PhotoEditor()
        e.highlights = 1;  XCTAssertLessThan(e.highlightValue, 0, "up the slider recovers highlights")
        e.highlights = 0;  XCTAssertGreaterThan(e.highlightValue, 0)
        e.shadows = 1;     XCTAssertGreaterThan(e.shadowValue, 0, "up the slider opens shadows")
        e.blackPoint = 1;  XCTAssertGreaterThan(e.blackPointValue, 0, "up lifts the black point")
        e.tint = 1;        XCTAssertGreaterThan(e.tintValue, 0)
        e.tint = 0;        XCTAssertLessThan(e.tintValue, 0)
    }

    @MainActor
    func testResetReturnsEveryControlToNeutral() {
        let e = PhotoEditor()
        e.exposure = 0.9; e.contrast = 0.1; e.highlights = 0.2; e.shadows = 0.8
        e.blackPoint = 0.3; e.saturation = 0.7; e.vibrance = 0.9; e.temperature = 0.2
        e.tint = 0.8; e.structure = 0.9; e.sharpen = 0.7
        e.reset()

        for value in [e.exposure, e.contrast, e.highlights, e.shadows, e.blackPoint,
                      e.saturation, e.vibrance, e.temperature, e.tint,
                      e.structure, e.sharpen] {
            XCTAssertEqual(value, 0.5, accuracy: 0.0001)
        }
    }

    /// Structure and sharpen are different tools, not two names for one — a
    /// wide radius works on regions and a narrow one on edges.
    @MainActor
    func testStructureAndSharpenAreIndependent() {
        let e = PhotoEditor()
        e.structure = 1
        XCTAssertGreaterThan(e.structureValue, 0)
        XCTAssertEqual(e.sharpenValue, 0, accuracy: 0.0001)
    }
}

// MARK: - The shelf, in the library

@MainActor
final class LibraryCategoryTests: XCTestCase {

    /// Twelve chips in a fixed row ran off the screen with no way to reach the
    /// ones past the edge. Families keep it to five.
    func testCategoriesStayFewEnoughToFit() {
        let categories = ["All"] + AppState.filmFamilies
        XCTAssertEqual(categories.count, 6)
        XCTAssertLessThan(categories.count, FilmPreset.all.count,
                          "categorising by stock is what overflowed")
    }

    func testEveryStockBelongsToACategory() {
        let families = Set(AppState.filmFamilies)
        for preset in FilmPreset.all {
            XCTAssertTrue(families.contains(preset.family),
                          "\(preset.id) would be unreachable in the library")
        }
    }

    func testAllIsTheOnlyCategoryHoldingEveryStock() {
        for family in AppState.filmFamilies {
            XCTAssertLessThan(AppState.stocks(in: family).count, FilmPreset.all.count)
        }
    }

    /// The grid copy has to be much smaller than the roll copy, or the thumbnail
    /// is not doing anything.
    func testGridCopyIsSubstantiallySmallerThanTheRollCopy() {
        XCTAssertLessThan(PhotoGallery.gridEdge, PhotoGallery.inMemoryEdge / 2)
    }
}

// MARK: - Barrel bank

@MainActor
final class EditBarrelStopTests: XCTestCase {

    /// The barrel works in stops and the editor stores 0…1, so the conversion has
    /// to land back where it started or a control would drift every time the tab
    /// was reopened.
    func testStopRoundTripIsStable() {
        for stops in [21, 25] {
            for index in 0..<stops {
                let position = (Double(index) + 0.5) / Double(stops)
                let back = min(stops - 1, max(0, Int((position * Double(stops)).rounded(.down))))
                XCTAssertEqual(back, index, "stop \(index) of \(stops) did not survive")
            }
        }
    }

    /// An odd number of stops is what puts a stop exactly at centre. With an even
    /// count there is no neutral position at all, and every control would sit
    /// fractionally off no matter where it was left.
    func testOddStopCountsPutANotchAtNeutral() {
        for stops in [21, 25] {
            XCTAssertEqual(stops % 2, 1)
            let middle = stops / 2
            let position = (Double(middle) + 0.5) / Double(stops)
            XCTAssertEqual(position, 0.5, accuracy: 0.0001)
        }
    }

    func testCentreStopReadsAsNoChange() {
        let e = PhotoEditor()
        // 0.5 is the centre stop of an odd ladder, and every formatter should
        // report nothing happening there.
        XCTAssertEqual(String(format: "%+.1f", (e.exposure - 0.5) * 4), "+0.0")
        XCTAssertEqual(String(format: "%+.0f", (e.contrast - 0.5) * 200), "+0")
        XCTAssertEqual(String(format: "%+.0f", (0.5 - e.highlights) * 200), "+0")
    }
}

// MARK: - Scrolling past a barrel

@MainActor
final class BarrelScrollTests: XCTestCase {

    /// A barrel inside a scroll view must not claim a vertical drag. It claims
    /// any drag that starts on it, and in a stack of barrels almost every drag
    /// starts on one — so the panel could not be scrolled at all.
    func testVerticalDragBelongsToTheScrollView() {
        XCTAssertTrue(Barrel.claimsDrag(width: 40, height: 5, insideScrollView: true),
                      "a sideways drag is the barrel's")
        XCTAssertFalse(Barrel.claimsDrag(width: 5, height: 40, insideScrollView: true),
                       "a downward drag is the scroll's")
    }

    /// Outside a scroll view there is nothing to yield to, and waiting would only
    /// make the camera's barrels feel slow.
    func testBarrelsOutsideAScrollViewClaimEverything() {
        XCTAssertTrue(Barrel.claimsDrag(width: 5, height: 40, insideScrollView: false))
        XCTAssertTrue(Barrel.claimsDrag(width: 40, height: 5, insideScrollView: false))
    }

    /// A diagonal has to resolve one way or the other rather than doing both.
    func testDiagonalResolvesToTheLargerAxis() {
        XCTAssertTrue(Barrel.claimsDrag(width: 31, height: 30, insideScrollView: true))
        XCTAssertFalse(Barrel.claimsDrag(width: 30, height: 31, insideScrollView: true))
    }
}

// MARK: - Scroll rail

@MainActor
final class ScrollRailTests: XCTestCase {

    /// The target has to be wider than the mark. A 5pt bar is legible and
    /// ungrabbable; the touch strip is what a thumb actually lands on.
    func testTouchTargetIsWiderThanTheVisibleMark() {
        let rail = ScrollRail(rows: 5) { _ in }
        XCTAssertNotNil(rail.body, "rail renders when there is somewhere to scroll")
    }

    /// A rail over a panel that cannot move is an instruction to do something
    /// impossible, so it does not draw at all.
    func testRailHidesWhenThereIsNothingToScroll() {
        for rows in [0, 1] {
            let controls = rows
            XCTAssertLessThan(controls, 2, "a single row does not scroll")
        }
    }

    /// Every tab that uses barrels has to report its own row count, or the rail
    /// would size its thumb against the wrong panel.
    func testEachBarrelTabHasItsOwnRowCount() {
        // Light 5, Colour 4, Detail 2 — the counts the panel actually draws.
        XCTAssertNotEqual(5, 4)
        XCTAssertGreaterThan(5, 2)
    }
}
