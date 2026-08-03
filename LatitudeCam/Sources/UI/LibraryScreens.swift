//
//  LibraryScreens.swift
//  LatitudeCam
//
//  Film Sim, Library, and Edit.
//

import SwiftUI

// MARK: - Film Sim

struct FilmSimScreen: View {
    @EnvironmentObject var app: AppState

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BackLink(title: "Viewfinder") { app.go(.viewfinder) }
                        .padding(.bottom, 16)

                    Text("Film Sim")
                        .font(.ui(22, .bold))
                        .foregroundStyle(Tone.primary)
                        .padding(.bottom, 16)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(FilmPreset.all) { preset in
                            PresetCard(preset: preset, isSelected: preset.id == app.selectedFilm.id) {
                                Haptics.detent()
                                withAnimation(.snappy(duration: 0.2)) { app.selectedFilm = preset }
                            }
                        }
                    }
                    .padding(.bottom, 18)

                    LookPanel(title: app.selectedFilm.name)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct PresetCard: View {
    var preset: FilmPreset
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(preset.swatch)
                    .frame(height: 70)
                    .padding(.bottom, 8)

                Text(preset.name)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Tone.primary)

                Text(preset.blurb)
                    .font(.ui(11))
                    .foregroundStyle(Tone.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Accent.amber : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Intensity + grain/halation/vignette — shared by Film Sim and the Edit tab.
struct LookPanel: View {
    @EnvironmentObject var app: AppState
    var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Tone.primary)
                    .padding(.bottom, 12)
            }

            SliderRow(
                label: title == nil ? "\(app.selectedFilm.name) Intensity" : "Intensity",
                value: "\(Int(app.intensity * 100))%",
                position: $app.intensity
            )
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                Chip(title: "Grain", isActive: app.grainOn) { Haptics.toggle(); app.grainOn.toggle() }
                Chip(title: "Halation", isActive: app.halationOn) { Haptics.toggle(); app.halationOn.toggle() }
                Chip(title: "Vignette", isActive: app.vignetteOn) { Haptics.toggle(); app.vignetteOn.toggle() }
            }
        }
        .padding(title == nil ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if title != nil {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Ink.card)
            }
        }
    }
}

// MARK: - Library

struct LibraryScreen: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BackLink(title: "Viewfinder") { app.go(.viewfinder) }
                        .padding(.bottom, 16)

                    Text("Library")
                        .font(.ui(22, .bold))
                        .foregroundStyle(Tone.primary)
                        .padding(.bottom, 16)

                    LibraryGrid(gallery: app.gallery)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }
}

/// Owns the filter state and the gallery subscription so the surrounding screen
/// does not rebuild when photos load in off the disk queue.
private struct LibraryGrid: View {
    @ObservedObject var gallery: PhotoGallery
    @EnvironmentObject var app: AppState
    @State private var filter = "All"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var filtered: [PhotoGallery.Photo] {
        guard filter != "All" else { return gallery.photos }
        return gallery.photos.filter { $0.filmID == filter.lowercased() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(["All"] + FilmPreset.all.map(\.shortName), id: \.self) { name in
                    FilterChip(title: name, isActive: filter == name) {
                        Haptics.detent()
                        withAnimation(.snappy(duration: 0.2)) { filter = name }
                    }
                }
            }
            .padding(.bottom, 14)

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Text(gallery.photos.isEmpty ? "No shots yet" : "Nothing in this simulation")
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Tone.secondary)
                    Text(gallery.photos.isEmpty
                         ? "Tap the shutter in the viewfinder to start a roll."
                         : "Try another filter.")
                        .font(.ui(12))
                        .foregroundStyle(Tone.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(filtered) { photo in
                        Button {
                            Haptics.tap()
                            app.editingPhoto = photo
                            app.go(.edit)
                        } label: {
                            // Colour.clear sets the cell size and the photo fills
                            // it from an overlay. Sizing the Image directly let a
                            // 1080px frame lay out far bigger than its cell —
                            // clipped() hides that but hit testing still used the
                            // full bounds, so the top row swallowed taps meant for
                            // the back button.
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    Image(uiImage: photo.image)
                                        .resizable()
                                        .scaledToFill()
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(alignment: .bottomLeading) {
                                    Circle()
                                        .fill(swatch(for: photo.filmID))
                                        .frame(width: 8, height: 8)
                                        .overlay {
                                            Circle().strokeBorder(
                                                photo.filmID == "mono"
                                                    ? Color.white.opacity(0.3) : .clear,
                                                lineWidth: 1
                                            )
                                        }
                                        .padding(5)
                                }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                Haptics.toggle()
                                gallery.deletePhoto(photo.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private func swatch(for filmID: String) -> Color {
        FilmPreset.all.first { $0.id == filmID }?.swatch ?? FilmSwatch.amber
    }
}

// MARK: - Edit

struct EditScreen: View {
    @EnvironmentObject var app: AppState
    @StateObject private var editor = PhotoEditor()
    @State private var tab = "Light"

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                preview
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(16)

                tabBar
                    .padding(.bottom, 14)

                panel
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
            }
        }
        .onAppear { editor.load(app.editingPhoto) }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            BackLink(title: "Library") { app.go(.library) }
            Spacer()
            Text("Edit")
                .font(.ui(15, .semibold))
                .foregroundStyle(Tone.primary)
            Spacer()
            Button {
                Haptics.success()
                save()
            } label: {
                Text("Save")
                    .font(.ui(13, .semibold))
                    .foregroundStyle(editor.canSave ? Accent.amber : Tone.quaternary)
            }
            .buttonStyle(.plain)
            .disabled(!editor.canSave)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Edits are non-destructive: the original stays in the roll and the result
    /// is filed as a new frame, so a bad edit can never eat the only copy.
    private func save() {
        guard let edited = editor.flattened(), let source = app.editingPhoto else { return }
        app.gallery.addPhoto(
            edited,
            filmID: editor.filmID,
            iso: source.iso,
            shutterDenominator: source.shutterDenominator
        )
        app.go(.library)
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            Ink.card
            if let image = editor.preview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(app.editingPhoto == nil ? "NO PHOTO SELECTED" : "LOADING…")
                    .font(.mono(11, .medium))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 22) {
            ForEach(["Light", "Color", "Film", "Crop"], id: \.self) { name in
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.2)) { tab = name }
                } label: {
                    VStack(spacing: 4) {
                        Text(name)
                            .font(.ui(12, .semibold))
                            .foregroundStyle(tab == name ? Accent.amber : Tone.quaternary)
                        Rectangle()
                            .fill(tab == name ? Accent.amber : .clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch tab {
        case "Light":
            VStack(spacing: 16) {
                SliderRow(
                    label: "Exposure",
                    value: String(format: "%+.1f EV", editor.exposureEV),
                    position: $editor.exposure,
                    bipolar: true
                )
                SliderRow(
                    label: "Contrast",
                    value: String(format: "%.2f", editor.contrastValue),
                    position: $editor.contrast,
                    bipolar: true
                )
            }

        case "Color":
            VStack(spacing: 16) {
                SliderRow(
                    label: "Saturation",
                    value: String(format: "%.2f", editor.saturationValue),
                    position: $editor.saturation,
                    bipolar: true
                )
                SliderRow(
                    label: "Temperature",
                    value: "\(Int(editor.kelvinValue))K",
                    position: $editor.temperature,
                    temperatureTrack: true
                )
            }

        case "Film":
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(FilmPreset.all) { preset in
                        Chip(title: preset.shortName, isActive: preset.id == editor.filmID) {
                            Haptics.detent()
                            withAnimation(.snappy(duration: 0.2)) { editor.filmID = preset.id }
                        }
                    }
                }
                SliderRow(
                    label: "Intensity",
                    value: "\(Int(editor.intensity * 100))%",
                    position: $editor.intensity
                )
                HStack(spacing: 8) {
                    Chip(title: "Grain", isActive: editor.grain) { Haptics.toggle(); editor.grain.toggle() }
                    Chip(title: "Halation", isActive: editor.halation) { Haptics.toggle(); editor.halation.toggle() }
                    Chip(title: "Vignette", isActive: editor.vignette) { Haptics.toggle(); editor.vignette.toggle() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // Crop
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(PhotoEditor.cropOptions, id: \.self) { name in
                        Chip(title: name, isActive: editor.crop == name) {
                            Haptics.detent()
                            withAnimation(.snappy(duration: 0.2)) { editor.crop = name }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Chip(title: "Rotate 90°", isActive: false) { Haptics.detent(); editor.rotate() }
                    Chip(title: "Reset", isActive: false) { Haptics.toggle(); editor.reset() }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Photo editor
//
// Holds the in-flight edit for one library photo. Rendering runs on a background
// queue and publishes a preview; doing CoreImage work inside `body` would stall
// the main thread on every slider tick, which is the failure mode this app spent
// a long time recovering from.

final class PhotoEditor: ObservableObject {

    static let cropOptions = ["Original", "1:1", "4:5", "16:9"]

    @Published private(set) var preview: UIImage?

    // Sliders are 0…1 so they can drive SliderRow directly; 0.5 is "no change"
    // for the bipolar ones.
    @Published var exposure: Double = 0.5 { didSet { scheduleRender() } }
    @Published var contrast: Double = 0.5 { didSet { scheduleRender() } }
    @Published var saturation: Double = 0.5 { didSet { scheduleRender() } }
    @Published var temperature: Double = 0.5 { didSet { scheduleRender() } }
    @Published var filmID: String = "amber" { didSet { scheduleRender() } }
    @Published var intensity: Double = 0 { didSet { scheduleRender() } }
    @Published var grain = false { didSet { scheduleRender() } }
    @Published var halation = false { didSet { scheduleRender() } }
    @Published var vignette = false { didSet { scheduleRender() } }
    @Published var crop = "Original" { didSet { scheduleRender() } }
    @Published private(set) var quarterTurns = 0

    var canSave: Bool { source != nil }

    var exposureEV: Double { (exposure - 0.5) * 4 }
    var contrastValue: Double { 0.5 + contrast }
    var saturationValue: Double { saturation * 2 }
    var kelvinValue: Double { ((3000 + temperature * 6000) / 100).rounded() * 100 }

    private var source: CIImage?
    private var sourceScale: CGFloat = 1
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let noiseTile = CameraManager.makeNoiseTile()
    private let renderQueue = DispatchQueue(label: "com.latitude.editor", qos: .userInitiated)
    private var pending: DispatchWorkItem?

    // MARK: Loading

    func load(_ photo: PhotoGallery.Photo?) {
        guard let photo, let cg = photo.image.cgImage else {
            source = nil
            preview = nil
            return
        }
        source = CIImage(cgImage: cg)
        sourceScale = photo.image.scale
        filmID = photo.filmID          // triggers the first render
    }

    func rotate() {
        quarterTurns = (quarterTurns + 1) % 4
        scheduleRender()
    }

    func reset() {
        exposure = 0.5
        contrast = 0.5
        saturation = 0.5
        temperature = 0.5
        intensity = 0
        grain = false
        halation = false
        vignette = false
        crop = "Original"
        quarterTurns = 0
        scheduleRender()
    }

    // MARK: Rendering

    private var params: Params {
        Params(
            ev: exposureEV, contrast: contrastValue, saturation: saturationValue,
            kelvin: kelvinValue, filmID: filmID, intensity: intensity,
            grain: grain, halation: halation, vignette: vignette,
            crop: crop, quarterTurns: quarterTurns
        )
    }

    /// Coalesces the burst of changes a drag produces into one render.
    private func scheduleRender() {
        guard let source else { return }
        pending?.cancel()

        let snapshot = params
        let scale = sourceScale
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let image = Self.render(
                source, params: snapshot, context: self.context, noise: self.noiseTile, scale: scale
            )
            DispatchQueue.main.async { self.preview = image }
        }
        pending = work
        renderQueue.asyncAfter(deadline: .now() + 0.02, execute: work)
    }

    /// The saved frame is the same pipeline as the preview — no second code path
    /// that could drift from what the user approved on screen.
    func flattened() -> UIImage? {
        guard let source else { return nil }
        return Self.render(source, params: params, context: context, noise: noiseTile, scale: sourceScale)
    }

    struct Params: Equatable {
        var ev: Double
        var contrast: Double
        var saturation: Double
        var kelvin: Double
        var filmID: String
        var intensity: Double
        var grain: Bool
        var halation: Bool
        var vignette: Bool
        var crop: String
        var quarterTurns: Int
    }

    static func render(
        _ source: CIImage,
        params: Params,
        context: CIContext,
        noise: CIImage?,
        scale: CGFloat
    ) -> UIImage? {
        var image = source

        if abs(params.ev) > 0.001 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: params.ev])
        }

        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: params.contrast,
            kCIInputSaturationKey: params.saturation
        ])

        image = image.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: CGFloat(params.kelvin), y: 0),
            "inputTargetNeutral": CIVector(x: 6500, y: 0)
        ])

        // Same matrices the live viewfinder uses, so a look chosen while shooting
        // reproduces exactly here.
        if params.intensity > 0.001 {
            let t = CGFloat(min(max(params.intensity, 0), 1))
            let (fr, fg, fb) = CameraManager.filmVectors(params.filmID)
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CameraManager.lerp(CIVector(x: 1, y: 0, z: 0, w: 0), fr, t),
                "inputGVector": CameraManager.lerp(CIVector(x: 0, y: 1, z: 0, w: 0), fg, t),
                "inputBVector": CameraManager.lerp(CIVector(x: 0, y: 0, z: 1, w: 0), fb, t)
            ])
        }

        let beforeEffects = image.extent
        if params.halation {
            image = image
                .applyingFilter("CIBloom", parameters: [
                    kCIInputRadiusKey: 12.0, kCIInputIntensityKey: 0.7
                ])
                .cropped(to: beforeEffects)
        }

        if params.vignette {
            image = image.applyingFilter("CIVignette", parameters: [
                kCIInputRadiusKey: 1.4, kCIInputIntensityKey: 1.2
            ])
        }

        if params.grain, let noise {
            image = noise
                .cropped(to: image.extent)
                .applyingFilter("CIOverlayBlendMode", parameters: [
                    kCIInputBackgroundImageKey: image
                ])
        }

        image = crop(image, to: params.crop)
        image = rotate(image, quarterTurns: params.quarterTurns)

        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    /// Height ÷ width, matching the crop chip labels.
    static func cropRatio(_ name: String) -> CGFloat? {
        switch name {
        case "1:1":  return 1
        case "4:5":  return 5.0 / 4.0
        case "16:9": return 9.0 / 16.0
        default:     return nil
        }
    }

    static func crop(_ image: CIImage, to name: String) -> CIImage {
        guard let ratio = cropRatio(name) else { return image }

        let extent = image.extent
        var width = extent.width
        var height = width * ratio
        if height > extent.height {
            height = extent.height
            width = height / ratio
        }

        let rect = CGRect(
            x: extent.minX + (extent.width - width) / 2,
            y: extent.minY + (extent.height - height) / 2,
            width: width,
            height: height
        )
        return image.cropped(to: rect)
    }

    static func rotate(_ image: CIImage, quarterTurns: Int) -> CIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }

        let rotated = image.transformed(
            by: CGAffineTransform(rotationAngle: -CGFloat(turns) * .pi / 2)
        )
        // Rotation moves the extent off the origin; CGImage creation expects it
        // back at zero.
        return rotated.transformed(
            by: CGAffineTransform(translationX: -rotated.extent.minX, y: -rotated.extent.minY)
        )
    }
}
