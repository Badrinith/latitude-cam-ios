//
//  Theme.swift
//  LatitudeCam
//
//  Design tokens transcribed from the Latitude design handoff.
//

import SwiftUI
import UIKit

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

// MARK: - Image helpers

extension UIImage {
    /// Centre-crops to a height ÷ width ratio. Nil ratio returns self, so the
    /// "keep the sensor frame" case costs nothing.
    func centerCropped(toHeightOverWidth ratio: CGFloat?) -> UIImage {
        guard let ratio, ratio > 0, let cg = cgImage else { return self }

        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        var cropW = w
        var cropH = w * ratio
        if cropH > h {
            cropH = h
            cropW = h / ratio
        }

        let rect = CGRect(
            x: ((w - cropW) / 2).rounded(),
            y: ((h - cropH) / 2).rounded(),
            width: cropW.rounded(),
            height: cropH.rounded()
        )
        guard let cropped = cg.cropping(to: rect) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}

// MARK: - Preferences
//
// Settings live in UserDefaults rather than on AppState so the Settings screen
// can bind to them with @AppStorage and every reader — viewfinder grid, render
// pipeline, gallery compression — picks the change up without threading it
// through the view tree.

enum Pref {
    static let grid = "settings.grid"
    static let aspect = "settings.aspect"
    static let jpegQuality = "settings.jpegQuality"
    static let peakingColor = "settings.peakingColor"
    static let histogramStyle = "settings.histogramStyle"
    static let haptics = "settings.haptics"
    static let hapticStrength = "settings.hapticStrength"
    /// Set once the entry flow has been completed, so later cold launches go
    /// straight from the splash to the viewfinder.
    static let onboarded = "app.onboarded"

    static let gridOptions = ["Rule of Thirds", "Golden Ratio", "Off"]
    static let aspectOptions = ["3:2", "4:3", "1:1", "16:9"]
    static let jpegQualityOptions = ["Maximum", "High", "Balanced"]
    static let peakingColorOptions = ["Amber", "Red", "Green", "White"]
    static let histogramStyleOptions = ["Luma", "RGB"]
    static let hapticStrengthOptions = ["Subtle", "Standard", "Strong"]

    static func string(_ key: String, default fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }

    /// Height ÷ width. Nil keeps the sensor's own frame.
    static func aspectRatio(_ name: String) -> CGFloat? {
        switch name {
        case "3:2":  return 3.0 / 2.0
        case "4:3":  return 4.0 / 3.0
        case "1:1":  return 1
        case "16:9": return 16.0 / 9.0
        default:     return nil
        }
    }

    static func compressionQuality(_ name: String) -> CGFloat {
        switch name {
        case "Maximum":  return 0.98
        case "Balanced": return 0.75
        default:         return 0.90
        }
    }

    static func peakingTint(_ name: String) -> (r: Double, g: Double, b: Double) {
        switch name {
        case "Red":   return (0.90, 0.20, 0.18)
        case "Green": return (0.20, 0.85, 0.35)
        case "White": return (1.00, 1.00, 1.00)
        default:      return (0.85, 0.54, 0.32)   // Amber
        }
    }
}

// MARK: - Navigation state

enum Screen {
    case splash, onboarding, login, viewfinder, filmSim, library, edit, review, settings
}

@MainActor
final class AppState: ObservableObject {
    // Cold launch only: AppState is built once per process, so the splash cannot
    // replay when the app returns from the background.
    @Published var screen: Screen = .splash
    @Published var proSheetOpen = false
    /// Which manual control the Pro sheet should call attention to, set when the
    /// user taps that value in the viewfinder HUD.
    @Published var proFocus: String?
    @Published var exportSheetOpen = false

    let cameraManager = CameraManager()
    let gallery = PhotoGallery()

    /// The frame the shutter froze, held for the Review screen.
    @Published var capturedImage: UIImage?
    /// The library photo the Edit screen is working on.
    @Published var editingPhoto: PhotoGallery.Photo?
    /// Briefly set after a save so the viewfinder can confirm the shot landed.
    @Published var lastSaveMessage: String?

    // Every control below feeds the render pipeline, so each one syncs on write.
    @Published var selectedFilm: FilmPreset = FilmPreset.all[0] { didSet { syncCamera() } }
    @Published var intensity: Double = 0.8 { didSet { syncCamera() } }
    @Published var grainOn = true { didSet { syncCamera() } }
    @Published var halationOn = false { didSet { syncCamera() } }
    @Published var vignetteOn = false { didSet { syncCamera() } }

    // Manual controls — stored 0…1 so the sliders and the viewfinder HUD read
    // from one source of truth.
    @Published var shutter: Double = 0.62 { didSet { syncCamera() } }
    @Published var iso: Double = 0.18 { didSet { syncCamera() } }
    @Published var whiteBalance: Double = 0.58 { didSet { syncCamera() } }
    @Published var exposureComp: Double = 0.5 { didSet { syncCamera() } }
    @Published var focusPeaking = true { didSet { syncCamera() } }
    @Published var proRAW = false

    static let shutterStops = [15, 30, 60, 125, 240, 500, 1000]
    static let isoStops = [50, 100, 200, 400, 800, 1600, 3200]
    /// Named lighting temperatures rather than a continuous sweep — a WB dial
    /// clicks between presets, and the readouts stay round numbers.
    static let whiteBalanceStops = [2500, 3200, 4000, 5000, 5600, 6500, 7500]
    /// 11 half-stop positions across ±2.5 EV.
    static let evDetents = 11

    static var shutterLabels: [String] { shutterStops.map { "1/\($0)" } }
    static var isoLabels: [String] { isoStops.map(String.init) }
    static var whiteBalanceLabels: [String] { whiteBalanceStops.map { "\($0)K" } }
    static var exposureLabels: [String] {
        (0..<evDetents).map { String(format: "%+.1f", -2.5 + Double($0) * 0.5) }
    }

    func stop<T>(_ ladder: [T], at position: Double) -> T {
        ladder[min(ladder.count - 1, max(0, Int(position * Double(ladder.count))))]
    }

    var shutterValue: Int { stop(Self.shutterStops, at: shutter) }
    var isoValue: Int { stop(Self.isoStops, at: iso) }
    var kelvinValue: Double { Double(stop(Self.whiteBalanceStops, at: whiteBalance)) }

    /// −2.5…+2.5 EV in half-stop detents. Derived from the same band index the
    /// slider uses for its clicks, so a click always coincides with a change.
    var evValue: Double {
        let index = min(Self.evDetents - 1, max(0, Int(exposureComp * Double(Self.evDetents))))
        return -2.5 + Double(index) * 0.5
    }

    var shutterLabel: String { "1/\(shutterValue)" }
    var isoLabel: String { "ISO \(isoValue)" }
    var kelvinLabel: String { "\(Int(kelvinValue))K" }
    var exposureLabel: String { String(format: "%+.1f EV", evValue) }

    // Dials address stops by index; the 0…1 storage stays so persistence and the
    // HUD keep reading from one source of truth.
    func stopIndex(_ count: Int, at position: Double) -> Int {
        min(count - 1, max(0, Int(position * Double(count))))
    }

    func position(forIndex index: Int, of count: Int) -> Double {
        (Double(min(max(index, 0), count - 1)) + 0.5) / Double(count)
    }

    var shutterIndex: Int {
        get { stopIndex(Self.shutterStops.count, at: shutter) }
        set { shutter = position(forIndex: newValue, of: Self.shutterStops.count) }
    }
    var isoIndex: Int {
        get { stopIndex(Self.isoStops.count, at: iso) }
        set { iso = position(forIndex: newValue, of: Self.isoStops.count) }
    }
    var whiteBalanceIndex: Int {
        get { stopIndex(Self.whiteBalanceStops.count, at: whiteBalance) }
        set { whiteBalance = position(forIndex: newValue, of: Self.whiteBalanceStops.count) }
    }
    var exposureIndex: Int {
        get { stopIndex(Self.evDetents, at: exposureComp) }
        set { exposureComp = position(forIndex: newValue, of: Self.evDetents) }
    }

    func go(_ next: Screen) {
        withAnimation(.easeInOut(duration: 0.28)) { screen = next }
    }

    /// Where the splash hands off. First run gets the tour; every run after it
    /// goes straight to the camera.
    func finishSplash() {
        go(UserDefaults.standard.bool(forKey: Pref.onboarded) ? .viewfinder : .onboarding)
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Pref.onboarded)
        go(.viewfinder)
    }

    // MARK: - Camera

    /// Mirror the UI state onto the render pipeline. Cheap enough to call on
    /// every slider tick — the camera queue picks it up on the next frame.
    func syncCamera() {
        var s = RenderSettings()
        s.filmID = selectedFilm.id
        s.intensity = intensity
        s.ev = evValue
        s.iso = isoValue
        s.shutterDenominator = shutterValue
        s.kelvin = kelvinValue
        s.grain = grainOn
        s.halation = halationOn
        s.vignette = vignetteOn
        s.focusPeaking = focusPeaking
        s.peakingColorName = Pref.string(Pref.peakingColor, default: "Amber")
        cameraManager.apply(s)
    }

    /// Freeze the current frame and move to Review. No-op with nothing to shoot,
    /// which is the Simulator's normal state.
    @discardableResult
    func capture() -> Bool {
        guard let image = cameraManager.capturePhoto() else {
            lastSaveMessage = "No frame yet — camera still starting"
            clearMessageSoon()
            return false
        }
        // The sensor frame is 16:9; the chosen aspect is a crop of it, so the
        // saved photo matches what the viewfinder's aspect badge promised.
        let aspect = Pref.string(Pref.aspect, default: "3:2")
        capturedImage = image.centerCropped(toHeightOverWidth: Pref.aspectRatio(aspect))
        go(.review)
        return true
    }

    /// Put the look back to the shipped default without touching exposure.
    func resetLook() {
        selectedFilm = FilmPreset.all[0]
        intensity = 0.8
        grainOn = true
        halationOn = false
        vignetteOn = false
        lastSaveMessage = "Look reset"
        clearMessageSoon()
    }

    func discardCapture() {
        capturedImage = nil
        go(.viewfinder)
    }

    func saveCapturedPhoto() {
        guard let image = capturedImage else { return }
        gallery.addPhoto(
            image,
            filmID: selectedFilm.id,
            iso: isoValue,
            shutterDenominator: shutterValue
        )
        lastSaveMessage = "Saved to Library"
        clearMessageSoon()
    }

    private func clearMessageSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            lastSaveMessage = nil
        }
    }

    init() {
        // Adopt whatever the camera restored from the last session so the HUD
        // and the pipeline do not disagree on launch.
        let restored = cameraManager.currentSettings
        if let film = FilmPreset.all.first(where: { $0.id == restored.filmID }) {
            selectedFilm = film
        }
        if let index = Self.isoStops.firstIndex(of: restored.iso) {
            iso = (Double(index) + 0.5) / Double(Self.isoStops.count)
        }
        if let index = Self.shutterStops.firstIndex(of: restored.shutterDenominator) {
            shutter = (Double(index) + 0.5) / Double(Self.shutterStops.count)
        }
        if let index = Self.whiteBalanceStops.firstIndex(where: {
            abs(Double($0) - restored.kelvin) < 1
        }) {
            whiteBalance = (Double(index) + 0.5) / Double(Self.whiteBalanceStops.count)
        }
        syncCamera()

        #if DEBUG
        // Lets `simctl launch` open straight onto a screen for visual checks:
        //   SIMCTL_CHILD_LAT_SCREEN=viewfinder xcrun simctl launch <udid> com.latitude.cam
        if let name = ProcessInfo.processInfo.environment["LAT_SCREEN"] {
            let routes: [String: Screen] = [
                "splash": .splash, "onboarding": .onboarding, "login": .login,
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
