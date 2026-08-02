//
//  Theme.swift
//  LatitudeCam
//
//  Design tokens transcribed from the Latitude design handoff.
//

import SwiftUI

// MARK: - Color tokens

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Ink {
    /// Screen background
    static let base = Color(hex: 0x0D0D0D)
    /// Sheet + icon-mark background
    static let raised = Color(hex: 0x161616)
    /// Grouped cards, chips
    static let card = Color(hex: 0x1C1C1E)
}

enum Tone {
    /// Warm white — headlines, primary text
    static let primary = Color(hex: 0xF2EFE8)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.45)
    static let quaternary = Color.white.opacity(0.4)
    static let separator = Color.white.opacity(0.1)
    static let hairline = Color.white.opacity(0.12)
}

enum Accent {
    static let amber = Color(hex: 0xD98A52)
    static let amberDeep = Color(hex: 0x8A5A34)
}

enum FilmSwatch {
    static let amber = Color(hex: 0x8A7A63)
    static let slate = Color(hex: 0x6B6A63)
    static let rust = Color(hex: 0x9C3F2E)
    static let mono = Color(hex: 0x2B2B2B)
}

// MARK: - Type ramp
//
// UI text uses San Francisco. Technical readouts use SF Mono so they read as
// instrument data, per the handoff.

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Film presets

struct FilmPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let swatch: Color

    static let all: [FilmPreset] = [
        .init(id: "amber", name: "Amber Stock", blurb: "Warm, soft highlights", swatch: FilmSwatch.amber),
        .init(id: "slate", name: "Slate", blurb: "Cool, muted neutral", swatch: FilmSwatch.slate),
        .init(id: "rust", name: "Rust", blurb: "Deep reds, punchy", swatch: FilmSwatch.rust),
        .init(id: "mono", name: "Mono", blurb: "High-contrast B&W", swatch: FilmSwatch.mono)
    ]

    /// Short label used on the viewfinder filmstrip.
    var shortName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

// MARK: - Navigation state

enum Screen {
    case launch, onboarding, login, viewfinder, filmSim, library, edit, review, settings
}

@MainActor
final class AppState: ObservableObject {
    @Published var screen: Screen = .launch
    @Published var proSheetOpen = false
    @Published var exportSheetOpen = false

    @Published var selectedFilm: FilmPreset = FilmPreset.all[0]
    @Published var intensity: Double = 0.8
    @Published var grainOn = true
    @Published var halationOn = false
    @Published var vignetteOn = false

    // Manual controls — stored 0…1 so the sliders and the viewfinder HUD read
    // from one source of truth.
    @Published var shutter: Double = 0.62
    @Published var iso: Double = 0.18
    @Published var whiteBalance: Double = 0.58
    @Published var exposureComp: Double = 0.56
    @Published var focusPeaking = true
    @Published var proRAW = false

    private static let shutterStops = [15, 30, 60, 125, 240, 500, 1000]
    private static let isoStops = [50, 100, 200, 400, 800, 1600, 3200]

    private func stop<T>(_ ladder: [T], at position: Double) -> T {
        ladder[min(ladder.count - 1, max(0, Int(position * Double(ladder.count))))]
    }

    var shutterLabel: String { "1/\(stop(Self.shutterStops, at: shutter))" }
    var isoLabel: String { "ISO \(stop(Self.isoStops, at: iso))" }
    var kelvinLabel: String { "\(Int(((2000 + whiteBalance * 6200) / 100).rounded()) * 100)K" }
    var exposureLabel: String { String(format: "%+.1f EV", (exposureComp - 0.5) * 5) }

    func go(_ next: Screen) {
        withAnimation(.easeInOut(duration: 0.28)) { screen = next }
    }

    init() {
        #if DEBUG
        // Lets `simctl launch` open straight onto a screen for visual checks:
        //   SIMCTL_CHILD_LAT_SCREEN=viewfinder xcrun simctl launch <udid> com.latitude.cam
        if let name = ProcessInfo.processInfo.environment["LAT_SCREEN"] {
            let routes: [String: Screen] = [
                "launch": .launch, "onboarding": .onboarding, "login": .login,
                "viewfinder": .viewfinder, "filmsim": .filmSim, "library": .library,
                "edit": .edit, "review": .review, "settings": .settings
            ]
            if let target = routes[name.lowercased()] { screen = target }
            proSheetOpen = ProcessInfo.processInfo.environment["LAT_SHEET"] == "pro"
            exportSheetOpen = ProcessInfo.processInfo.environment["LAT_SHEET"] == "export"
        }
        #endif
    }
}
