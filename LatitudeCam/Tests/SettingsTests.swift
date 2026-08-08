//
//  SettingsTests.swift
//  LatitudeCam
//
//  Settings are plain UserDefaults strings read by the viewfinder, the render
//  pipeline and the gallery. A typo in an option list or a mismatched default
//  would leave a row that displays fine but changes nothing.
//

import XCTest
@testable import LatitudeCam

final class PreferenceMappingTests: XCTestCase {

    /// Every option a picker can offer must map to a real value; anything that
    /// falls through to a default is a row that silently does nothing.
    func testEveryAspectOptionResolves() {
        for name in Pref.aspectOptions {
            XCTAssertNotNil(Pref.aspectRatio(name), "unmapped aspect: \(name)")
        }
    }

    func testAspectRatiosAreHeightOverWidth() {
        XCTAssertEqual(Pref.aspectRatio("1:1"), 1)
        XCTAssertEqual(Pref.aspectRatio("3:2")!, 1.5, accuracy: 0.001)
        XCTAssertEqual(Pref.aspectRatio("4:3")!, 4.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(Pref.aspectRatio("16:9")!, 16.0 / 9.0, accuracy: 0.001)
    }

    func testUnknownAspectKeepsTheSensorFrame() {
        XCTAssertNil(Pref.aspectRatio("Original"))
        XCTAssertNil(Pref.aspectRatio(""))
    }

    func testJPEGQualityOptionsAreDistinctAndOrdered() {
        let maximum = Pref.compressionQuality("Maximum")
        let high = Pref.compressionQuality("High")
        let balanced = Pref.compressionQuality("Balanced")

        XCTAssertGreaterThan(maximum, high)
        XCTAssertGreaterThan(high, balanced)
        for q in [maximum, high, balanced] {
            XCTAssertGreaterThan(q, 0)
            XCTAssertLessThanOrEqual(q, 1)
        }
    }

    func testUnknownJPEGQualityFallsBackToHigh() {
        XCTAssertEqual(Pref.compressionQuality("nonsense"), Pref.compressionQuality("High"))
    }

    func testEveryPeakingColourIsDistinct() {
        var seen = Set<String>()
        for name in Pref.peakingColorOptions {
            let tint = Pref.peakingTint(name)
            let key = "\(tint.r)-\(tint.g)-\(tint.b)"
            XCTAssertFalse(seen.contains(key), "duplicate tint for \(name)")
            seen.insert(key)
        }
    }

    func testUnknownPeakingColourFallsBackToAmber() {
        let fallback = Pref.peakingTint("nonsense")
        let amber = Pref.peakingTint("Amber")
        XCTAssertEqual(fallback.r, amber.r, accuracy: 0.001)
        XCTAssertEqual(fallback.g, amber.g, accuracy: 0.001)
        XCTAssertEqual(fallback.b, amber.b, accuracy: 0.001)
    }

    func testGridOptionsIncludeAnOffSwitch() {
        XCTAssertTrue(Pref.gridOptions.contains("Off"))
        XCTAssertTrue(Pref.gridOptions.contains("Rule of Thirds"))
    }

    func testRawCaptureOptionsOfferSensorAndProRAWPaths() {
        XCTAssertEqual(Pref.rawCaptureSourceOptions, ["Sensor RAW", "Apple ProRAW"])
        XCTAssertEqual(
            CameraManager.RawCaptureSource(rawValue: Pref.rawCaptureSourceOptions[0]),
            .sensor
        )
        XCTAssertEqual(
            CameraManager.RawCaptureSource(rawValue: Pref.rawCaptureSourceOptions[1]),
            .appleProRAW
        )
    }

    func testStringReadsDefaultsAndFallsBack() {
        let key = "settings.testOnly"
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(Pref.string(key, default: "fallback"), "fallback")

        UserDefaults.standard.set("stored", forKey: key)
        XCTAssertEqual(Pref.string(key, default: "fallback"), "stored")
        UserDefaults.standard.removeObject(forKey: key)
    }
}

final class CaptureOrientationTests: XCTestCase {

    func testLandscapeCaptureMapsToEXIFOrientation() {
        XCTAssertEqual(
            CameraManager.exifOrientation(forCaptureRotation: 90),
            CGImagePropertyOrientation.right.rawValue
        )
        XCTAssertEqual(
            CameraManager.exifOrientation(forCaptureRotation: -90),
            CGImagePropertyOrientation.left.rawValue
        )
    }

    func testPortraitCaptureKeepsEXIFUpright() {
        XCTAssertEqual(
            CameraManager.exifOrientation(forCaptureRotation: 0),
            CGImagePropertyOrientation.up.rawValue
        )
    }
}

// MARK: - Aspect cropping

final class AspectCropTests: XCTestCase {

    /// Scale 1 so the assertions below can talk in pixels. The default renderer
    /// scale is the device's, which would make a 100pt image 300px wide.
    private func image(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testNilRatioReturnsTheSameImage() {
        let original = image(width: 100, height: 50)
        let out = original.centerCropped(toHeightOverWidth: nil)
        XCTAssertEqual(out.cgImage?.width, original.cgImage?.width)
        XCTAssertEqual(out.cgImage?.height, original.cgImage?.height)
    }

    func testSquareCropOfALandscapeFrameTakesTheHeight() {
        let out = image(width: 100, height: 50).centerCropped(toHeightOverWidth: 1)
        XCTAssertEqual(out.cgImage?.width, 50)
        XCTAssertEqual(out.cgImage?.height, 50)
    }

    /// A portrait sensor frame at 3:2 should keep full width and lose height —
    /// the common case for this app, since the preview is rotated to portrait.
    func testPortraitFrameCropsHeightNotWidth() {
        let out = image(width: 1080, height: 1920).centerCropped(toHeightOverWidth: 1.5)
        XCTAssertEqual(out.cgImage?.width, 1080)
        XCTAssertEqual(out.cgImage?.height, 1620)
    }

    func testCropNeverGrowsTheImage() {
        let original = image(width: 200, height: 100)
        for name in Pref.aspectOptions {
            let out = original.centerCropped(toHeightOverWidth: Pref.aspectRatio(name))
            XCTAssertLessThanOrEqual(out.cgImage!.width, 200, name)
            XCTAssertLessThanOrEqual(out.cgImage!.height, 100, name)
        }
    }

    func testDegenerateRatioIsIgnored() {
        let original = image(width: 100, height: 50)
        let out = original.centerCropped(toHeightOverWidth: 0)
        XCTAssertEqual(out.cgImage?.width, 100)
        XCTAssertEqual(out.cgImage?.height, 50)
    }
}
