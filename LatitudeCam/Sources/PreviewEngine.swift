//
//  PreviewEngine.swift
//  LatitudeCam
//
//  Real-time Preview Processing: Convert camera frames to processed images
//  Handles pixel conversion, filtering, and before/after comparison
//

import Foundation
import UIKit
import CoreImage
import CoreGraphics

// MARK: - Preview Engine

public class PreviewEngine {
    
    // Configuration
    private let targetFPS: Int = 30
    private let pixelBufferSize: Int = 1024
    
    // State
    /// Must start in the distant past — seeding this with `Date()` makes the
    /// throttle drop the very first frame after construction.
    private var lastPreviewTime: Date = .distantPast
    private var pixelBuffer: [Pixel] = []
    
    // Callbacks
    var onPreviewUpdate: ((UIImage?) -> Void)?
    
    public init() {}
    
    // MARK: - Frame Processing
    
    /// Process a camera frame and trigger preview update
    public func processFrame(_ frame: CGImage) {
        // Frame rate throttling (target ~30fps)
        let now = Date()
        let timeSinceLastPreview = now.timeIntervalSince(lastPreviewTime)
        let minFrameInterval = 1.0 / Double(targetFPS)
        
        guard timeSinceLastPreview >= minFrameInterval else {
            return  // Skip this frame to maintain target FPS
        }
        
        lastPreviewTime = now
        
        // Convert frame to pixels
        let pixels = convertToPixels(frame)
        
        // Process pixels (apply film + exposure)
        // Note: Camera manager will provide film/exposure settings
        let processedPixels = pixels  // Will be enhanced in UI
        
        // Convert back to image
        let processedImage = convertToImage(
            processedPixels,
            width: frame.width,
            height: frame.height
        )
        
        // Trigger update on main thread
        DispatchQueue.main.async {
            self.onPreviewUpdate?(processedImage)
        }
    }
    
    // MARK: - Pixel Conversion
    
    /// Convert CGImage to array of Pixel objects
    public func convertToPixels(_ cgImage: CGImage) -> [Pixel] {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        
        guard let data = cgImage.dataProvider?.data as Data? else {
            return []
        }
        
        var pixels: [Pixel] = []
        let pixelData = [UInt8](data)
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * bytesPerRow) + (x * bytesPerPixel)
                
                let r = Int(pixelData[pixelIndex])
                let g = Int(pixelData[pixelIndex + 1])
                let b = Int(pixelData[pixelIndex + 2])
                // alpha = pixelData[pixelIndex + 3]
                
                pixels.append(Pixel(r: r, g: g, b: b))
            }
        }
        
        return pixels
    }
    
    /// Convert array of Pixel objects back to UIImage
    public func convertToImage(_ pixels: [Pixel], width: Int, height: Int) -> UIImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        var pixelData = [UInt8]()
        
        for pixel in pixels {
            pixelData.append(UInt8(pixel.r))
            pixelData.append(UInt8(pixel.g))
            pixelData.append(UInt8(pixel.b))
            pixelData.append(255)  // Alpha
        }
        
        guard let data = CFDataCreate(nil, pixelData, pixelData.count) else {
            return nil
        }
        
        guard let provider = CGDataProvider(data: data) else {
            return nil
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Image Processing
    
    /// Process pixels through film and exposure pipeline
    public func processPixels(
        _ pixels: [Pixel],
        film: FilmProfile,
        iso: Int,
        shutter: Double
    ) -> [Pixel] {
        let exposure = ExposureMeter(baseISO: 100, baseShutter: 1.0)
        
        return pixels.map { pixel in
            let afterFilm = film.apply(to: pixel)
            return exposure.adjust(afterFilm, toISO: iso, exposureTime: shutter)
        }
    }
    
    // MARK: - Before/After Comparison
    
    /// Create side-by-side before/after comparison image
    public func createBeforeAfterComparison(
        original: CGImage,
        processed: CGImage
    ) -> UIImage? {
        let width = original.width
        let height = original.height
        let combinedWidth = width * 2
        
        let size = CGSize(width: combinedWidth, height: height)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        
        defer { UIGraphicsEndImageContext() }
        
        // Draw original on left
        let originalUIImage = UIImage(cgImage: original)
        originalUIImage.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw processed on right
        let processedUIImage = UIImage(cgImage: processed)
        processedUIImage.draw(in: CGRect(x: width, y: 0, width: width, height: height))
        
        // Draw divider line
        UIColor.white.setStroke()
        let dividerPath = UIBezierPath()
        dividerPath.move(to: CGPoint(x: width, y: 0))
        dividerPath.addLine(to: CGPoint(x: width, y: height))
        dividerPath.lineWidth = 2
        dividerPath.stroke()
        
        // Draw labels
        let labelAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.white,
            NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 16)
        ]
        
        "BEFORE".draw(
            at: CGPoint(x: 10, y: 10),
            withAttributes: labelAttributes
        )
        
        "AFTER".draw(
            at: CGPoint(x: width + 10, y: 10),
            withAttributes: labelAttributes
        )
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    // MARK: - Preview Utilities
    
    /// Get preview statistics for display
    public func getPreviewStats(pixels: [Pixel]) -> PreviewStats {
        guard !pixels.isEmpty else {
            return PreviewStats(avgBrightness: 0, colorBalance: 0)
        }
        
        let totalBrightness = pixels.reduce(0) { $0 + ($1.r + $1.g + $1.b) / 3 }
        let avgBrightness = totalBrightness / pixels.count
        
        let redAvg = pixels.reduce(0) { $0 + $1.r } / pixels.count
        let blueAvg = pixels.reduce(0) { $0 + $1.b } / pixels.count
        let colorBalance = redAvg - blueAvg
        
        return PreviewStats(
            avgBrightness: avgBrightness,
            colorBalance: colorBalance
        )
    }
}

// MARK: - Preview Statistics

public struct PreviewStats {
    public let avgBrightness: Int
    public let colorBalance: Int
}
