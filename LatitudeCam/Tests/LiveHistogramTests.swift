//
//  LiveHistogramTests.swift
//  LatitudeCam
//
//  The histogram is a shooting aid, so being wrong is worse than being absent —
//  a mis-scaled or mis-ordered distribution actively misleads exposure choices.
//

import XCTest
import CoreImage
@testable import LatitudeCam

final class HistogramNormalisationTests: XCTestCase {

    func testNormalisePutsThePeakAtOne() {
        let out = HistogramSampler.normalise([1, 2, 4])
        XCTAssertEqual(out[0], 0.25, accuracy: 0.001)
        XCTAssertEqual(out[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(out[2], 1.0, accuracy: 0.001)
    }

    /// An all-black frame produces an all-zero channel; dividing by that peak
    /// would emit NaN and blank the whole overlay.
    func testNormaliseHandlesAnAllZeroChannel() {
        let out = HistogramSampler.normalise([0, 0, 0])
        XCTAssertEqual(out, [0, 0, 0])
        XCTAssertFalse(out.contains { $0.isNaN })
    }

    func testNormalisePreservesLength() {
        XCTAssertEqual(HistogramSampler.normalise([Double](repeating: 3, count: 32)).count, 32)
    }

    func testEmptyDataHasTheRequestedBinCount() {
        let empty = LiveHistogramData.empty(bins: 32)
        XCTAssertEqual(empty.luma.count, 32)
        XCTAssertEqual(empty.red.count, 32)
        XCTAssertEqual(empty.green.count, 32)
        XCTAssertEqual(empty.blue.count, 32)
        XCTAssertEqual(empty.brightness, 0)
    }

    /// An empty histogram is indistinguishable from a black frame by brightness
    /// alone, and the badge must not accuse the user of underexposing nothing.
    func testEmptyDataIsNotMistakenForAFrame() {
        XCTAssertFalse(LiveHistogramData.empty(bins: 32).hasData)
    }

    func testARealFrameReportsHavingData() {
        let context = CIContext(options: [.cacheIntermediates: false])
        let image = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        XCTAssertTrue(HistogramSampler.histogram(of: image, bins: 32, context: context).hasData)
    }
}

// MARK: - Exposure verdict

final class ExposureVerdictTests: XCTestCase {

    func testVerdictBoundaries() {
        XCTAssertEqual(HistogramEngine.exposureVerdict(brightness: 0), "Under")
        XCTAssertEqual(HistogramEngine.exposureVerdict(brightness: 84), "Under")
        XCTAssertEqual(HistogramEngine.exposureVerdict(brightness: 85), "Good")
        XCTAssertEqual(HistogramEngine.exposureVerdict(brightness: 170), "Good")
        XCTAssertEqual(HistogramEngine.exposureVerdict(brightness: 171), "Over")
        XCTAssertEqual(HistogramEngine.exposureVerdict(brightness: 255), "Over")
    }

    /// The per-pixel reference path and the live path must agree on the verdict,
    /// or the badge contradicts itself depending on which one produced it.
    func testLiveDataUsesTheSameVerdict() {
        let data = LiveHistogramData(
            luma: [], red: [], green: [], blue: [], brightness: 200
        )
        XCTAssertEqual(data.exposure, "Over")
        XCTAssertEqual(data.exposure, HistogramEngine.exposureVerdict(brightness: 200))
    }
}

// MARK: - Sampling real images

final class HistogramSamplingTests: XCTestCase {

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let bins = 32

    private func solid(_ color: CIColor) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
    }

    private func peakBin(_ buckets: [Double]) -> Int {
        buckets.enumerated().max { $0.element < $1.element }?.offset ?? -1
    }

    func testBucketCountMatchesRequestedBins() {
        let data = HistogramSampler.histogram(of: solid(.gray), bins: bins, context: context)
        XCTAssertEqual(data.luma.count, bins)
        XCTAssertEqual(data.red.count, bins)
    }

    func testBlackFrameLandsInTheLowestBin() {
        let data = HistogramSampler.histogram(of: solid(.black), bins: bins, context: context)
        XCTAssertEqual(peakBin(data.luma), 0)
    }

    func testWhiteFrameLandsInTheHighestBin() {
        let data = HistogramSampler.histogram(of: solid(.white), bins: bins, context: context)
        XCTAssertEqual(peakBin(data.luma), bins - 1)
    }

    func testBlackAndWhiteSitAtOppositeEnds() {
        let dark = HistogramSampler.histogram(of: solid(.black), bins: bins, context: context)
        let light = HistogramSampler.histogram(of: solid(.white), bins: bins, context: context)
        XCTAssertLessThan(peakBin(dark.luma), peakBin(light.luma))
        XCTAssertLessThan(dark.brightness, light.brightness)
    }

    func testBrightnessTracksTheFrame() {
        let dark = HistogramSampler.histogram(of: solid(.black), bins: bins, context: context)
        let light = HistogramSampler.histogram(of: solid(.white), bins: bins, context: context)
        XCTAssertLessThan(dark.brightness, 85, "a black frame should read as underexposed")
        XCTAssertGreaterThan(light.brightness, 170, "a white frame should read as overexposed")
    }

    func testValuesAreNormalisedIntoRange() {
        let data = HistogramSampler.histogram(of: solid(.gray), bins: bins, context: context)
        for channel in [data.luma, data.red, data.green, data.blue] {
            for value in channel {
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThanOrEqual(value, 1)
                XCTAssertFalse(value.isNaN)
            }
        }
    }

    /// CIImage(color:) is infinite until cropped; handing that straight to
    /// CIAreaHistogram would ask it to count an unbounded region.
    func testInfiniteExtentIsRejectedRatherThanCrashing() {
        let data = HistogramSampler.histogram(of: CIImage(color: .gray), bins: bins, context: context)
        XCTAssertEqual(data.luma.count, bins)
        XCTAssertEqual(data.brightness, 0)
    }

    func testSamplerStartsEmpty() {
        let sampler = HistogramSampler(bins: bins)
        XCTAssertEqual(sampler.bins, bins)
        XCTAssertEqual(sampler.data.luma.count, bins)
        XCTAssertEqual(sampler.data.brightness, 0)
    }
}
