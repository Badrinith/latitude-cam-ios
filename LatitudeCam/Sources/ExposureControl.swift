//
//  ExposureControl.swift
//  LatitudeCam
//
//  Image Processing: Manual Exposure Adjustment
//  Adjust brightness via ISO and Shutter Speed
//

import Foundation

// MARK: - ISO Control

/// Simulates camera ISO (sensor sensitivity)
/// ISO 100 = base sensitivity
/// ISO 200 = 2x brighter
/// ISO 400 = 4x brighter (2x stop increase)
public struct ISOControl {
    let baseISO: Int
    
    public init(baseISO: Int = 100) {
        self.baseISO = baseISO
    }
    
    /// Adjust pixel brightness based on ISO value
    /// - Parameters:
    ///   - pixel: The pixel to adjust
    ///   - toISO: Target ISO value
    /// - Returns: Adjusted pixel with increased or decreased brightness
    public func adjust(_ pixel: Pixel, toISO: Int) -> Pixel {
        // Calculate ISO multiplier relative to base ISO
        let multiplier = Double(toISO) / Double(baseISO)
        
        // Apply multiplier to each channel (preserves color balance)
        let r = Int(Double(pixel.r) * multiplier)
        let g = Int(Double(pixel.g) * multiplier)
        let b = Int(Double(pixel.b) * multiplier)
        
        return Pixel(r: r, g: g, b: b)
    }
}

// MARK: - Shutter Speed Control

/// Simulates camera shutter speed (exposure time)
/// Base value = standard exposure time (e.g., 1/60s)
/// 2.0 = 2x longer exposure = 2x more light
/// 0.5 = 0.5x shorter exposure = 0.5x less light
public struct ShutterControl {
    let baseShutter: Double
    
    public init(baseShutter: Double = 1.0) {
        self.baseShutter = baseShutter
    }
    
    /// Adjust pixel brightness based on shutter exposure time
    /// - Parameters:
    ///   - pixel: The pixel to adjust
    ///   - exposureTime: Relative exposure time (1.0 = base, 2.0 = 2x longer, 0.5 = 0.5x shorter)
    /// - Returns: Adjusted pixel with increased or decreased brightness
    public func adjust(_ pixel: Pixel, exposureTime: Double) -> Pixel {
        // Calculate exposure multiplier relative to base
        let multiplier = exposureTime / baseShutter
        
        // Apply multiplier to each channel (preserves color balance)
        let r = Int(Double(pixel.r) * multiplier)
        let g = Int(Double(pixel.g) * multiplier)
        let b = Int(Double(pixel.b) * multiplier)
        
        return Pixel(r: r, g: g, b: b)
    }
}

// MARK: - Exposure Meter (combines ISO + Shutter)

/// Combines ISO and Shutter Speed for complete exposure control
public struct ExposureMeter {
    let iso: ISOControl
    let shutter: ShutterControl
    
    public init(baseISO: Int = 100, baseShutter: Double = 1.0) {
        self.iso = ISOControl(baseISO: baseISO)
        self.shutter = ShutterControl(baseShutter: baseShutter)
    }
    
    /// Apply complete exposure adjustment (ISO + Shutter combined)
    public func adjust(_ pixel: Pixel, toISO: Int, exposureTime: Double) -> Pixel {
        // Apply ISO adjustment first
        let afterISO = iso.adjust(pixel, toISO: toISO)
        
        // Then apply shutter adjustment
        let afterShutter = shutter.adjust(afterISO, exposureTime: exposureTime)
        
        return afterShutter
    }
}
