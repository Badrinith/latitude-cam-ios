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

// MARK: - Meter readout
//
// Signed deviation from the metering target, with the verdict spelled out. Its
// own leaf so the 4Hz republish does not rebuild the screen around it.

struct MeterReadout: View {
    let frames: FrameBuffer
    var rotation: Angle

    @StateObject private var meter = HistogramSampler(bins: 32, samplesPerSecond: 4)

    var body: some View {
        HStack(spacing: 6) {
            Text(deviation)
                .font(.mono(13, .bold))
                .foregroundStyle(verdictColor)
                .contentTransition(.numericText())
            Text(verdict)
                .font(.mono(8, .semibold))
                .kerning(1.2)
                .foregroundStyle(verdictColor.opacity(0.8))
        }
        .rotationEffect(rotation)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .glass(radius: 14)
        .onAppear { meter.follow(frames) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exposure")
        .accessibilityValue(spoken)
    }

    private var stops: Double { meter.data.deviationStops }

    private var deviation: String {
        meter.data.hasData ? String(format: "%+.1f", stops) : "—"
    }

    private var verdict: String {
        guard meter.data.hasData else { return "METER" }
        if meter.data.isWellExposed { return "GOOD" }
        return stops < 0 ? "UNDER" : "OVER"
    }

    /// Severity, not decoration: amber is what "selected" looks like everywhere
    /// else here, so a drift worth acting on gets its own red.
    private var verdictColor: Color {
        guard meter.data.hasData else { return Tone.quaternary }
        if meter.data.isWellExposed { return Color(hex: 0x6FBF8F) }
        return abs(stops) > 1.5 ? Color(hex: 0xE2685A) : Color(hex: 0xE0A44E)
    }

    private var spoken: String {
        guard meter.data.hasData else { return "Metering" }
        return meter.data.isWellExposed
            ? "Good"
            : String(format: "%@ by %.1f stops", stops < 0 ? "Under" : "Over", abs(stops))
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
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: 96, alignment: .leading)
        .glass(radius: 8)
        .onAppear { sampler.follow(frames) }
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

    @StateObject private var orientation = DeviceOrientation()
    @State private var reticle: CGPoint?
    @State private var lastPreviewSize: CGSize?
    @State private var lastPinch: CGFloat = 1

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            CameraPreview(frames: app.cameraManager.frames)
                .contentShape(Rectangle())
                // A spatial tap rather than a zero-distance drag: a drag gesture
                // fires on the first finger of a pinch too, so metering used to
                // jump to wherever the pinch began.
                .onTapGesture { location in meter(at: location) }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            // Relative to the last reading, not to the start of the
                            // gesture — otherwise the zoom snaps back to where the
                            // pinch began every time the scale is re-read.
                            let step = value / lastPinch
                            lastPinch = value
                            app.pinchZoom(by: step)
                        }
                        .onEnded { _ in
                            lastPinch = 1
                            Haptics.detent()
                        }
                )

            AspectMask(aspect: aspect)

            CompositionGrid(style: gridStyle).ignoresSafeArea()

            GeometryReader { geo in
                Color.clear
                    .onAppear { lastPreviewSize = geo.size }
                    .onChange(of: geo.size) { _, size in lastPreviewSize = size }
            }
            .allowsHitTesting(false)

            if let reticle {
                Rectangle()
                    .strokeBorder(Accent.amber, lineWidth: 1)
                    .frame(width: 66, height: 66)
                    .position(reticle)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 1.35).combined(with: .opacity))
                    .zIndex(3)
            }

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

    /// The corner instruments. Unlike the barrels these are glyphs in round
    /// buttons, so they turn in place — a round button is the same shape at every
    /// angle, and only what is printed on it needs to come back upright.
    ///
    /// The exposure readouts that used to sit up here are gone: the chips above
    /// the shutter show the same three values and are now the way to change them,
    /// so keeping a second copy at arm's reach was two of everything.
    /// Instruments across the top, in one strip.
    ///
    /// They were a column down the right edge, which put them under the hand
    /// holding the phone and made each one 32pt — small for a control you reach
    /// for while framing. A row along the top is clear of the grip, and the
    /// buttons grow to 42.
    private var chrome: some View {
        VStack(spacing: 9) {
            controlRow
                .padding(.top, 6)

            HStack(spacing: 7) {
                MeterReadout(
                    frames: app.cameraManager.frames,
                    rotation: orientation.angle
                )

                // The lens buttons name the nearest marked focal length; between
                // them only a number can say where you actually are.
                if let wide = app.cameraManager.lenses.first(where: { $0.id == "wide" }) {
                    Text(String(format: "%.1f×", app.zoom / Double(wide.zoom)))
                        .font(.mono(11, .semibold))
                        .foregroundStyle(Accent.amber)
                        .rotationEffect(orientation.angle)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .glass(radius: 14)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    LiveHistogramView(
                        frames: app.cameraManager.frames,
                        style: histogramStyle
                    )
                    CameraStatusPill(camera: app.cameraManager)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { deck }
    }

    /// One capsule rather than five floating circles: the strip reads as a top
    /// plate, and the shared ground is what keeps five glyphs from looking like
    /// five unrelated decisions.
    private var controlRow: some View {
        HStack(spacing: 8) {
            Button { app.flipCamera() } label: {
                optionLabel {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(app.usingFrontCamera ? Accent.amber : Tone.primary)
                        .rotationEffect(orientation.angle)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch camera")

            Button { app.go(.settings) } label: {
                optionLabel {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Tone.primary)
                        .rotationEffect(orientation.angle)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            if app.cameraManager.supportsPortrait {
                Button { app.togglePortrait() } label: {
                    optionLabel {
                        Image(systemName: "person.and.background.dotted")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(app.portrait ? Accent.amber : Tone.primary)
                            .rotationEffect(orientation.angle)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Portrait")
            }

            Button { cycleAspect() } label: {
                optionLabel {
                    Text(aspect)
                        .font(.mono(13, .semibold))
                        .foregroundStyle(Tone.primary)
                        .rotationEffect(orientation.angle)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aspect ratio")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .glass(radius: 34)
    }

    /// Everything a thumb needs, in the band below the picture: the pro barrels,
    /// the release, then the film barrel. Nothing sits over the frame — the knob
    /// this replaces occupied the lower 340pt of every shot.
    ///
    /// The app stays locked to portrait, so turning the body does not reflow the
    /// picture. What moves is the controls: they travel to whichever screen edge
    /// is now facing the ground and turn as a whole to face the user. Turning the
    /// lettering alone was not enough — a barrel you drag sideways is the wrong
    /// shape entirely once sideways has become up. The release does not move; a
    /// shutter you have to hunt for is worse than one held at an odd angle.
    /// Taken from the cluster itself, not guessed alongside it. At 118 the open
    /// cluster overflowed its band and was drawn — and touched — over the shutter
    /// row beneath, so controls there stopped responding while nothing looked
    /// wrong. A frame does not clip what overflows it.
    private static let clusterBand: CGFloat = BarrelCluster.expandedHeight + 18
    /// Exposed so the relationship above can be asserted rather than eyeballed.
    static var clusterBandHeight: CGFloat { clusterBand }
    private static let filmBand: CGFloat = 106
    private static let shutterBand: CGFloat = 80
    private static let bandInset: CGFloat = 12

    /// One view tree in every orientation.
    ///
    /// The first attempt branched on orientation and built two different trees.
    /// SwiftUI cannot interpolate between two trees, so it swapped them — which
    /// is exactly the jump that was reported. Here the blocks are laid out at a
    /// constant size and only their rotation and centre change, and both of those
    /// animate. Nothing resizes, so there is nothing left to snap.
    private var deck: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                deckShade
                    .frame(height: 190)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(orientation.edge == .bottom ? 1 : 0)

                if app.proMode {
                    band(BarrelCluster().frame(maxHeight: .infinity, alignment: .bottom),
                         thickness: Self.clusterBand,
                         centre: clusterCentre(in: size), length: size.width)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                }

                band(filmSelector, thickness: Self.filmBand,
                     centre: filmCentre(in: size), length: size.width)

                // Fixed. A shutter you have to hunt for is worse than one held at
                // an odd angle, so it keeps its place whichever way the body turns.
                shutterRow
                    .frame(width: size.width, height: Self.shutterBand)
                    .position(
                        x: size.width / 2,
                        y: size.height - Self.bandInset - Self.filmBand - Self.shutterBand / 2
                    )
            }
        }
    }

    /// Laid out along the screen's width in every orientation, then turned about
    /// its own centre. Keeping the frame constant is what makes the move
    /// animatable — a block that also resized would snap however it was eased.
    private func band<C: View>(
        _ content: C, thickness: CGFloat, centre: CGPoint, length: CGFloat
    ) -> some View {
        content
            .frame(width: length, height: thickness)
            .background {
                deckShade.opacity(orientation.edge == .bottom ? 0 : 1)
            }
            .rotationEffect(orientation.angle)
            .position(centre)
    }

    private func filmCentre(in size: CGSize) -> CGPoint {
        switch orientation.edge {
        case .bottom:
            return CGPoint(x: size.width / 2, y: size.height - Self.bandInset - Self.filmBand / 2)
        case .leading:
            return CGPoint(x: Self.bandInset + Self.filmBand / 2, y: size.height / 2)
        case .trailing:
            return CGPoint(x: size.width - Self.bandInset - Self.filmBand / 2, y: size.height / 2)
        }
    }

    private func clusterCentre(in size: CGSize) -> CGPoint {
        switch orientation.edge {
        case .bottom:
            // Above the release, with the film barrel below it — the portrait
            // arrangement, unchanged.
            return CGPoint(
                x: size.width / 2,
                y: size.height - Self.bandInset - Self.filmBand
                    - Self.shutterBand - Self.clusterBand / 2
            )
        case .leading:
            return CGPoint(x: Self.bandInset + Self.filmBand + Self.clusterBand / 2,
                           y: size.height / 2)
        case .trailing:
            return CGPoint(x: size.width - Self.bandInset - Self.filmBand - Self.clusterBand / 2,
                           y: size.height / 2)
        }
    }

    private var filmSelector: some View {
        FilmTwoTier(onOpenDetail: { app.go(.filmSim) })
    }

    /// The release is centred in its own layer so nothing beside it can shift it.
    /// A shutter that moves when a lens is added is a shutter you have to look for.
    private var shutterRow: some View {
        ZStack {
            ShutterButton { fire() }

            HStack(spacing: 9) {
                Button { app.go(.library) } label: {
                    LibraryThumbnail(gallery: app.gallery)
                }
                .buttonStyle(.plain)

                proButton

                Spacer(minLength: 0)

                LensBarrel(
                    camera: app.cameraManager,
                    selected: app.lensID,
                    onSelect: { app.selectLens($0) }
                )
            }
            .padding(.horizontal, 18)
        }
    }

    private var proButton: some View {
        Button {
            Haptics.toggle()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                app.proMode.toggle()
            }
        } label: {
            Text("PRO")
                .font(.mono(13, .bold))
                .kerning(0.9)
                .foregroundStyle(app.proMode ? Ink.base : Tone.secondary)
                .rotationEffect(orientation.angle)
                .frame(width: 52, height: 36)
                .background {
                    if app.proMode {
                        Capsule().fill(Accent.amber)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                            .overlay { Capsule().fill(Color.black.opacity(0.2)) }
                            .overlay { Capsule().strokeBorder(Tone.hairline, lineWidth: 0.5) }
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pro controls")
    }

    private var deckShade: some View {
        LinearGradient(
            colors: [.clear, Color.black.opacity(0.72)],
            startPoint: .top, endPoint: .bottom
        )
        .allowsHitTesting(false)
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

    /// Normalised sensor coordinates. The preview is rotated 90° into portrait,
    /// so the screen's x is the sensor's y — swapping them here is what makes the
    /// reticle land where the thumb did.
    private func meter(at point: CGPoint) {
        guard let size = lastPreviewSize, size.width > 1, size.height > 1 else { return }
        let normalised = CGPoint(
            x: min(max(point.y / size.height, 0), 1),
            y: min(max(1 - point.x / size.width, 0), 1)
        )
        Haptics.tap()
        app.pointOfInterest = normalised
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            reticle = point
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.3)) { reticle = nil }
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

    /// 50pt. These are reached for while the other hand holds the phone and the
    /// eye is on the picture, which is the worst case for a small target — well
    /// past the 44 Apple asks for, because a miss here costs the shot. The strip
    /// behind them carries the glass, so each button only needs its own tint.
    private func optionLabel<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .frame(width: 50, height: 50)
            .background {
                Circle().fill(Color.white.opacity(0.07))
            }
            .contentShape(Circle())
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

    @AppStorage(Pref.captureFormat) private var captureFormat = "RAW + JPEG"
    @AppStorage(Pref.captureResolution) private var captureResolution = "Full"

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

            ChipRow(label: "Format", options: Pref.captureFormatOptions, selection: $captureFormat)
            ChipRow(label: "Resolution", options: Pref.captureResolutionOptions, selection: $captureResolution)

            if !app.cameraManager.supportsRAW {
                Text("This camera has no RAW format — captures save as JPEG.")
                    .font(.ui(11))
                    .foregroundStyle(Tone.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
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
