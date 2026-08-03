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
