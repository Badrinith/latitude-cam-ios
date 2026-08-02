import Foundation

struct Pixel {
    var r: UInt8, g: UInt8, b: UInt8
    
    mutating func clamp() {
        // Clamping happens in individual adjustments
    }
}

protocol FilmProfile {
    func apply(to pixel: Pixel) -> Pixel
    var name: String { get }
}

struct AmberFilm: FilmProfile {
    let name = "Amber"
    func apply(to pixel: Pixel) -> Pixel {
        let r = min(255, Int(pixel.r) * 120 / 100)
        let g = max(0, Int(pixel.g) * 90 / 100)
        let b = max(0, Int(pixel.b) * 80 / 100)
        return Pixel(r: UInt8(r), g: UInt8(g), b: UInt8(b))
    }
}

struct SlateFilm: FilmProfile {
    let name = "Slate"
    func apply(to pixel: Pixel) -> Pixel {
        let r = max(0, Int(pixel.r) * 80 / 100)
        let g = max(0, Int(pixel.g) * 80 / 100)
        let b = min(255, Int(pixel.b) * 120 / 100)
        return Pixel(r: UInt8(r), g: UInt8(g), b: UInt8(b))
    }
}

struct RustFilm: FilmProfile {
    let name = "Rust"
    func apply(to pixel: Pixel) -> Pixel {
        let r = min(255, Int(pixel.r) * 130 / 100)
        let g = min(255, Int(pixel.g) * 110 / 100)
        let b = max(0, Int(pixel.b) * 60 / 100)
        return Pixel(r: UInt8(r), g: UInt8(g), b: UInt8(b))
    }
}

struct MonoFilm: FilmProfile {
    let name = "Mono"
    func apply(to pixel: Pixel) -> Pixel {
        let gray = UInt8(Double(pixel.r) * 0.299 + Double(pixel.g) * 0.587 + Double(pixel.b) * 0.114)
        return Pixel(r: gray, g: gray, b: gray)
    }
}
