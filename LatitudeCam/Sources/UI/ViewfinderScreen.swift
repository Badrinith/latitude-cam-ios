//
//  ViewfinderScreen.swift
//  LatitudeCam
//
//  The camera screen, plus the Manual Controls sheet it presents.
//

import SwiftUI

// MARK: - Live preview
//
// Frames arrive 30 times a second. This view observes the frame buffer alone, so
// SwiftUI reinvalidates a single Image and leaves the chrome — sliders, film
// strip, sheets — untouched. Observing the whole camera (or forcing a new .id on
// the screen) rebuilt every control mid-gesture, which is what made the buttons
// feel dead.

struct CameraPreview: View {
    @ObservedObject var frames: FrameBuffer

    var body: some View {
        GeometryReader { geo in
            if let image = frames.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                StripePattern.viewfinder
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
    }
}

/// Dims what the chosen aspect ratio will crop away, so the badge is a promise
/// the user can see rather than a label.
struct AspectMask: View {
    var aspect: String

    var body: some View {
        GeometryReader { geo in
            if let ratio = Pref.aspectRatio(aspect) {
                let keepHeight = min(geo.size.height, geo.size.width * ratio)
                let bar = max(0, (geo.size.height - keepHeight) / 2)
                VStack(spacing: 0) {
                    Color.black.opacity(0.55).frame(height: bar)
                    Spacer(minLength: 0)
                    Color.black.opacity(0.55).frame(height: bar)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Reports session state. Separate from the preview because status changes a
/// handful of times per launch, not 30 times a second.
struct CameraStatusPill: View {
    @ObservedObject var camera: CameraManager

    var body: some View {
        if let text = message {
            Text(text)
                .font(.mono(10, .medium))
                .foregroundStyle(Tone.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glass(radius: 8)
        }
    }

    private var message: String? {
        switch camera.status {
        case .running:              return nil
        case .idle:                 return "STARTING CAMERA…"
        case .requestingPermission: return "AWAITING CAMERA ACCESS"
        case .denied:               return "CAMERA ACCESS DENIED — SETTINGS › LATITUDE"
        case .noDevice:             return "NO CAMERA ON THIS DEVICE"
        case .failed(let reason):   return "CAMERA ERROR — \(reason.uppercased())"
        }
    }
}

// MARK: - Live histogram
//
// Owns its sampler so the 5Hz republish stays inside this leaf. Hanging the
// sampler off ViewfinderScreen would drag the whole screen along with it.

struct LiveHistogramView: View {
    let frames: FrameBuffer
    var style: String

    @StateObject private var sampler = HistogramSampler()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Canvas { context, size in
                if style == "RGB" {
                    draw(sampler.data.red, in: &context, size: size, color: .red)
                    draw(sampler.data.green, in: &context, size: size, color: .green)
                    draw(sampler.data.blue, in: &context, size: size, color: .blue)
                } else {
                    draw(sampler.data.luma, in: &context, size: size, color: Accent.amber, opacity: 0.95)
                }
            }
            .frame(width: 84, height: 30)

            Text(sampler.data.hasData ? sampler.data.exposure.uppercased() : "—")
                .font(.mono(8, .semibold))
                .foregroundStyle(verdictColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: 96, alignment: .leading)
        .glass(radius: 8)
        .onAppear { sampler.follow(frames) }
    }

    private var verdictColor: Color {
        guard sampler.data.hasData else { return Tone.quaternary }
        switch sampler.data.exposure {
        case "Under", "Over": return Accent.amber
        default:              return Tone.secondary
        }
    }

    private func draw(
        _ buckets: [Double],
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color,
        opacity: Double = 0.55
    ) {
        guard buckets.count > 1 else { return }
        let step = size.width / CGFloat(buckets.count - 1)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, value) in buckets.enumerated() {
            path.addLine(to: CGPoint(
                x: CGFloat(i) * step,
                y: size.height - CGFloat(value) * size.height
            ))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()

        context.fill(path, with: .color(color.opacity(opacity)))
    }
}

// MARK: - Viewfinder

struct ViewfinderScreen: View {
    @EnvironmentObject var app: AppState

    @AppStorage(Pref.grid) private var gridStyle = "Rule of Thirds"
    @AppStorage(Pref.aspect) private var aspect = "3:2"
    @AppStorage(Pref.histogramStyle) private var histogramStyle = "Luma"

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            CameraPreview(frames: app.cameraManager.frames)

            AspectMask(aspect: aspect)

            CompositionGrid(style: gridStyle).ignoresSafeArea()

            chrome

            if let message = app.lastSaveMessage {
                Text(message)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Tone.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glass(radius: 12)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if app.proSheetOpen {
                BottomSheet(onDismiss: { app.proSheetOpen = false }) {
                    ManualControlsSheet()
                }
                .zIndex(1)
            }
        }
        // Scoped to the sheet only. Animating the whole ZStack meant every frame
        // arriving from the camera kicked off an implicit animation.
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.proSheetOpen)
        .animation(.easeInOut(duration: 0.2), value: app.lastSaveMessage)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            // Settings pill on the left, exposure readouts centred.
            ZStack {
                hud

                HStack {
                    Button { app.go(.settings) } label: {
                        Text("SETTINGS")
                            .font(.mono(10, .semibold))
                            .kerning(0.5)
                            .foregroundStyle(Color.white.opacity(0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glass(radius: 16)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    LiveHistogramView(
                        frames: app.cameraManager.frames,
                        style: histogramStyle
                    )
                    CameraStatusPill(camera: app.cameraManager)
                }

                Spacer()

                VStack(spacing: 8) {
                    Button { cycleAspect() } label: {
                        optionLabel {
                            Text(aspect)
                                .font(.mono(9, .semibold))
                                .foregroundStyle(Tone.primary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.toggle()
                        app.proRAW.toggle()
                    } label: {
                        optionLabel {
                            Text("RAW")
                                .font(.mono(8, .semibold))
                                .foregroundStyle(app.proRAW ? Accent.amber : Tone.quaternary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.toggle()
                        app.focusPeaking.toggle()
                    } label: {
                        optionLabel {
                            Circle()
                                .strokeBorder(
                                    app.focusPeaking ? Accent.amber : Tone.quaternary,
                                    lineWidth: 1.5
                                )
                                .frame(width: 12, height: 12)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { deck }
    }

    /// The knob and the shutter share one region, so the thumb turns the roll and
    /// lands on the release without repositioning.
    private var deck: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.66)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 340)
            .allowsHitTesting(false)

            FilmKnob(
                presets: FilmPreset.all,
                selection: $app.selectedFilm,
                previews: app.cameraManager.filmPreviews,
                counts: app.frameCounts,
                onOpenDetail: { app.go(.filmSim) }
            )
            .frame(height: 340)

            HStack {
                Button { app.proSheetOpen = true } label: {
                    Text("PRO")
                        .font(.ui(13, .semibold))
                        .foregroundStyle(Accent.amber)
                }
                .buttonStyle(.plain)

                Spacer()

                ShutterButton { fire() }

                Spacer()

                Button { app.go(.library) } label: {
                    LibraryThumbnail(gallery: app.gallery)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 22)   // FilmKnob.hubFromBottom assumes 22 + 37

        }
    }

    /// A heavy thump when a frame is taken, a warning when there was nothing to
    /// take. The two must not feel the same.
    private func fire() {
        if app.capture() {
            Haptics.shutter()
        } else {
            Haptics.blocked()
        }
    }

    private func cycleAspect() {
        Haptics.detent()
        let options = Pref.aspectOptions
        let next = (options.firstIndex(of: aspect).map { $0 + 1 } ?? 0) % options.count
        withAnimation(.snappy(duration: 0.2)) { aspect = options[next] }
    }

    /// One capsule instead of three floating pills, and each segment opens the
    /// control it displays — the value you can see is the value you can change.
    private var hud: some View {
        HStack(spacing: 0) {
            hudSegment(app.shutterLabel, focus: "shutter")
            hudDivider
            hudSegment(app.isoLabel, focus: "iso")
            hudDivider
            hudSegment(app.kelvinLabel, focus: "wb")
        }
        .glass(radius: 10)
    }

    private func hudSegment(_ text: String, focus: String) -> some View {
        Button {
            Haptics.tap()
            app.proFocus = focus
            app.proSheetOpen = true
        } label: {
            Text(text)
                .font(.mono(12, .medium))
                .foregroundStyle(Tone.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hudDivider: some View {
        Rectangle().fill(Tone.hairline).frame(width: 0.5, height: 14)
    }

    private func optionLabel<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .frame(width: 32, height: 32)
            .glass(radius: 16)
            .contentShape(Rectangle())
    }
}

/// The most recent shot, so the corner button reflects the roll.
struct LibraryThumbnail: View {
    @ObservedObject var gallery: PhotoGallery

    var body: some View {
        Group {
            if let latest = gallery.photos.first {
                Image(uiImage: latest.image)
                    .resizable()
                    .scaledToFill()
            } else {
                StripePattern.thumbnail
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
        }
    }
}

// MARK: - Manual controls sheet

struct ManualControlsSheet: View {
    @EnvironmentObject var app: AppState

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            header

            LazyVGrid(columns: columns, spacing: 18) {
                RotaryDial(
                    label: "Shutter",
                    values: AppState.shutterLabels,
                    index: Binding(get: { app.shutterIndex }, set: { app.shutterIndex = $0 }),
                    hasAuto: true,
                    highlighted: app.proFocus == "shutter"
                )
                RotaryDial(
                    label: "ISO",
                    values: AppState.isoLabels,
                    index: Binding(get: { app.isoIndex }, set: { app.isoIndex = $0 }),
                    hasAuto: true,
                    highlighted: app.proFocus == "iso"
                )
                RotaryDial(
                    label: "White Balance",
                    values: AppState.whiteBalanceLabels,
                    index: Binding(get: { app.whiteBalanceIndex }, set: { app.whiteBalanceIndex = $0 }),
                    highlighted: app.proFocus == "wb"
                )
                RotaryDial(
                    label: "Exposure",
                    values: AppState.exposureLabels,
                    index: Binding(get: { app.exposureIndex }, set: { app.exposureIndex = $0 }),
                    neutralIndex: AppState.evDetents / 2
                )
            }
            .padding(.bottom, 20)

            ToggleRow(label: "Focus Peaking", isOn: $app.focusPeaking)
            ToggleRow(label: "ProRAW", isOn: $app.proRAW)

            Divider().padding(.vertical, 12)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capture Format")
                        .font(.ui(13))
                        .foregroundStyle(Tone.secondary)
                    Menu {
                        Picker("Format", selection: Binding(
                            get: { UserDefaults.standard.string(forKey: Pref.captureFormat) ?? "RAW + JPEG" },
                            set: { UserDefaults.standard.set($0, forKey: Pref.captureFormat); Haptics.detent() }
                        )) {
                            ForEach(Pref.captureFormatOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                    } label: {
                        Text(UserDefaults.standard.string(forKey: Pref.captureFormat) ?? "RAW + JPEG")
                            .font(.ui(14, .medium))
                            .foregroundStyle(Tone.primary)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Resolution")
                        .font(.ui(13))
                        .foregroundStyle(Tone.secondary)
                    Menu {
                        Picker("Resolution", selection: Binding(
                            get: { UserDefaults.standard.string(forKey: Pref.captureResolution) ?? "Full" },
                            set: { UserDefaults.standard.set($0, forKey: Pref.captureResolution); Haptics.detent() }
                        )) {
                            ForEach(Pref.captureResolutionOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                    } label: {
                        Text(UserDefaults.standard.string(forKey: Pref.captureResolution) ?? "Full")
                            .font(.ui(14, .medium))
                            .foregroundStyle(Tone.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        // The highlight is a pointer, not a mode — it clears once the sheet has
        // done its job of showing you where the control lives.
        .onDisappear { app.proFocus = nil }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("Manual Controls")
                .font(.ui(15, .semibold))
                .foregroundStyle(Tone.primary)

            Spacer()

            // Reset is recoverable: the previous state goes on the undo stack, so
            // a mistaken tap costs one more tap rather than your whole setup.
            historyButton(systemName: "arrow.uturn.backward", enabled: app.canUndo) {
                app.undoControls()
            }
            historyButton(systemName: "arrow.uturn.forward", enabled: app.canRedo) {
                app.redoControls()
            }

            Button { app.resetControls() } label: {
                Text("Reset")
                    .font(.ui(12, .semibold))
                    .foregroundStyle(Tone.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)

            Button { app.proSheetOpen = false } label: {
                Text("Done")
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Accent.amber)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 18)
    }

    private func historyButton(
        systemName: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.toggle()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Tone.primary : Tone.quaternary)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(enabled ? 0.07 : 0.03), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
