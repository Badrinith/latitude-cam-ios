//
//  Barrel.swift
//  LatitudeCam
//
//  A knurled barrel laid flat: engraved values roll horizontally under a fixed
//  index, the way a command dial on a top plate does when you look down at it.
//
//  Chosen over the rotary dial it replaces for one reason above the others — its
//  shape states the gesture. A milled cylinder asks to be pushed sideways, and
//  sideways is the gesture. The dial it replaces failed silently, and nothing
//  about a circle tells you which way it was supposed to turn.
//

import SwiftUI
import UIKit
import CoreMotion

// MARK: - Orientation
//
// The app is locked to portrait, as a camera should be — the picture must not
// reflow because the body turned. But once the body is sideways every readout is
// sideways too, so the glyphs counter-rotate in place. This is what a camera does
// with the icons in its finder, and it is the whole of "landscape support" for a
// screen that is otherwise a live image.

final class DeviceOrientation: ObservableObject {

    /// The screen edge currently facing the ground. Controls belong along it.
    enum Edge { case bottom, leading, trailing }

    @Published private(set) var angle: Angle = .zero
    @Published private(set) var edge: Edge = .bottom

    private let motion = CMMotionManager()
    private var token: NSObjectProtocol?

    /// How far past level the phone has to be tilted before the answer changes.
    /// Below this the reading is ambiguous and the last good answer stands, so
    /// the controls do not flick about while the phone is being picked up.
    private static let commitment = 0.62
    /// How much of gravity has to lie in the screen's plane before there is any
    /// left or right to read. Below this the phone is flat on its back or face
    /// and the last good answer stands.
    ///
    /// Deliberately small: a phone aimed down at a table still has a clear
    /// which-way-up, and the old test threw that away along with the genuinely
    /// flat case.
    private static let level = 0.18

    init() {
        // A forced orientation for screenshots. The app is portrait-locked and
        // this Xcode ships no Simulator.app, so without this the turned layout
        // can only be seen on a physical phone — which is why so much of it was
        // fixed blind. LAT_ORIENTATION=left|right pins the reading and skips
        // the sensor entirely.
        if let forced = ProcessInfo.processInfo.environment["LAT_ORIENTATION"] {
            switch forced {
            case "left":  angle = .degrees(90);  edge = .leading
            case "right": angle = .degrees(-90); edge = .trailing
            default:      angle = .zero;         edge = .bottom
            }
            return
        }

        // Read from gravity rather than from UIDevice.
        //
        // UIDevice.orientation is the interface's idea of which way is up, and
        // it is entangled with what the app declares it supports and with the
        // rotation lock in Control Centre — which is exactly the coupling this
        // is meant not to have. Gravity is not a setting: it says which way the
        // phone is being held whatever the phone has been told to do about it.
        // Device motion's gravity vector is filtered, so a hand moving while
        // framing does not briefly make the labels snap back to portrait.
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.2
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let self, let gravity = data?.gravity else { return }
                self.apply(x: gravity.x, y: gravity.y, z: gravity.z)
            }
        } else if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 0.2
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let a = data?.acceleration else { return }
                self.apply(x: a.x, y: a.y, z: a.z)
            }
        } else {
            // Simulators and any device without an accelerometer. Keeps the old
            // behaviour rather than leaving orientation stuck in portrait.
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            token = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in self?.updateFromDevice() }
            updateFromDevice()
        }
    }

    deinit {
        motion.stopDeviceMotionUpdates()
        motion.stopAccelerometerUpdates()
        if let token {
            NotificationCenter.default.removeObserver(token)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    /// Which way the phone is being held, from the direction gravity pulls.
    ///
    /// Pure and static so the axis signs — the part that is easy to get
    /// backwards and impossible to see in code — can be tested rather than
    /// discovered by turning a phone over and squinting at it.
    static func reading(x: Double, y: Double, z: Double) -> (angle: Angle, edge: Edge)? {
        // Only the part of gravity lying in the screen's plane says anything
        // about which way up the phone is. Judge it on its own terms rather
        // than against the whole vector.
        //
        // This used to test |x| and |y| against an absolute threshold, which
        // quietly meant "and the phone must also be roughly upright". Point the
        // camera down at a table — the commonest thing anyone does with a
        // camera app — and most of gravity goes into z, both horizontal terms
        // fall under the threshold, and the reading freezes at whatever it last
        // saw. The controls then stayed rotated 90° while the phone was plainly
        // upright, which is what it looked like on the glass.
        let horizontal = (x * x + y * y).squareRoot()

        // Genuinely flat, screen up or down: there is no left or right, and
        // holding the last answer is the right thing to do.
        guard horizontal > level else { return nil }

        // Direction within the screen's plane, independent of how far the phone
        // is tilted toward or away from you.
        let nx = x / horizontal
        let ny = y / horizontal

        if abs(nx) > abs(ny) {
            guard abs(nx) > commitment else { return nil }
            // Turned anticlockwise the phone's left edge swings down, so the
            // controls go there and the block turns +90 to face the user.
            return nx < 0 ? (.degrees(90), .leading) : (.degrees(-90), .trailing)
        } else {
            guard abs(ny) > commitment else { return nil }
            // Upside down keeps the last good answer rather than turning the
            // whole camera over for a grip nobody shoots with.
            return ny < 0 ? (.zero, .bottom) : nil
        }
    }

    private func apply(x: Double, y: Double, z: Double) {
        guard let next = Self.reading(x: x, y: y, z: z) else { return }
        commit(next)
    }

    private func updateFromDevice() {
        let next: (angle: Angle, edge: Edge)
        switch UIDevice.current.orientation {
        case .landscapeLeft:  next = (.degrees(90), .leading)
        case .landscapeRight: next = (.degrees(-90), .trailing)
        case .portrait:       next = (.zero, .bottom)
        default:              return
        }
        commit(next)
    }

    private func commit(_ next: (angle: Angle, edge: Edge)) {
        guard next.angle != angle else { return }
        withAnimation(.spring(response: 0.44, dampingFraction: 0.8)) {
            angle = next.angle
            edge = next.edge
        }
    }
}

// MARK: - The barrel

struct Barrel: View {
    /// Engraved values in order. Index 0 is the A position when `hasAuto`.
    var values: [String]
    @Binding var index: Int
    var hasAuto = false
    var height: CGFloat = 52
    /// Distance between engraved values on the surface.
    var pitch: CGFloat = 74
    /// Drag travel needed to advance one stop. Independent of `pitch` so the
    /// engraving can be spaced for legibility and the turn tuned for feel.
    var pointsPerStop: CGFloat = 52
    var radius: CGFloat = 10
    /// One colour per value, when the values name something that has a colour.
    /// The film barrel uses the stock swatches so the engraving shows what the
    /// frame will look like, not just what it is called.
    var tints: [Color]?
    /// Values that are shown for context but cannot be selected in the current
    /// capture mode, such as focal lengths without Sensor RAW support.
    var disabledIndices: Set<Int> = []
    /// Set when the barrel sits inside a scroll view.
    ///
    /// A barrel claims any drag that starts on it, vertical ones included — and
    /// in a stack of barrels almost every drag starts on one, so the scroll never
    /// received a gesture and the panel would not move. This makes the barrel wait
    /// a little longer before claiming, and ignore a drag that is mostly vertical,
    /// which is the scroll's to have.
    var insideScrollView = false

    @State private var dragStart: Int?
    @State private var lastEndTick = Date.distantPast

    private var clamped: Int { min(max(index, 0), max(0, values.count - 1)) }
    private var isAuto: Bool { hasAuto && clamped == 0 }

    var body: some View {
        ZStack {
            surface
            engravings
            edgeFalloff
            notch
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .gesture(turn)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(values.indices.contains(clamped) ? values[clamped] : "")
        .accessibilityAdjustableAction { direction in
            select(clamped + (direction == .increment ? 1 : -1))
        }
    }

    // MARK: Surface

    /// Milled metal: a vertical light band across the middle, and fine flutes
    /// along it. The flutes are what make it read as something you grip.
    private var surface: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x101011), Color(hex: 0x3D3D41),
                    Color(hex: 0x2A2A2D), Color(hex: 0x101011)
                ],
                startPoint: .top, endPoint: .bottom
            )

            Canvas { context, size in
                var x: CGFloat = 0
                while x < size.width {
                    var flute = Path()
                    flute.move(to: CGPoint(x: x, y: 0))
                    flute.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(flute, with: .color(.black.opacity(0.42)), lineWidth: 1)
                    x += 4
                }
            }
        }
    }

    /// Curvature is faked by darkening both ends. Without it the strip reads flat
    /// and the values look like a list rather than something wrapping away.
    private var edgeFalloff: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.85), location: 0),
                .init(color: .clear, location: 0.22),
                .init(color: .clear, location: 0.78),
                .init(color: .black.opacity(0.85), location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .allowsHitTesting(false)
    }

    private var engravings: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(values.indices, id: \.self) { slot in
                    ZStack {
                        // The stock's own colour, painted across its whole segment
                        // rather than only its letters: the barrel reads as a strip
                        // of the film itself passing under the index.
                        if let tints, tints.indices.contains(slot) {
                            LinearGradient(
                                colors: [
                                    tints[slot].opacity(slot == clamped ? 1.0 : 0.42),
                                    tints[slot].opacity(slot == clamped ? 0.72 : 0.28)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                            .padding(.vertical, slot == clamped ? 0 : 7)
                        }

                        Text(values[slot])
                            .font(.mono(slot == clamped ? 15 : 12, slot == clamped ? .bold : .medium))
                            .foregroundStyle(engravingColour(slot))
                            .shadow(color: .black.opacity(tints == nil ? 0.6 : 0.25), radius: 1, y: 0.5)
                    }
                    .frame(width: pitch)
                }
            }
            .frame(width: pitch * CGFloat(values.count), height: geo.size.height)
            // Bring the live value to the centre of the strip.
            .offset(x: geo.size.width / 2 - (CGFloat(clamped) + 0.5) * pitch)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: clamped)
        }
        .allowsHitTesting(false)
    }

    private func engravingColour(_ slot: Int) -> Color {
        if disabledIndices.contains(slot) {
            return Color(hex: 0xC9C2B6).opacity(0.2)
        }
        // On a colour band the lettering has to go dark to survive; the band is
        // carrying the information now, so the type only has to be readable.
        if let tints, tints.indices.contains(slot) {
            return slot == clamped ? Ink.base : Ink.base.opacity(0.55)
        }
        if slot == clamped { return isAuto ? Accent.amber : Tone.primary }
        if hasAuto && slot == 0 { return Tone.secondary }
        return Color(hex: 0xC9C2B6).opacity(0.5)
    }

    /// The index. Two hairlines rather than a pointer, so the value sits *in* the
    /// mark instead of under it — a window, the way a frame counter reads.
    private var notch: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Accent.amber.opacity(0.85)).frame(width: 0.75)
            Color.clear.frame(width: pitch * 0.62)
            Rectangle().fill(Accent.amber.opacity(0.85)).frame(width: 0.75)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    // MARK: Turning

    /// Whether a drag of this shape is the barrel's to act on. Pulled out so the
    /// rule can be tested — the failure it guards against is a panel that simply
    /// will not scroll, which looks like a broken ScrollView rather than a
    /// gesture that was taken.
    static func claimsDrag(width: CGFloat, height: CGFloat, insideScrollView: Bool) -> Bool {
        guard insideScrollView else { return true }
        return abs(width) > abs(height)
    }

    private var turn: some Gesture {
        DragGesture(minimumDistance: insideScrollView ? 10 : 1)
            .onChanged { value in
                // Let the scroll have anything that is more down than sideways.
                guard Self.claimsDrag(
                    width: value.translation.width,
                    height: value.translation.height,
                    insideScrollView: insideScrollView
                ) else { return }
                if dragStart == nil {
                    dragStart = clamped
                    Haptics.prepare()
                }
                let from = dragStart ?? clamped
                // Drag left to advance, matching the direction the engraving moves.
                let raw = CGFloat(from) - value.translation.width / pointsPerStop
                let target = min(max(Int(raw.rounded()), 0), values.count - 1)

                if target != clamped {
                    Haptics.detent()
                    index = target
                } else if Int(raw.rounded()) != target {
                    reportEndOfTravel()
                }
            }
            .onEnded { _ in dragStart = nil }
    }

    /// A soft double tick at either end, so the limit is felt rather than guessed at.
    private func reportEndOfTravel() {
        guard Date().timeIntervalSince(lastEndTick) > 0.6 else { return }
        lastEndTick = Date()
        Haptics.tap()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            Haptics.tap()
        }
    }

    private func select(_ slot: Int) {
        let target = min(max(slot, 0), values.count - 1)
        guard target != clamped else {
            reportEndOfTravel()
            return
        }
        Haptics.detent()
        index = target
    }
}

// MARK: - Film selector
//
// Two tiers, because eleven names will not fit one roll. VERMILION needs more
// width than a segment of an eleven-stop barrel can give it, and no tracking
// fixes that — so the family narrows the field first and the stock barrel only
// ever holds the two or three names in it.
//
// It also scales. A twelfth stock joins a family; it does not lengthen the roll.

struct FilmTwoTier: View {
    @EnvironmentObject var app: AppState
    var onOpenDetail: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            // Upper tier: the shelf.
            Barrel(
                values: AppState.filmFamilies.map { $0.uppercased() },
                index: Binding(get: { app.familyIndex }, set: { app.familyIndex = $0 }),
                height: 26,
                pitch: 108,
                pointsPerStop: 52,
                radius: 6
            )
            .opacity(0.82)

            // Lower tier: what is on it. Tinted with each stock's own colour, so
            // the barrel shows what the frame will look like and not only what it
            // is called.
            Barrel(
                values: stocks.map { $0.name.uppercased() },
                index: Binding(get: { app.stockIndex }, set: { app.stockIndex = $0 }),
                height: 42,
                pitch: 104,
                pointsPerStop: 50,
                radius: 9,
                tints: stocks.map(\.engraved)
            )
            .overlay(alignment: .top) {
                Triangle()
                    .fill(Accent.amber)
                    .frame(width: 8, height: 5)
                    .offset(y: -3)
            }

            Text(app.selectedFilm.blurb.uppercased())
                .font(.mono(7, .medium))
                .kerning(0.9)
                .foregroundStyle(Tone.quaternary)
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.tap()
                    onOpenDetail()
                }
        }
        .padding(.horizontal, 18)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: app.selectedFilm.family)
    }

    private var stocks: [FilmPreset] { AppState.stocks(in: app.selectedFilm.family) }
}

// MARK: - Film label
//
// The quiet state is a paper stock label, not another always-open control. It
// keeps the viewfinder clear while still making the selected simulation legible
// at a glance. Opening the label retains the same two-stage family -> stock
// selection model as FilmTwoTier, so this is a presentation change, not a
// second film-selection system.

struct FilmLabelSelector: View {
    @EnvironmentObject var app: AppState
    var onOpenDetail: () -> Void

    @State private var isOpen = false

    var body: some View {
        VStack(spacing: isOpen ? 7 : 0) {
            Button {
                Haptics.toggle()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.selectedFilm.name.uppercased())
                            .font(.mono(11, .bold))
                            .kerning(1.1)
                            .foregroundStyle(Ink.base)
                        Text(app.selectedFilm.blurb.uppercased())
                            .font(.mono(6.5, .medium))
                            .kerning(0.7)
                            .foregroundStyle(Ink.base.opacity(0.72))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isOpen ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Ink.base.opacity(0.75))
                }
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(app.selectedFilm.engraved)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Accent.amber.opacity(0.76), lineWidth: 0.8)
                        }
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Film simulation")
            .accessibilityValue(app.selectedFilm.name)

            if isOpen {
                VStack(spacing: 5) {
                    Barrel(
                        values: AppState.filmFamilies.map { $0.uppercased() },
                        index: Binding(
                            get: { app.familyIndex },
                            set: { app.familyIndex = $0 }
                        ),
                        height: 24,
                        pitch: 100,
                        pointsPerStop: 50,
                        radius: 6
                    )

                    Barrel(
                        values: stocks.map { $0.name.uppercased() },
                        index: Binding(
                            get: { app.stockIndex },
                            set: { app.stockIndex = $0 }
                        ),
                        height: 34,
                        pitch: 98,
                        pointsPerStop: 48,
                        radius: 8,
                        tints: stocks.map(\.engraved)
                    )

                    Button {
                        Haptics.tap()
                        onOpenDetail()
                    } label: {
                        Text("OPEN FILM LIBRARY")
                            .font(.mono(7, .semibold))
                            .kerning(1.1)
                            .foregroundStyle(Tone.quaternary)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: app.selectedFilm.family)
    }

    private var stocks: [FilmPreset] { AppState.stocks(in: app.selectedFilm.family) }
}

// MARK: - Pro cluster
//
// Collapsed to chips above the shutter; one tap inflates the chosen control into
// a barrel at thumb height. Nothing ever occupies the middle of the frame.

struct BarrelCluster: View {

    /// The tallest the cluster gets: one open barrel with its label, above two
    /// rows of chips, plus the spacing between them.
    ///
    /// The viewfinder sizes its band from this rather than from a number typed
    /// beside it. When the two disagreed the open cluster was drawn — and touched
    /// — over the shutter row below, so controls down there stopped responding
    /// while nothing looked wrong: a SwiftUI frame does not clip what overflows it.
    static let expandedHeight: CGFloat = 196

    @EnvironmentObject var app: AppState
    @AppStorage(Pref.captureFormat) private var captureFormat = "RAW + JPEG"
    @AppStorage(Pref.rawCaptureSource) private var rawCaptureSource = "Sensor RAW"

    /// nil while collapsed.
    @State private var focus: String?
    @State private var idle: Task<Void, Never>?

    private struct Control: Identifiable {
        let id: String
        let label: String
        let chip: String
    }

    /// Two rows of three. Six on one row shrank the type past reading, and a
    /// scroller hides controls behind a gesture you have to discover.
    private var rows: [[Control]] {
        [
            [
                .init(id: "shutter", label: "SHUTTER", chip: app.shutterLabel),
                .init(id: "iso", label: "ISO", chip: app.isoLabel),
                .init(id: "wb", label: "WHITE BALANCE", chip: app.kelvinLabel)
            ],
            portraitRow
        ]
    }

    /// Aperture only appears while portrait is on, because that is the only time
    /// it does anything. A control that is present but inert teaches the wrong
    /// thing about every other control beside it.
    private var portraitRow: [Control] {
        [
            .init(id: "ev", label: "EXPOSURE", chip: app.exposureLabel),
            .init(id: "focus", label: "FOCUS", chip: app.focusLabel),
            .init(id: "raw", label: "RAW CAPTURE", chip: rawChipLabel)
        ]
    }

    private var rawChipLabel: String {
        switch captureFormat {
        case "RAW Only": return "RAW"
        case "RAW + JPEG": return "RAW+"
        default: return "JPEG"
        }
    }

    private var controls: [Control] { rows.flatMap { $0 } }

    var body: some View {
        VStack(spacing: 8) {
            if let focus, let control = controls.first(where: { $0.id == focus }) {
                expanded(control)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            chips
        }
        .padding(.horizontal, 18)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: focus)
        // A capture closes the cluster: the shot is taken, the adjustment is done.
        .onChange(of: app.captureTick) { _, _ in collapse() }
        .onDisappear { idle?.cancel() }
    }

    // MARK: Expanded

    @ViewBuilder
    private func expanded(_ control: Control) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(control.label)
                    .font(.mono(7.5, .semibold))
                    .kerning(1.6)
                    .foregroundStyle(Tone.quaternary)
                Spacer()
                Text(control.chip)
                    .font(.mono(11, .bold))
                    .foregroundStyle(Accent.amber)
            }
            .padding(.horizontal, 2)

            if control.id == "raw" {
                rawCapturePicker
                    .overlay(alignment: .top) {
                        Triangle()
                            .fill(Accent.amber)
                            .frame(width: 9, height: 6)
                            .offset(y: -4)
                    }
            } else {
                barrel(for: control.id)
                    .overlay(alignment: .top) {
                        Triangle()
                            .fill(Accent.amber)
                            .frame(width: 9, height: 6)
                            .offset(y: -4)
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { restartIdle() }
    }

    @ViewBuilder
    private func barrel(for id: String) -> some View {
        switch id {
        case "shutter":
            Barrel(
                values: AppState.shutterLabels,
                index: binding(get: { app.shutterIndex }, set: { app.shutterIndex = $0 }),
                hasAuto: true
            )
        case "iso":
            Barrel(
                values: AppState.isoLabels,
                index: binding(get: { app.isoIndex }, set: { app.isoIndex = $0 }),
                hasAuto: true
            )
        case "wb":
            Barrel(
                values: AppState.whiteBalanceLabels,
                index: binding(get: { app.whiteBalanceIndex }, set: { app.whiteBalanceIndex = $0 })
            )
        case "focus":
            Barrel(
                values: AppState.focusLabels,
                index: binding(get: { app.focusIndex }, set: { app.focusIndex = $0 }),
                hasAuto: true
            )
        case "aperture":
            Barrel(
                values: AppState.apertureLabels,
                index: binding(get: { app.apertureIndex }, set: { app.apertureIndex = $0 })
            )
        case "metering":
            Barrel(
                values: AppState.meteringModes,
                index: binding(get: { app.meteringIndex }, set: { app.meteringIndex = $0 })
            )
        default:
            Barrel(
                values: AppState.exposureLabels,
                index: binding(get: { app.exposureIndex }, set: { app.exposureIndex = $0 })
            )
        }
    }

    private var rawCapturePicker: some View {
        VStack(spacing: 4) {
            ChipRow(
                label: "Capture",
                options: Pref.captureFormatOptions,
                selection: $captureFormat,
                disabledOptions: app.usingFrontCamera ? ["RAW Only", "RAW + JPEG"] : []
            )
            if app.usingFrontCamera {
                Text("Selfie camera: JPEG only")
                    .font(.mono(9, .semibold))
                    .foregroundStyle(Tone.quaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if captureFormat != "JPEG Only" {
                ChipRow(label: "Source", options: Pref.rawCaptureSourceOptions, selection: $rawCaptureSource)
            }
        }
        .padding(.top, 1)
    }

    /// Every turn restarts the idle timer, so a control cannot close under the thumb.
    private func binding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Int> {
        Binding(get: get, set: { value in
            set(value)
            restartIdle()
        })
    }

    // MARK: Collapsed

    private var chips: some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 6) {
                    chipRow(row)
                    if index == 1 {
                        peakingChip
                        resetChip
                    }
                }
            }
        }
    }

    /// A toggle, not a scale — it opens nothing, so it reads as a switch rather
    /// than as a sixth thing to turn.
    private var peakingChip: some View {
        Button {
            Haptics.toggle()
            app.focusPeaking.toggle()
        } label: {
            Image(systemName: "camera.filters")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(app.focusPeaking ? Ink.base : Tone.secondary)
                .frame(width: 34)
                .padding(.vertical, 6)
                .background {
                    if app.focusPeaking {
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
        .accessibilityLabel("Focus peaking")
    }

    /// Puts every manual control back where it shipped. Recoverable: the previous
    /// state goes on the undo stack, so a mistaken tap costs one more tap rather
    /// than the setup you had built.
    private var resetChip: some View {
        Button {
            app.resetControls()
            // Whatever was open is showing a value that just changed underneath it.
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                focus = nil
                app.proFocus = nil
            }
            idle?.cancel()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tone.secondary)
                .frame(width: 34)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay { Capsule().fill(Color.black.opacity(0.2)) }
                        .overlay { Capsule().strokeBorder(Tone.hairline, lineWidth: 0.5) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset manual controls")
    }

    private func chipRow(_ row: [Control]) -> some View {
        HStack(spacing: 6) {
            ForEach(row) { control in
                Button { open(control.id) } label: {
                    Text(control.chip)
                        .font(.mono(10, .medium))
                        .foregroundStyle(focus == control.id ? Ink.base : Tone.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                            .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background {
                            if focus == control.id {
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
            }
        }
    }

    // MARK: Focus

    private func open(_ id: String) {
        Haptics.tap()
        // Tapping the live control closes it — the chip is a toggle, not a mode.
        focus = (focus == id) ? nil : id
        app.proFocus = focus
        focus == nil ? idle?.cancel() : restartIdle()
    }

    private func collapse() {
        idle?.cancel()
        guard focus != nil else { return }
        focus = nil
        app.proFocus = nil
    }

    /// Closes itself after four seconds, the way a meter times out. A control you
    /// have to remember to dismiss is a mode, and modes are what this replaces.
    private func restartIdle() {
        idle?.cancel()
        idle = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                focus = nil
                app.proFocus = nil
            }
        }
    }
}

// MARK: - Lens selector
//
// The same barrel as every other control, because it is the same kind of choice:
// an ordered ladder you step along. A row of buttons made it the one control on
// screen that worked differently from its neighbours.
//
// Observes the camera directly — the ladder is a property of the hardware, and a
// body with no ultra-wide must not be offered 0.5×.

struct LensBarrel: View {
    @ObservedObject var camera: CameraManager
    var selected: String
    var onSelect: (CameraManager.Lens) -> Void

    @AppStorage(Pref.captureFormat) private var captureFormat = "RAW + JPEG"
    @AppStorage(Pref.rawCaptureSource) private var rawCaptureSource = "Sensor RAW"

    private var unavailableLensIDs: Set<String> {
        guard captureFormat != "JPEG Only", rawCaptureSource == "Sensor RAW" else {
            return []
        }
        // The device's Bayer DNG path accepts only the primary wide sensor at
        // its native field. A 2x video crop makes AVFoundation reject the RAW
        // shutter request, so it is intentionally unavailable here.
        return Set(camera.lenses.map(\.id).filter { $0 != "wide" })
    }

    var body: some View {
        // One lens is not a choice, so it does not get a control.
        if camera.lenses.count > 1 {
            Barrel(
                values: camera.lenses.map(\.label),
                index: Binding(
                    get: { camera.lenses.firstIndex { $0.id == selected } ?? 0 },
                    set: { index in
                        let clamped = min(max(index, 0), camera.lenses.count - 1)
                        onSelect(camera.lenses[clamped])
                    }
                ),
                height: 38,
                pitch: 46,
                pointsPerStop: 44,
                radius: 8,
                disabledIndices: Set(camera.lenses.indices.filter {
                    unavailableLensIDs.contains(camera.lenses[$0].id)
                })
            )
            .frame(width: 106)
            .overlay(alignment: .top) {
                Triangle()
                    .fill(Accent.amber)
                    .frame(width: 7, height: 4.5)
                    .offset(y: -3)
            }
            .accessibilityLabel("Lens")
        }
    }
}

// MARK: - Edit barrel
//
// The editor's control, and deliberately the camera's control at a smaller size.
// Every other direction considered introduced a widget the app does not otherwise
// have; an editor should not have to be learned separately from the camera it
// belongs to, so this is the same drag, the same detent and the same haptic as
// the shutter and film barrels.
//
// Barrels engrave values, not names, which is the honest weakness of the choice —
// so the label sits above each one and the group heading carries the rest.

struct EditBarrel: View {
    var label: String
    /// 0…1, matching the editor's storage. The barrel works in stops, so the two
    /// are converted at the boundary rather than the editor changing shape.
    @Binding var position: Double
    var stops: Int = 21
    /// Turns a 0…1 position into what is engraved on the barrel.
    var format: (Double) -> String

    private var index: Binding<Int> {
        Binding(
            get: { min(stops - 1, max(0, Int((position * Double(stops)).rounded(.down)))) },
            set: { position = (Double(min(max($0, 0), stops - 1)) + 0.5) / Double(stops) }
        )
    }

    private var engraved: [String] {
        (0..<stops).map { format((Double($0) + 0.5) / Double(stops)) }
    }

    /// A control at its centre stop is doing nothing, and should look like it.
    private var isNeutral: Bool { abs(position - 0.5) < (0.5 / Double(stops)) }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.mono(8, .semibold))
                    .kerning(0.9)
                    .foregroundStyle(isNeutral ? Tone.quaternary : Accent.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }

            Barrel(
                values: engraved,
                index: index,
                height: 40,
                // Wider now the barrel spans the screen: at 52 the values crowded
                // each other, and the whole point of the extra width is being able
                // to read the stops either side of the one you are on.
                pitch: 78,
                pointsPerStop: 40,
                radius: 8,
                insideScrollView: true
            )
            .overlay(alignment: .top) {
                Triangle()
                    .fill(isNeutral ? Tone.quaternary : Accent.amber)
                    .frame(width: 7, height: 4.5)
                    .offset(y: -3)
            }
        }
    }
}
