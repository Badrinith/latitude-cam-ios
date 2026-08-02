//
//  HistogramEngine.swift
//  LatitudeCam - Phase 0.4.3
//
//  Histogram Display: Analyze exposure and color distribution
//

import Foundation
import UIKit

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
        
        let exposure: String
        if avgBrightness < 85 { exposure = "Under" }
        else if avgBrightness > 170 { exposure = "Over" }
        else { exposure = "Good" }
        
        return HistogramData(
            redBuckets: redBuckets,
            greenBuckets: greenBuckets,
            blueBuckets: blueBuckets,
            brightness: avgBrightness,
            exposure: exposure
        )
    }
    
    public func renderHistogram(_ data: HistogramData, size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        
        // Background
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        
        let maxBucket = max(data.redBuckets.max() ?? 1, 
                           data.greenBuckets.max() ?? 1,
                           data.blueBuckets.max() ?? 1)
        
        let barWidth = size.width / CGFloat(bucketCount)
        
        // Draw histograms
        for i in 0..<bucketCount {
            let redHeight = CGFloat(data.redBuckets[i]) / CGFloat(maxBucket) * size.height
            let greenHeight = CGFloat(data.greenBuckets[i]) / CGFloat(maxBucket) * size.height
            let blueHeight = CGFloat(data.blueBuckets[i]) / CGFloat(maxBucket) * size.height
            
            let x = CGFloat(i) * barWidth
            
            // Red channel
            UIColor.red.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(x: x, y: size.height - redHeight, width: barWidth, height: redHeight))
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
