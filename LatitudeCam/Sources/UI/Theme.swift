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
    static let mirrorToPhotos = "settings.mirrorToPhotos"
    static let captureFormat = "settings.captureFormat"
    static let captureResolution = "settings.captureResolution"
    /// Set once the entry flow has been completed, so later cold launches go
    /// straight from the splash to the viewfinder.
    static let onboarded = "app.onboarded"

    static let gridOptions = ["Rule of Thirds", "Golden Ratio", "Off"]
    static let aspectOptions = ["3:2", "4:3", "1:1", "16:9"]
    static let jpegQualityOptions = ["Maximum", "High", "Balanced"]
    static let peakingColorOptions = ["Amber", "Red", "Green", "White"]
    static let histogramStyleOptions = ["Luma", "RGB"]
    static let hapticStrengthOptions = ["Subtle", "Standard", "Strong"]
    static let captureFormatOptions = ["RAW Only", "JPEG Only", "RAW + JPEG"]
    static let captureResolutionOptions = ["4MP", "8MP", "12MP", "Full"]

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

    /// Nil means the sensor's own largest size.
    static func megapixels(_ name: String) -> Int? {
        switch name {
        case "4MP":  return 4
        case "8MP":  return 8
        case "12MP": return 12
        default:     return nil   // Full
        }
    }

    static func compressionQuality(_ name: String) -> CGFloat {
        switch name {
        case "Maximum":  return 1.0
        case "Balanced": return 0.75
        default:         return 0.92   // High
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
    /// Encoding and library writes, kept off the main queue so the shutter stays
    /// responsive while a frame is still being filed.
    private let exportQueue = DispatchQueue(label: "com.latitude.export", qos: .utility)

    /// The frame the shutter froze, held for the Review screen.
    @Published var capturedImage: UIImage?
    /// The library photo the Edit screen is working on.
    @Published var editingPhoto: PhotoGallery.Photo?
    /// The roll entry the shutter just wrote, so Review can take it back.
    private var savedPhotoID: String?
    /// Briefly set after a save so the viewfinder can confirm the shot landed.
    @Published var lastSaveMessage: String?

    // Every control below feeds the render pipeline, so each one syncs on write.
    @Published var selectedFilm: FilmPreset = FilmPreset.all[0] { didSet { syncCamera() } }
    @Published var intensity: Double = 0.8 { didSet { syncCamera() } }
    @Published var grainOn = false { didSet { syncCamera() } }
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
    /// Either dial on A. Kept as one flag because AVFoundation's continuous auto
    /// mode governs shutter and ISO together — there is no half-auto.
    @Published var autoExposure = false { didSet { syncCamera() } }

    static let shutterStops = [15, 30, 60, 125, 240, 500, 1000]
    static let isoStops = [50, 100, 200, 400, 800, 1600, 3200]
    /// Named lighting temperatures rather than a continuous sweep — a WB dial
    /// clicks between presets, and the readouts stay round numbers.
    static let whiteBalanceStops = [2500, 3200, 4000, 5000, 5600, 6500, 7500]
    /// 11 half-stop positions across ±2.5 EV.
    static let evDetents = 11

    /// A leads both scales, as it does on an X-series or an M body: turn past the
    /// slowest speed and the camera takes the exposure back.
    static var shutterLabels: [String] { ["A"] + shutterStops.map { "1/\($0)" } }
    static var isoLabels: [String] { ["A"] + isoStops.map(String.init) }
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

    var shutterLabel: String { autoExposure ? "AUTO" : "1/\(shutterValue)" }
    var isoLabel: String { autoExposure ? "ISO A" : "ISO \(isoValue)" }
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

    // Dial index 0 is A; stops start at 1.
    var shutterIndex: Int {
        get { autoExposure ? 0 : stopIndex(Self.shutterStops.count, at: shutter) + 1 }
        set {
            if newValue <= 0 { autoExposure = true }
            else {
                autoExposure = false
                shutter = position(forIndex: newValue - 1, of: Self.shutterStops.count)
            }
        }
    }
    var isoIndex: Int {
        get { autoExposure ? 0 : stopIndex(Self.isoStops.count, at: iso) + 1 }
        set {
            if newValue <= 0 { autoExposure = true }
            else {
                autoExposure = false
                iso = position(forIndex: newValue - 1, of: Self.isoStops.count)
            }
        }
    }
    var whiteBalanceIndex: Int {
        get { stopIndex(Self.whiteBalanceStops.count, at: whiteBalance) }
        set { whiteBalance = position(forIndex: newValue, of: Self.whiteBalanceStops.count) }
    }
    var exposureIndex: Int {
        get { stopIndex(Self.evDetents, at: exposureComp) }
        set { exposureComp = position(forIndex: newValue, of: Self.evDetents) }
    }

    /// Haptics live here rather than at each call site, so a new navigation
    /// cannot ship without feedback.
    func go(_ next: Screen) {
        guard next != screen else { return }
        Haptics.tap()
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
        s.autoExposure = autoExposure
        cameraManager.apply(s)
    }

    /// Take a full-resolution frame off the sensor, save it, and stay on the
    /// viewfinder so the next shot needs only the shutter.
    ///
    /// The saved photo comes from `AVCapturePhotoOutput`, not from the preview
    /// stream. The preview is 2MP and only ever a viewfinder — saving it was what
    /// made every file 250KB.
    @discardableResult
    func capture() -> Bool {
        guard cameraManager.status.isLive else {
            lastSaveMessage = "No frame yet — camera still starting"
            clearMessageSoon()
            return false
        }

        let format = Pref.string(Pref.captureFormat, default: "RAW + JPEG")
        let resolution = Pref.string(Pref.captureResolution, default: "Full")
        let wantsRAW = format != "JPEG Only"
        let wantsProcessed = format != "RAW Only"

        cameraManager.captureStill(
            wantsRAW: wantsRAW,
            wantsProcessed: wantsProcessed,
            targetMegapixels: Pref.megapixels(resolution)
        ) { [weak self] still in
            self?.store(still, requestedFormat: format)
        }
        return true
    }

    /// Writes one finished capture to the roll, to Apple Photos, and to the DNG
    /// folder, then reports what actually landed.
    ///
    /// Confirms as soon as the frame is in the roll rather than waiting on the
    /// library. Encoding and the Photos write take a moment and the shutter should
    /// not be held hostage to either; only a failure revises the message.
    private func store(_ still: CameraManager.CapturedStill, requestedFormat: String) {
        guard still.raw != nil || still.image != nil else {
            lastSaveMessage = "Capture failed"
            clearMessageSoon()
            return
        }

        let aspect = Pref.string(Pref.aspect, default: "3:2")
        let quality = Pref.compressionQuality(Pref.string(Pref.jpegQuality, default: "Maximum"))

        // cropping() on a CGImage is a reference, not a copy — cheap enough for
        // the main queue, unlike the encode below.
        let frame = still.image?.centerCropped(toHeightOverWidth: Pref.aspectRatio(aspect))
        if let frame {
            capturedImage = frame
            savedPhotoID = gallery.addPhoto(
                frame,
                filmID: selectedFilm.id,
                iso: isoValue,
                shutterDenominator: shutterValue
            )
        }

        let megapixels = Double(still.pixelWidth * still.pixelHeight) / 1_000_000
        let sizeLabel = megapixels >= 1 ? String(format: "%.0fMP", megapixels.rounded()) : ""
        let landed = still.raw != nil && frame != nil ? "RAW+JPEG"
            : still.raw != nil ? "RAW" : "JPEG"
        lastSaveMessage = still.rawUnavailable
            ? "✓ JPEG \(sizeLabel) — RAW unsupported"
            : "✓ \(landed) \(sizeLabel)"
        clearMessageSoon()

        let mirrorEnabled = UserDefaults.standard.object(forKey: Pref.mirrorToPhotos) as? Bool ?? true

        exportQueue.async { [weak self] in
            guard let self else { return }
            if let dng = still.raw {
                PhotoExporter.saveRawDNG(dng, iso: self.isoValue) { _, _ in }
            }
            guard mirrorEnabled else { return }

            // A full-resolution encode is far too slow for the main queue; running
            // it there froze the whole viewfinder for the duration.
            let jpeg = frame?.jpegData(compressionQuality: quality)
            PhotoExporter.saveCapture(jpeg: jpeg, dng: still.raw) { ok, problem in
                guard !ok else { return }
                Task { @MainActor in
                    self.lastSaveMessage = problem ?? "Could not save to Photos"
                    self.clearMessageSoon()
                }
            }
        }
    }

    /// Writes to the roll, mirrors to Apple Photos when enabled, and saves RAW backup.
    private func keep(_ image: UIImage) {
        savedPhotoID = gallery.addPhoto(
            image,
            filmID: selectedFilm.id,
            iso: isoValue,
            shutterDenominator: shutterValue
        )

        // Save high-quality RAW (HEIF) backup
        PhotoExporter.saveAsRAW(image) { _, _ in }

        let mirrorEnabled = UserDefaults.standard.object(forKey: Pref.mirrorToPhotos) as? Bool ?? true
        guard mirrorEnabled else { return }

        PhotoExporter.saveToPhotos(image) { [weak self] ok, problem in
            Task { @MainActor in
                guard let self else { return }
                if ok {
                    self.lastSaveMessage = "✓ Saved to Photos"
                } else {
                    self.lastSaveMessage = problem ?? "Could not save to Photos"
                }
                self.clearMessageSoon()
            }
        }
    }

    /// One-off mirror for a frame taken while the setting was off.
    func mirrorCaptureToPhotos() {
        guard let image = capturedImage else { return }
        PhotoExporter.saveToPhotos(image) { [weak self] ok, problem in
            Task { @MainActor in
                guard let self else { return }
                self.lastSaveMessage = ok ? "Saved to Apple Photos" : (problem ?? "Could not save")
                self.clearMessageSoon()
            }
        }
    }

    /// Undoes the automatic save when the user rejects the frame in Review.
    func deleteCapture() {
        if let id = savedPhotoID { gallery.deletePhoto(id) }
        savedPhotoID = nil
        capturedImage = nil
        go(.viewfinder)
    }

    // MARK: - Reset, undo, redo

    /// Everything a reset touches, so it can be put back exactly.
    struct ControlSnapshot: Equatable {
        var filmID: String
        var intensity: Double
        var grain: Bool
        var halation: Bool
        var vignette: Bool
        var shutter: Double
        var iso: Double
        var whiteBalance: Double
        var exposureComp: Double
        var focusPeaking: Bool
        var autoExposure: Bool
    }

    static let defaultControls = ControlSnapshot(
        filmID: "amber", intensity: 0.8,
        grain: false, halation: false, vignette: false,
        shutter: 0.36, iso: 0.21, whiteBalance: 0.64, exposureComp: 0.5,
        focusPeaking: true, autoExposure: false
    )

    private var undoStack: [ControlSnapshot] = []
    private var redoStack: [ControlSnapshot] = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// Frames already shot on each stock, printed in the film knob's rebate.
    var frameCounts: [String: Int] {
        Dictionary(grouping: gallery.photos, by: \.filmID).mapValues(\.count)
    }

    var controls: ControlSnapshot {
        ControlSnapshot(
            filmID: selectedFilm.id, intensity: intensity,
            grain: grainOn, halation: halationOn, vignette: vignetteOn,
            shutter: shutter, iso: iso, whiteBalance: whiteBalance,
            exposureComp: exposureComp, focusPeaking: focusPeaking,
            autoExposure: autoExposure
        )
    }

    func apply(_ snapshot: ControlSnapshot) {
        if let film = FilmPreset.all.first(where: { $0.id == snapshot.filmID }) {
            selectedFilm = film
        }
        intensity = snapshot.intensity
        grainOn = snapshot.grain
        halationOn = snapshot.halation
        vignetteOn = snapshot.vignette
        shutter = snapshot.shutter
        iso = snapshot.iso
        whiteBalance = snapshot.whiteBalance
        exposureComp = snapshot.exposureComp
        focusPeaking = snapshot.focusPeaking
        autoExposure = snapshot.autoExposure
    }

    /// Back to the shipped settings. Recoverable — the previous state goes on the
    /// undo stack, so a mistaken reset costs one tap.
    func resetControls() {
        guard controls != Self.defaultControls else {
            lastSaveMessage = "Already at the default"
            clearMessageSoon()
            return
        }
        undoStack.append(controls)
        redoStack.removeAll()
        apply(Self.defaultControls)
        refreshHistory()
        lastSaveMessage = "Controls reset"
        clearMessageSoon()
    }

    func undoControls() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(controls)
        apply(previous)
        refreshHistory()
    }

    func redoControls() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(controls)
        apply(next)
        refreshHistory()
    }

    private func refreshHistory() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    /// Put the look back to the shipped default without touching exposure.
    func resetLook() {
        selectedFilm = FilmPreset.all[0]
        intensity = 0.8
        grainOn = false
        halationOn = false
        vignetteOn = false
        lastSaveMessage = "Look reset"
        clearMessageSoon()
    }

    /// Keeps what the shutter already saved and returns to shooting.
    func keepCapture() {
        savedPhotoID = nil
        capturedImage = nil
        go(.viewfinder)
    }

    /// Used by the Edit screen, which writes a new frame rather than replacing one.
    func saveCapturedPhoto() {
        guard let image = capturedImage else { return }
        keep(image)
        lastSaveMessage = "Saved to Library"
        clearMessageSoon()
    }

    func clearMessageSoon() {
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

        // Initialize defaults for settings that should be on by default
        if UserDefaults.standard.object(forKey: Pref.mirrorToPhotos) == nil {
            UserDefaults.standard.set(true, forKey: Pref.mirrorToPhotos)
        }

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
