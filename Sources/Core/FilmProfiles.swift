//
//  FilmProfiles.swift
//  LatitudeCam
//
//  Image Processing: Film Profile Effects
//  These apply film-stock-inspired color adjustments to pixels
//

import Foundation

// MARK: - Pixel Model

/// Represents a single pixel with RGB values (0-255)
public struct Pixel {
    public var r: Int
    public var g: Int
    public var b: Int
    
    public init(r: Int, g: Int, b: Int) {
        // Clamp values to 0-255 range
        self.r = max(0, min(255, r))
        self.g = max(0, min(255, g))
        self.b = max(0, min(255, b))
    }
}

// MARK: - Film Profile Protocol

/// Protocol for all film profile effects
public protocol FilmProfile {
    /// Apply the film effect to a pixel
    func apply(to pixel: Pixel) -> Pixel
}

// MARK: - Amber Film

/// Warm, yellowish tone reminiscent of vintage color film
/// RGB Adjustments: R +20%, G -10%, B -20%
public struct AmberFilm: FilmProfile {
    public init() {}
    
    public func apply(to pixel: Pixel) -> Pixel {
        let r = Int(Double(pixel.r) * 1.2)
        let g = Int(Double(pixel.g) * 0.9)
        let b = Int(Double(pixel.b) * 0.8)
        
        return Pixel(r: r, g: g, b: b)
    }
}

// MARK: - Slate Film

/// Cool, desaturated tone with blue undertones
/// RGB Adjustments: R -20%, G -20%, B +20%
public struct SlateFilm: FilmProfile {
    public init() {}
    
    public func apply(to pixel: Pixel) -> Pixel {
        let r = Int(Double(pixel.r) * 0.8)
        let g = Int(Double(pixel.g) * 0.8)
        let b = Int(Double(pixel.b) * 1.2)
        
        return Pixel(r: r, g: g, b: b)
    }
}

// MARK: - Rust Film

/// Warm, heavily saturated tone with vintage character
/// RGB Adjustments: R +30%, G +10%, B -40%
public struct RustFilm: FilmProfile {
    public init() {}
    
    public func apply(to pixel: Pixel) -> Pixel {
        let r = Int(Double(pixel.r) * 1.3)
        let g = Int(Double(pixel.g) * 1.1)
        let b = Int(Double(pixel.b) * 0.6)
        
        return Pixel(r: r, g: g, b: b)
    }
}

// MARK: - Mono Film

/// Black and white conversion using standard luminosity formula
/// Formula: 0.299*R + 0.587*G + 0.114*B
public struct MonoFilm: FilmProfile {
    public init() {}
    
    public func apply(to pixel: Pixel) -> Pixel {
        // Standard luminosity coefficients
        let luminosity = Int(
            Double(pixel.r) * 0.299 +
            Double(pixel.g) * 0.587 +
            Double(pixel.b) * 0.114
        )
        
        return Pixel(r: luminosity, g: luminosity, b: luminosity)
    }
}
