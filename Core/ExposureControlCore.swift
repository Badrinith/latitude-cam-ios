import Foundation

struct ExposureMeter {
    var iso: Double = 100
    var shutterSpeed: Double = 1.0
    
    func adjustPixel(_ pixel: Pixel) -> Pixel {
        let isoMultiplier = iso / 100.0
        let shutterMultiplier = shutterSpeed
        let combinedMultiplier = isoMultiplier * shutterMultiplier
        
        let r = min(255, Int(Double(pixel.r) * combinedMultiplier))
        let g = min(255, Int(Double(pixel.g) * combinedMultiplier))
        let b = min(255, Int(Double(pixel.b) * combinedMultiplier))
        
        return Pixel(r: UInt8(r), g: UInt8(g), b: UInt8(b))
    }
}

struct HistogramData {
    var rBuckets: [Int] = Array(repeating: 0, count: 256)
    var gBuckets: [Int] = Array(repeating: 0, count: 256)
    var bBuckets: [Int] = Array(repeating: 0, count: 256)
    var brightness: Double = 0
    
    enum ExposureStatus: String {
        case underexposed = "Under"
        case good = "Good"
        case overexposed = "Over"
    }
    
    var status: ExposureStatus {
        if brightness < 85 { return .underexposed }
        if brightness > 170 { return .overexposed }
        return .good
    }
}

func generateHistogram(from pixels: [Pixel]) -> HistogramData {
    var hist = HistogramData()
    var totalBrightness = 0
    
    for pixel in pixels {
        hist.rBuckets[Int(pixel.r)] += 1
        hist.gBuckets[Int(pixel.g)] += 1
        hist.bBuckets[Int(pixel.b)] += 1
        totalBrightness += Int(pixel.r) + Int(pixel.g) + Int(pixel.b)
    }
    
    hist.brightness = pixels.isEmpty ? 0 : Double(totalBrightness) / Double(pixels.count * 3)
    return hist
}
