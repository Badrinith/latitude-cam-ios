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
    @AppStorage(Pref.rawProgressDesign) private var rawProgressDesign = "01 Aperture Bloom"
    @AppStorage(Pref.viewfinderControls) private var controlStyle = "Top Plate"

    @StateObject private var orientation = DeviceOrientation()
    @State private var reticle: CGPoint?
    @State private var lastPreviewSize: CGSize?
    @State private var lastPinch: CGFloat = 1
    /// Bellows only. Kept here rather than inside the drawer so the drawer's
    /// position survives the deck being rebuilt by an unrelated state change.
    @State private var bellowsOpen = false

    /// Top Plate only. Set while a dial is turning and cleared a beat after it
    /// stops, which is what puts the barrel on screen and takes it away again.
    @State private var activeDial: ActiveDial?
    @State private var dialIdleTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            // Grouped so Top Plate can inset the whole picture below its metal
            // band in one place. The plate is opaque — in the handoff the frame
            // starts under it rather than running behind it — and the mask, the
            // grid, the measured size and the reticle all have to agree about
            // where the picture actually is, or metering lands off the thumb.
            ZStack {
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

                CompositionGrid(style: gridStyle)

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
            }
            // The plate is translucent now, so the picture runs the full height
            // behind it instead of being inset below opaque metal — the top of
            // the frame is visible rather than paid for.
            .ignoresSafeArea()

            chrome

            if app.rawCaptureInProgress {
                RAWCaptureProgressOverlay(
                    design: rawProgressDesign,
                    progress: app.rawCaptureProgress
                )
                .allowsHitTesting(false)
                .zIndex(4)
            }

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
    @ViewBuilder private var chrome: some View {
        if controlStyle == "Top Plate" {
            topPlateChrome
        } else {
            classicChrome
        }
    }

    /// The handoff's screen. Unlike the other three styles this is not a deck
    /// hung under the existing chrome — the metal plate replaces the glass
    /// strip outright, so the whole frame is arranged here rather than layered
    /// over the classic one.
    private var topPlateChrome: some View {
        VStack(spacing: 0) {
            TopPlateBand(
                rotation: orientation.angle,
                compact: orientation.edge != .bottom,
                onSettings: { app.go(.settings) },
                onCycleGrid: cycleGrid,
                onCycleAspect: cycleAspect,
                aspect: aspect,
                onDialTurn: showBarrel
            )

            TopPlateDeck(
                rotation: orientation.angle,
                landscape: orientation.edge != .bottom,
                histogramStyle: histogramStyle,
                aspect: aspect,
                onSettings: { app.go(.settings) },
                onFilmSim: { app.go(.filmSim) },
                onLibrary: { app.go(.library) },
                onFire: fire,
                onDialTurn: showBarrel,
                onResetDial: resetDial
            )
            .background(alignment: .bottom) {
                deckShade.frame(height: 260)
            }
        }
        .ignoresSafeArea(edges: .top)
        // Portrait: the barrel hangs under the plate, where the dials are.
        .overlay(alignment: .top) {
            if let activeDial, orientation.edge == .bottom {
                DialBarrel(dial: activeDial, rotation: .zero,
                           onScrub: { scrub(activeDial.key, by: $0) })
                    .padding(.horizontal, 12)
                    .padding(.top, TopPlateBand.height + 10)
                    .transition(.opacity.combined(with: .offset(y: -10)))
                    .zIndex(4)
            }
        }
        // Turned, both bands go against the edges that are physically up and
        // down rather than the ones the portrait layout calls top and bottom.
        // Pinning them to .top and .bottom is what put the barrel over the
        // switch row and the film strip on top of the shutter.
        //
        // The barrel takes the ground edge and film takes the sky. The barrel is
        // the one that gets dragged — it is a control, not a readout — so it
        // belongs where the thumb already is when the phone is held one-handed.
        // Film is a swipe you make deliberately, and it can be reached for.
        .overlay {
            if orientation.edge != .bottom {
                GeometryReader { geo in
                    // Instruments at the sky edge, laid out horizontally and
                    // turned as one piece.
                    rotatedBand(
                        TopPlateDeck.landscapeInstruments(
                            camera: app.cameraManager,
                            zoom: app.zoom,
                            histogramStyle: histogramStyle
                        ),
                        thickness: 54, at: skyEdge, in: geo.size
                    )

                    // Film moves to the leading side of the frame, beside the
                    // release rather than opposite it — asked for, and it keeps
                    // the sky edge for reading and the ground edge for turning.
                    rotatedBand(
                        TopPlateDeck.landscapeFilm(rotation: .zero,
                                                   onOpen: { app.go(.filmSim) }),
                        thickness: 118, at: .leading, in: geo.size
                    )
                    .opacity(activeDial == nil ? 1 : 0.25)

                    // The rail takes the ground edge, under the hand.
                    if app.proMode {
                        rotatedBand(
                            DialStrip(rotation: .zero, compact: true,
                                      onDialTurn: showBarrel, onReset: resetDial),
                            thickness: DialStrip.height, at: orientation.edge, in: geo.size
                        )
                    }

                    if let activeDial {
                        rotatedBand(
                            DialBarrel(dial: activeDial, rotation: .zero,
                                       onScrub: { scrub(activeDial.key, by: $0) })
                                .padding(.horizontal, 14),
                            thickness: 62, at: orientation.edge, in: geo.size,
                            inset: app.proMode ? DialStrip.height + 4 : 0
                        )
                    }
                }
                .transition(.opacity)
                .zIndex(4)
            }
        }
        // One spring for the whole turn. Portrait and landscape are different
        // view trees and SwiftUI cannot interpolate between two trees, so the
        // honest smooth answer is a cross-fade rather than a pretended morph —
        // and everything that does survive the change (the bands' angle and
        // centre) rides the same spring, so nothing arrives on its own beat.
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: orientation.edge)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: app.proMode)
        .animation(.easeOut(duration: 0.22), value: activeDial)
    }

    /// The edge that is physically up. `orientation.edge` is the one facing the
    /// ground, which is where the thumb falls and therefore where the barrel
    /// goes; the film strip takes the sky edge opposite it.
    private var skyEdge: DeviceOrientation.Edge {
        switch orientation.edge {
        case .leading:  return .trailing
        case .trailing: return .leading
        case .bottom:   return .bottom
        }
    }

    /// The picture itself: below the plate, above the release and the lens row.
    ///
    /// Landscape bands are laid out inside this rather than against the whole
    /// screen. Measured against the screen, a band is the full height — its top
    /// end reached up into the plate and its foot came down onto the shutter
    /// row, which is the overlap that was reported.
    private func viewfinderRegion(in size: CGSize) -> CGRect {
        let top = TopPlateBand.height
        // Lens row, the release, and the padding under it.
        let bottom: CGFloat = 170
        return CGRect(
            x: 0, y: top,
            width: size.width,
            height: max(140, size.height - top - bottom)
        )
    }

    /// Lays a band along the picture's long side, turns it to face the user, and
    /// parks it against one edge of the picture — never outside it. The frame
    /// stays constant through the rotation, which is what lets the move animate
    /// rather than snap.
    private func rotatedBand<C: View>(
        _ content: C, thickness: CGFloat,
        at edge: DeviceOrientation.Edge, in size: CGSize,
        inset: CGFloat = 0
    ) -> some View {
        let region = viewfinderRegion(in: size)
        let centre: CGPoint
        switch edge {
        case .leading:
            centre = CGPoint(x: region.minX + inset + thickness / 2 + 8, y: region.midY)
        case .trailing:
            centre = CGPoint(x: region.maxX - inset - thickness / 2 - 8, y: region.midY)
        case .bottom:
            centre = CGPoint(x: region.midX, y: region.maxY - inset - thickness / 2 - 8)
        }
        return content
            // Inset from the picture's ends too, so a band never runs edge to
            // edge across the frame it is sitting on.
            .frame(width: region.height - 28, height: thickness)
            .rotationEffect(orientation.angle)
            .position(centre)
    }

    /// Double tapping a dial puts that one control back to automatic, the way
    /// clicking a lens ring back to A does. Only the dial touched — a reset
    /// that quietly took the other four with it would be a trap.
    private func resetDial(_ key: ActiveDial.Key) {
        switch key {
        case .iso, .shutter:
            app.autoExposure = true
        case .white:
            app.whiteBalance = AppState.defaultControls.whiteBalance
        case .exposure:
            app.exposureComp = AppState.defaultControls.exposureComp
        case .aperture:
            app.apertureIndex = 2
        }
        activeDial = nil
    }

    /// Dragging the barrel drives the same value its dial does. The key is
    /// carried on the active dial so this does not have to guess which control
    /// is on screen.
    private func scrub(_ key: ActiveDial.Key, by delta: Double) {
        switch key {
        case .aperture:
            let last = AppState.apertureStops.count - 1
            let current = last > 0 ? Double(app.apertureIndex) / Double(last) : 0
            let next = KnobMath.clamp(current + delta)
            let index = min(last, max(0, Int((next * Double(last)).rounded())))
            if index != app.apertureIndex {
                app.apertureIndex = index
                Haptics.detent()
            }
        case .iso:
            // Same reason as the dial: a value the camera is not reading is not
            // a control.
            if app.autoExposure { app.autoExposure = false }
            step(\.iso, by: delta, stops: AppState.isoStops.count)
        case .shutter:
            if app.autoExposure { app.autoExposure = false }
            step(\.shutter, by: delta, stops: AppState.shutterStops.count)
        case .white:    step(\.whiteBalance, by: delta, stops: AppState.whiteBalanceStops.count)
        case .exposure: step(\.exposureComp, by: delta, stops: AppState.evDetents)
        }
        refreshBarrel(key)
    }

    /// Clicks only when the detent actually changes, so the barrel ticks in step
    /// with the number rather than on every pixel of travel.
    private func step(_ path: ReferenceWritableKeyPath<AppState, Double>, by delta: Double, stops: Int) {
        let before = KnobMath.detent(app[keyPath: path], stops: stops)
        app[keyPath: path] = KnobMath.clamp(app[keyPath: path] + delta)
        if KnobMath.detent(app[keyPath: path], stops: stops) != before { Haptics.detent() }
    }

    /// Keeps the reading under the index current while the barrel is dragged,
    /// and restarts the clock that retires it.
    private func refreshBarrel(_ key: ActiveDial.Key) {
        let reading: String
        let value: Double
        switch key {
        case .aperture:
            reading = AppState.apertureLabels[app.apertureIndex]
            let last = Double(AppState.apertureStops.count - 1)
            value = last > 0 ? Double(app.apertureIndex) / last : 0
        case .iso:      reading = app.isoLabel;     value = app.iso
        case .shutter:  reading = app.shutterLabel; value = app.shutter
        case .white:    reading = app.kelvinLabel;  value = app.whiteBalance
        case .exposure: reading = String(format: "%+.1f EV", app.evValue); value = app.exposureComp
        }
        showBarrel(ActiveDial(key: key, name: activeDial?.name ?? "", reading: reading, value: value))
    }

    /// Shows the barrel for the dial being turned, and starts the clock that
    /// retires it. Restarted on every change, so a long adjustment keeps it up
    /// and letting go puts it away.
    private func showBarrel(_ dial: ActiveDial) {
        activeDial = dial
        dialIdleTask?.cancel()
        dialIdleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            activeDial = nil
        }
    }

    private var classicChrome: some View {
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
    // Film Label expands to reveal the same family and stock rails. Reserve its
    // full height even while closed so the shutter never shifts or overlaps.
    private static let filmBand: CGFloat = 128
    private static let shutterBand: CGFloat = 80
    private static let bandInset: CGFloat = 12

    /// One view tree in every orientation.
    ///
    /// The first attempt branched on orientation and built two different trees.
    /// SwiftUI cannot interpolate between two trees, so it swapped them — which
    /// is exactly the jump that was reported. Here the blocks are laid out at a
    /// constant size and only their rotation and centre change, and both of those
    /// animate. Nothing resizes, so there is nothing left to snap.
    /// Which deck is on screen. All three keep the shutter row — the release,
    /// the roll, PRO and the lens selector are how the camera is operated at
    /// all, and a control style is a choice about the settings around them, not
    /// about whether the camera still works.
    @ViewBuilder private var deck: some View {
        switch controlStyle {
        case "Bellows Drawer": bellowsDeck
        case "Crown": crownDeck
        default: filmLabelDeck
        }
    }

    /// 11 · The selected stock rests as a tactile label below the shutter. The
    /// two-tier selector stays hidden until the label is tapped, so it never
    /// competes with the live photograph.
    private var filmLabelDeck: some View {
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

                band(
                    FilmLabelSelector(onOpenDetail: { app.go(.filmSim) }),
                    thickness: Self.filmBand,
                    centre: filmCentre(in: size),
                    length: size.width
                )

                shutterRow
                    .frame(width: size.width, height: Self.shutterBand)
                    .position(
                        x: size.width / 2,
                        y: size.height - Self.bandInset - Self.filmBand - Self.shutterBand / 2
                    )
            }
        }
    }

    /// 04 · A leatherette drawer under the shutter row, stowed to its pleats.
    private var bellowsDeck: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            shutterRow
                .frame(height: Self.shutterBand)
                .padding(.bottom, 10)

            BellowsDrawer(rotation: orientation.angle, open: $bellowsOpen)
        }
        .background(alignment: .bottom) {
            deckShade.frame(height: 240)
        }
    }

    /// 10 · One crown on the right edge. Nothing else is added to the frame,
    /// which is the entire argument for it.
    private var crownDeck: some View {
        VStack(spacing: 0) {
            CrownControl(rotation: orientation.angle)
                .frame(maxHeight: .infinity, alignment: .center)

            shutterRow
                .frame(height: Self.shutterBand)
                .padding(.bottom, 18)
        }
        .background(alignment: .bottom) {
            deckShade.frame(height: 190)
        }
    }

    private var classicDeck: some View {
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
                .font(.mono(14, .bold))
                .kerning(0.9)
                .foregroundStyle(app.proMode ? Ink.base : Tone.secondary)
                .rotationEffect(orientation.angle)
                .frame(width: 68, height: 46)
                .background {
                    if app.proMode {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Accent.amber)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.2)) }
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tone.hairline, lineWidth: 0.5) }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        if app.capture(rotationDegrees: orientation.angle.degrees) {
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

    /// Grid has no face of its own on the classic chrome — it lives in
    /// Settings. The plate's utility row gives it one, so it needs a cycler.
    private func cycleGrid() {
        Haptics.detent()
        let options = Pref.gridOptions
        let next = (options.firstIndex(of: gridStyle).map { $0 + 1 } ?? 0) % options.count
        withAnimation(.snappy(duration: 0.2)) { gridStyle = options[next] }
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

// MARK: - RAW capture progress

private struct RAWCaptureProgressOverlay: View {
    let design: String
    let progress: Double
    @State private var animated = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()

            VStack(spacing: 18) {
                animation
                    .frame(width: 174, height: 174)

                VStack(spacing: 6) {
                    Text(status)
                        .font(.mono(11, .bold))
                        .kerning(1.7)
                        .foregroundStyle(Tone.primary)
                    Text("ORIGINAL DNG · \(Int(progress * 100))%")
                        .font(.mono(9, .medium))
                        .kerning(1.1)
                        .foregroundStyle(Accent.amber)
                }

                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 190, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Accent.amber)
                            .frame(width: 190 * progress, height: 3)
                    }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .glass(radius: 24)
        }
        .onAppear { animated = true }
    }

    @ViewBuilder
    private var animation: some View {
        switch design.prefix(2) {
        case "01": apertureBloom
        case "02": filmAdvance
        case "03": amberScanline
        case "05": darkroomBath
        case "07": sensorMosaic
        default: quietProgress
        }
    }

    private var status: String {
        switch design.prefix(2) {
        case "01": return "CAPTURING SENSOR RAW"
        case "02": return "ADVANCING ORIGINAL FRAME"
        case "03": return "READING SENSOR DATA"
        case "05": return "DEVELOPING ORIGINAL DNG"
        case "07": return "BUILDING RAW PREVIEW"
        default: return "SAVING ORIGINAL DNG"
        }
    }

    private var apertureBloom: some View {
        ZStack {
            Circle().stroke(Tone.hairline, lineWidth: 2)
            Circle().trim(from: 0, to: 0.78)
                .stroke(Accent.amber, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(animated ? 360 : 0))
                .animation(.linear(duration: 1.45).repeatForever(autoreverses: false), value: animated)
            ForEach(0..<6, id: \.self) { index in
                Capsule().fill(Accent.amber.opacity(0.7))
                    .frame(width: 22, height: 68)
                    .offset(y: -38)
                    .rotationEffect(.degrees(Double(index) * 60 + (animated ? 28 : 0)))
            }
            Circle().fill(Ink.base).frame(width: 52, height: 52)
        }
    }

    private var filmAdvance: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.64))
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(index == 2 ? Accent.amber.opacity(0.7) : Color.white.opacity(0.18))
                        .frame(width: 48, height: 88)
                }
            }
            .offset(x: animated ? -28 : 28)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animated)
            VStack {
                HStack(spacing: 16) { ForEach(0..<9, id: \.self) { _ in Rectangle().fill(Accent.amber).frame(width: 8, height: 9) } }
                Spacer()
                HStack(spacing: 16) { ForEach(0..<9, id: \.self) { _ in Rectangle().fill(Accent.amber).frame(width: 8, height: 9) } }
            }
            .padding(.vertical, 10)
        }
    }

    private var amberScanline: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.09))
            CompositionGrid(style: "Rule of Thirds").clipShape(RoundedRectangle(cornerRadius: 14))
            Rectangle().fill(Accent.amber)
                .frame(height: 3)
                .shadow(color: Accent.amber, radius: 12)
                .offset(y: animated ? 68 : -68)
                .animation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true), value: animated)
        }
    }

    private var darkroomBath: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(RadialGradient(colors: [Color.red.opacity(0.55), Ink.base], center: .center, startRadius: 2, endRadius: 115))
            RoundedRectangle(cornerRadius: 12)
                .stroke(Accent.amber.opacity(animated ? 0.8 : 0.25), lineWidth: 2)
                .padding(22)
                .scaleEffect(animated ? 0.94 : 0.76)
                .opacity(animated ? 1 : 0.35)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animated)
        }
    }

    private var sensorMosaic: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 8)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<64, id: \.self) { index in
                Rectangle()
                    .fill([Color.red.opacity(0.68), Color.green.opacity(0.7), Color.blue.opacity(0.72), Accent.amber.opacity(0.75)][index % 4])
                    .aspectRatio(1, contentMode: .fit)
                    .opacity(animated ? 1 : 0.22)
                    .animation(.easeOut(duration: 0.38).delay(Double(index % 8) * 0.035), value: animated)
            }
        }
        .padding(8)
        .background(Ink.base, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Accent.amber.opacity(0.45), lineWidth: 1) }
    }

    private var quietProgress: some View {
        ZStack {
            Circle().stroke(Tone.hairline, lineWidth: 5)
            Circle().trim(from: 0, to: progress)
                .stroke(Accent.amber, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().fill(Accent.amber.opacity(animated ? 0.95 : 0.38)).frame(width: 22, height: 22)
                .shadow(color: Accent.amber, radius: animated ? 14 : 3)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animated)
        }
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
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Tone.hairline, lineWidth: 0.5) }
        }
    }
}

// MARK: - Manual controls sheet

struct ManualControlsSheet: View {
    @EnvironmentObject var app: AppState

    @AppStorage(Pref.captureFormat) private var captureFormat = "RAW + JPEG"
    @AppStorage(Pref.rawCaptureSource) private var rawCaptureSource = "Sensor RAW"
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

            ChipRow(
                label: "RAW Capture",
                options: Pref.captureFormatOptions,
                selection: $captureFormat,
                disabledOptions: app.usingFrontCamera ? ["RAW Only", "RAW + JPEG"] : []
            )
            if app.usingFrontCamera {
                Text("Selfie camera captures maximum-quality JPEG. Sensor RAW and Apple ProRAW require a rear camera.")
                    .font(.ui(11))
                    .foregroundStyle(Tone.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            } else if captureFormat != "JPEG Only" {
                ChipRow(label: "RAW Source", options: Pref.rawCaptureSourceOptions, selection: $rawCaptureSource)
                Text(rawCaptureSource == "Sensor RAW"
                     ? "Sensor RAW saves a standard Bayer DNG without the Apple ProRAW capture path."
                     : "Apple ProRAW uses Apple's computational RAW capture path.")
                    .font(.ui(11))
                    .foregroundStyle(Tone.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
            ChipRow(label: "Resolution", options: Pref.captureResolutionOptions, selection: $captureResolution)

            if captureFormat != "JPEG Only" && !supportsSelectedRAWSource {
                Text("This camera or lens cannot use \(rawCaptureSource). Select a RAW-capable camera or source; Latitude will not substitute HEIF.")
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

    private var supportsSelectedRAWSource: Bool {
        !app.usingFrontCamera && (rawCaptureSource == "Apple ProRAW"
            ? app.cameraManager.supportsAppleProRAW
            : app.cameraManager.supportsSensorRAW)
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
