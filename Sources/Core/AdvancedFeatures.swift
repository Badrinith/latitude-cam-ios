//
//  AdvancedFeatures.swift
//  LatitudeCam - Phase 0.4.4-5
//
//  Focus Peaking, Batch Processing, Custom Profiles, Grid Overlays
//

import Foundation
import UIKit

// MARK: - Focus Peaking

public class FocusPeakingOverlay {
    public func detectFocusAreas(pixels: [Pixel], width: Int, height: Int) -> [(x: Int, y: Int)] {
        var focusAreas: [(x: Int, y: Int)] = []
        let threshold = 50
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                if idx >= pixels.count { continue }
                
                let center = pixels[idx]
                let neighbors = [
                    pixels[idx - width - 1], pixels[idx - width], pixels[idx - width + 1],
                    pixels[idx - 1], pixels[idx + 1],
                    pixels[idx + width - 1], pixels[idx + width], pixels[idx + width + 1]
                ]
                
                let contrast = neighbors.map { pixel in
                    abs(pixel.r - center.r) + abs(pixel.g - center.g) + abs(pixel.b - center.b)
                }.max() ?? 0
                
                if contrast > threshold {
                    focusAreas.append((x: x, y: y))
                }
            }
        }
        
        return focusAreas
    }
}

// MARK: - Batch Processor

public class BatchProcessor {
    private var queue: [UIImage] = []
    private var processing = false
    
    public func addToBatch(_ image: UIImage) {
        queue.append(image)
    }
    
    public func processBatch(film: FilmProfile, iso: Int, shutter: Double, 
                            completion: @escaping (Int) -> Void) {
        processing = true
        var processed = 0
        
        for image in queue {
            // Process image through pipeline
            processed += 1
            completion(processed)
        }
        
        queue.removeAll()
        processing = false
    }
}

// MARK: - Custom Film Profiles

public class CustomFilmProfileEditor {
    public struct CustomProfile: FilmProfile {
        public let name: String
        public let rMultiplier: Double
        public let gMultiplier: Double
        public let bMultiplier: Double
        
        public func apply(to pixel: Pixel) -> Pixel {
            let r = Int(Double(pixel.r) * rMultiplier)
            let g = Int(Double(pixel.g) * gMultiplier)
            let b = Int(Double(pixel.b) * bMultiplier)
            return Pixel(r: r, g: g, b: b)
        }
    }
    
    public func createCustomProfile(name: String, rMult: Double, gMult: Double, bMult: Double) -> CustomProfile {
        return CustomProfile(name: name, rMultiplier: rMult, gMultiplier: gMult, bMultiplier: bMult)
    }
    
    public func saveProfile(_ profile: CustomProfile) {
        let defaults = UserDefaults.standard
        let key = "CustomProfile_\(profile.name)"
        defaults.set([
            "r": profile.rMultiplier,
            "g": profile.gMultiplier,
            "b": profile.bMultiplier
        ], forKey: key)
    }
}

// MARK: - Grid Overlays

public class GridOverlay {
    enum GridType { case thirdRule, goldenRatio, grid }
    
    public func renderGrid(_ type: GridType, size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        
        UIColor.white.withAlphaComponent(0.3).setStroke()
        let path = UIBezierPath()
        path.lineWidth = 1
        
        switch type {
        case .thirdRule:
            // Vertical lines at 1/3 and 2/3
            path.move(to: CGPoint(x: size.width / 3, y: 0))
            path.addLine(to: CGPoint(x: size.width / 3, y: size.height))
            
            path.move(to: CGPoint(x: size.width * 2 / 3, y: 0))
            path.addLine(to: CGPoint(x: size.width * 2 / 3, y: size.height))
            
            // Horizontal lines
            path.move(to: CGPoint(x: 0, y: size.height / 3))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 3))
            
            path.move(to: CGPoint(x: 0, y: size.height * 2 / 3))
            path.addLine(to: CGPoint(x: size.width, y: size.height * 2 / 3))
            
        case .goldenRatio:
            let phi = (1.0 + sqrt(5.0)) / 2.0
            let x1 = size.width / phi
            let y1 = size.height / phi
            
            path.move(to: CGPoint(x: x1, y: 0))
            path.addLine(to: CGPoint(x: x1, y: size.height))
            
            path.move(to: CGPoint(x: 0, y: y1))
            path.addLine(to: CGPoint(x: size.width, y: y1))
            
        case .grid:
            // Simple grid every 4th section
            for i in 1...3 {
                path.move(to: CGPoint(x: size.width * CGFloat(i) / 4, y: 0))
                path.addLine(to: CGPoint(x: size.width * CGFloat(i) / 4, y: size.height))
                
                path.move(to: CGPoint(x: 0, y: size.height * CGFloat(i) / 4))
                path.addLine(to: CGPoint(x: size.width, y: size.height * CGFloat(i) / 4))
            }
        }
        
        path.stroke()
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
