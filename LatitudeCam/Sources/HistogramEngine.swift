//
//  HistogramEngine.swift
//  LatitudeCam
//
//  Exposure analysis. Two paths: a per-pixel reference used by tests and batch
//  work, and a GPU path fast enough to run against the live camera.
//

import Foundation
import UIKit
import CoreImage
import Combine
import Metal

public class HistogramEngine {
    public struct HistogramData {
        public let redBuckets: [Int]
        public let greenBuckets: [Int]
        public let blueBuckets: [Int]
        public let brightness: Int
        public let exposure: String  // "Under", "Good", "Over"
    }

    private let bucketCount = 256

    public func generateHistogram(from pixels: [Pixel]) -> HistogramData {
        var redBuckets = Array(repeating: 0, count: bucketCount)
        var greenBuckets = Array(repeating: 0, count: bucketCount)
        var blueBuckets = Array(repeating: 0, count: bucketCount)

        for pixel in pixels {
            redBuckets[pixel.r] += 1
            greenBuckets[pixel.g] += 1
            blueBuckets[pixel.b] += 1
        }

        let totalBrightness = pixels.reduce(0) { $0 + ($1.r + $1.g + $1.b) / 3 }
        let avgBrightness = pixels.isEmpty ? 0 : totalBrightness / pixels.count

        return HistogramData(
            redBuckets: redBuckets,
            greenBuckets: greenBuckets,
            blueBuckets: blueBuckets,
            brightness: avgBrightness,
            exposure: Self.exposureVerdict(brightness: avgBrightness)
        )
    }

    public static func exposureVerdict(brightness: Int) -> String {
        if brightness < 85 { return "Under" }
        if brightness > 170 { return "Over" }
        return "Good"
    }
}

// MARK: - Live histogram

/// One frame's worth of distribution, already normalised to 0…1 so the view can
/// draw it without knowing the pixel count.
public struct LiveHistogramData: Equatable {
    public var luma: [Double]
    public var red: [Double]
    public var green: [Double]
    public var blue: [Double]
    /// Mean luma on the familiar 0…255 scale.
    public var brightness: Int

    /// False before the first frame lands. Without this the empty histogram
    /// reads as a pitch-black scene and the badge claims "UNDER".
    public var hasData: Bool { luma.contains { $0 > 0 } }

    public var exposure: String { HistogramEngine.exposureVerdict(brightness: brightness) }

    /// What a reflected-light meter is trying to put the scene at. 18% grey lands
    /// near 118 once sRGB's transfer curve is applied, not at 128 — metering to
    /// the middle of the number line rather than the middle of the tones would
    /// read about a third of a stop hot on every frame.
    public static let midGrey: Double = 118

    /// Deviation from that target in stops. Negative is under.
    public var deviationStops: Double {
        guard hasData, brightness > 0 else { return 0 }
        return log2(Double(brightness) / Self.midGrey)
    }

    /// Within a third of a stop is the width of the target, not a rounding
    /// tolerance: closer than that and no one can see the difference anyway.
    public var isWellExposed: Bool { abs(deviationStops) < 0.33 }

    public static func empty(bins: Int) -> LiveHistogramData {
        let zeros = [Double](repeating: 0, count: bins)
        return .init(luma: zeros, red: zeros, green: zeros, blue: zeros, brightness: 0)
    }
}

/// Computes histograms from live camera frames.
///
/// Two things keep this cheap enough to sit on a 30fps stream: `CIAreaHistogram`
/// does the counting on the GPU (a Swift loop over two million pixels per frame
/// is not viable), and sampling is throttled well below the frame rate — a
/// shooting aid does not need to update 30 times a second.
public final class HistogramSampler: ObservableObject {

    @Published public private(set) var data: LiveHistogramData

    public let bins: Int
    private let context: CIContext
    private let interval: CFTimeInterval
    private let workQueue = DispatchQueue(label: "com.latitude.histogram", qos: .utility)

    private var lastSample: CFTimeInterval = 0
    private var inFlight = false
    private var cancellable: AnyCancellable?

    public init(bins: Int = 32, samplesPerSecond: Double = 5) {
        self.bins = bins
        self.interval = 1.0 / max(1, samplesPerSecond)
        self.data = .empty(bins: bins)
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }
    }

    /// Subscribe to a frame buffer. The sampler republishes at its own rate, so
    /// views observe this object rather than the 30fps source.
    public func follow(_ frames: FrameBuffer) {
        cancellable = frames.$image
            .compactMap { $0?.cgImage }
            .sink { [weak self] cgImage in self?.ingest(cgImage) }
    }

    private func ingest(_ cgImage: CGImage) {
        let now = CACurrentMediaTime()
        guard !inFlight, now - lastSample >= interval else { return }
        lastSample = now
        inFlight = true

        workQueue.async { [weak self] in
            guard let self else { return }
            let sampled = Self.histogram(
                of: CIImage(cgImage: cgImage), bins: self.bins, context: self.context
            )
            DispatchQueue.main.async {
                self.data = sampled
                self.inFlight = false
            }
        }
    }

    // MARK: - Computation

    public static func histogram(of image: CIImage, bins: Int, context: CIContext) -> LiveHistogramData {
        guard !image.extent.isInfinite, image.extent.width >= 1, image.extent.height >= 1 else {
            return .empty(bins: bins)
        }

        guard let counts = areaHistogram(of: image, bins: bins, context: context) else {
            return .empty(bins: bins)
        }

        var red = [Double](repeating: 0, count: bins)
        var green = [Double](repeating: 0, count: bins)
        var blue = [Double](repeating: 0, count: bins)
        var luma = [Double](repeating: 0, count: bins)

        for i in 0..<bins {
            let r = Double(counts[i * 4 + 0])
            let g = Double(counts[i * 4 + 1])
            let b = Double(counts[i * 4 + 2])
            red[i] = r
            green[i] = g
            blue[i] = b
            luma[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }

        // Mean luma comes from the bucket distribution: each bin's midpoint
        // weighted by how much of the frame landed in it.
        let total = luma.reduce(0, +)
        var brightness = 0.0
        if total > 0 {
            for i in 0..<bins {
                let midpoint = (Double(i) + 0.5) / Double(bins) * 255
                brightness += midpoint * luma[i] / total
            }
        }

        return LiveHistogramData(
            luma: normalise(luma),
            red: normalise(red),
            green: normalise(green),
            blue: normalise(blue),
            brightness: Int(brightness.rounded())
        )
    }

    private static func areaHistogram(of image: CIImage, bins: Int, context: CIContext) -> [Float]? {
        guard let filter = CIFilter(name: "CIAreaHistogram") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        filter.setValue(bins, forKey: "inputCount")
        filter.setValue(1.0, forKey: kCIInputScaleKey)

        guard let output = filter.outputImage else { return nil }

        var buffer = [Float](repeating: 0, count: bins * 4)
        context.render(
            output,
            toBitmap: &buffer,
            rowBytes: bins * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: bins, height: 1),
            format: .RGBAf,
            colorSpace: nil
        )
        return buffer
    }

    /// Scale so the tallest bar is 1. The view only ever needs relative height,
    /// and absolute counts change with resolution.
    static func normalise(_ values: [Double]) -> [Double] {
        guard let peak = values.max(), peak > 0 else {
            return [Double](repeating: 0, count: values.count)
        }
        return values.map { $0 / peak }
    }
}
