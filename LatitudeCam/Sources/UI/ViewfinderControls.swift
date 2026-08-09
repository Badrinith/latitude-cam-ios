//
//  ViewfinderControls.swift
//  LatitudeCam
//
//  Two alternative control decks for the viewfinder, selectable in Settings
//  beside the classic barrels.
//
//  Both start from the same idea: a camera should show you the picture and
//  nothing else until you ask, and what comes back should be something with
//  knurling on it that you turn — not a slider, and not a row of taps.
//
//  · Bellows Drawer — a leatherette drawer with three knobs, stowed to its
//    pleats until pulled up.
//  · Crown — one knurled crown on the right edge. Press it to choose what it
//    drives, roll it to set the value.
//
//  The release is in neither of them. It lives in the shutter row and does not
//  move: a shutter you have to hunt for is worse than one held at an odd angle,
//  and that holds however the controls beside it are arranged.
//

import SwiftUI

// MARK: - Knob geometry

/// The arithmetic behind a rotary knob, kept apart from the view so the parts
/// that are easy to get backwards can be tested rather than eyeballed on a
/// device. A knob that runs the wrong way, or that jumps when the drag crosses
/// the twelve o'clock seam, is invisible in code and obvious in the hand.
enum KnobMath {

    /// Degrees of travel between the low and high stop. Less than a full turn,
    /// so the pointer never wraps onto itself and there is always a visible
    /// "this is as far as it goes".
    static let sweep: Double = 280

    /// The pointer angle for a 0…1 value, centred on straight up.
    static func pointerAngle(for value: Double) -> Double {
        -sweep / 2 + clamp(value) * sweep
    }

    /// Shortest signed distance between two absolute angles, in degrees.
    ///
    /// Without the wrap a drag passing through the seam at ±180° reads as a
    /// jump of most of a circle, and the value slams from one end of its range
    /// to the other in a single frame.
    static func angleDelta(from previous: Double, to current: Double) -> Double {
        var delta = current - previous
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    /// Turns the knob by an angular delta, clamped to its ends.
    static func advance(_ value: Double, byDegrees degrees: Double) -> Double {
        clamp(value + degrees / sweep)
    }

    /// Which detent a value falls in, for the click and its haptic. Matches the
    /// ladder indexing AppState.stop uses, so a click always coincides with the
    /// displayed value actually changing — a knob that clicks without moving
    /// reads as broken.
    static func detent(_ value: Double, stops: Int) -> Int {
        guard stops > 1 else { return 0 }
        return min(stops - 1, max(0, Int(clamp(value) * Double(stops))))
    }

    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

// MARK: - Which way is along

/// Projects a drag onto a control that has been turned with the body.
///
/// The app is portrait-locked, so a strip lying across the screen in portrait
/// is lying *up and down* it once the phone is sideways — and the finger that
/// moves along it moves vertically, not horizontally. Reading
/// `translation.width` regardless is why the film strip and the focal length
/// could not be scrubbed when the body was turned: the gesture was measuring
/// the axis the control no longer lay on.
///
/// Sign matters as much as axis. A +90 turn maps the control's own forward
/// direction onto screen-down; a -90 turn maps it onto screen-up. Getting that
/// backwards runs every scale the wrong way.
enum DragAxis {

    /// Movement along the control, in its own direction of travel.
    static func along(_ translation: CGSize, rotation: Angle) -> CGFloat {
        switch Int(rotation.degrees.rounded()) {
        case 90:   return translation.height
        case -90:  return -translation.height
        case 180, -180: return -translation.width
        default:   return translation.width
        }
    }

    /// Movement across it — the axis a dismissal uses, so the two never
    /// compete for the same movement.
    static func across(_ translation: CGSize, rotation: Angle) -> CGFloat {
        switch Int(rotation.degrees.rounded()) {
        case 90:   return -translation.width
        case -90:  return translation.width
        case 180, -180: return -translation.height
        default:   return translation.height
        }
    }
}

// MARK: - The knob

/// A knurled rotary knob over a 0…1 binding.
///
/// Turned by dragging around it rather than up and down: the whole point of a
/// knob is that the gesture matches the object, and a vertical drag on a round
/// control is just a slider wearing a costume.
struct Knob: View {
    var label: String
    var reading: String
    @Binding var value: Double
    /// Detent count, only for the click — the value itself stays continuous.
    var stops: Int = 24
    var diameter: CGFloat = 62
    var rotation: Angle = .zero

    @State private var lastAngle: Double?
    @State private var lastDetent: Int?

    var body: some View {
        VStack(spacing: 8) {
            knob
            VStack(spacing: 2) {
                Text(label)
                    .font(.mono(7.5, .semibold))
                    .kerning(1.4)
                    .foregroundStyle(Tone.quaternary)
                Text(reading)
                    .font(.mono(10, .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Tone.primary)
            }
            .rotationEffect(rotation)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(reading)
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / Double(stops)
            value = KnobMath.clamp(value + (direction == .increment ? step : -step))
            Haptics.detent()
        }
    }

    private var knob: some View {
        ZStack {
            // Knurling. Drawn as spokes rather than an image so it stays crisp
            // at any size and costs nothing to ship.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x3A3A3A), Color(hex: 0x121212)],
                        center: .init(x: 0.34, y: 0.28),
                        startRadius: 1, endRadius: diameter * 0.78
                    )
                )
                .overlay { knurling }
                .overlay {
                    Circle().strokeBorder(Tone.hairline, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.62), radius: 7, y: 4)

            // Brass cap. The one warm thing on the control, and what makes it
            // read as machined rather than drawn.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xB08D5B), Color(hex: 0x6D5533)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(Color.white.opacity(0.28))
                        .blur(radius: 3)
                        .padding(diameter * 0.13)
                }
                .frame(width: diameter * 0.44, height: diameter * 0.44)

            // Index line.
            Capsule()
                .fill(Accent.amber)
                .frame(width: 2, height: diameter * 0.2)
                .offset(y: -diameter * 0.31)
                .shadow(color: Accent.amber.opacity(0.8), radius: 4)
                .rotationEffect(.degrees(KnobMath.pointerAngle(for: value)))
        }
        .frame(width: diameter, height: diameter)
        // Comfortably past the 44pt minimum even at the smaller sizes, because
        // this is reached for while the other hand holds the phone and the eye
        // is on the picture — the worst case for a small target.
        .frame(width: max(diameter, 48), height: max(diameter, 48))
        .contentShape(Circle())
        .gesture(turn)
    }

    private var knurling: some View {
        ZStack {
            ForEach(0..<48, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i.isMultiple(of: 2) ? 0.09 : 0.02))
                    .frame(width: 1.4, height: diameter * 0.1)
                    .offset(y: -diameter * 0.44)
                    .rotationEffect(.degrees(Double(i) * 7.5))
            }
        }
        .mask(Circle())
    }

    private var turn: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let centre = CGPoint(x: diameter / 2, y: diameter / 2)
                let angle = atan2(drag.location.y - centre.y, drag.location.x - centre.x) * 180 / .pi

                defer { lastAngle = angle }
                guard let previous = lastAngle else { return }

                value = KnobMath.advance(
                    value, byDegrees: KnobMath.angleDelta(from: previous, to: angle)
                )

                let detent = KnobMath.detent(value, stops: stops)
                if detent != lastDetent {
                    lastDetent = detent
                    Haptics.detent()
                }
            }
            .onEnded { _ in
                lastAngle = nil
                lastDetent = nil
            }
    }
}

// MARK: - 04 · Bellows Drawer

/// A leatherette drawer that rises from the bottom rail carrying three knobs,
/// and tucks away leaving only its pleats — which double as the handle, so the
/// thing you grab to open it is the only part that stays on screen.
struct BellowsDrawer: View {
    @EnvironmentObject var app: AppState
    var rotation: Angle = .zero

    @Binding var open: Bool

    /// How much of the drawer is left showing when stowed: the pleated lip and
    /// nothing else.
    static let lip: CGFloat = 30
    static let height: CGFloat = 158

    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            pleats
            knobs
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(leatherette)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 18, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 18, style: .continuous
        ))
        .overlay(alignment: .top) {
            Rectangle().fill(Tone.hairline).frame(height: 0.5)
        }
        .offset(y: offset)
        .gesture(pull)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: open)
        .animation(.interactiveSpring(), value: drag)
    }

    private var offset: CGFloat {
        let base = open ? 0 : Self.height - Self.lip
        return max(0, min(Self.height - Self.lip, base + drag))
    }

    /// The pleats are the handle. Tapping them works as well as dragging —
    /// a drawer that only opens to a swipe is a drawer half the people never
    /// find.
    private var pleats: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<26, id: \.self) { _ in
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 2, height: 9)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)

            Text(open ? "STOW" : "CONTROLS")
                .font(.mono(7, .semibold))
                .kerning(2)
                .foregroundStyle(Tone.quaternary)
                .padding(.top, 5)
                .rotationEffect(rotation)
        }
        .frame(height: Self.lip)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            open.toggle()
        }
    }

    private var knobs: some View {
        HStack(alignment: .top, spacing: 0) {
            Knob(label: "ISO", reading: app.isoLabel.replacingOccurrences(of: "ISO ", with: ""),
                 value: $app.iso, stops: AppState.isoStops.count, rotation: rotation)
                .frame(maxWidth: .infinity)

            Knob(label: "SHUTTER", reading: app.shutterLabel,
                 value: $app.shutter, stops: AppState.shutterStops.count, rotation: rotation)
                .frame(maxWidth: .infinity)

            Knob(label: "WHITE", reading: app.kelvinLabel,
                 value: $app.whiteBalance, stops: AppState.whiteBalanceStops.count, rotation: rotation)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 14)
        .padding(.horizontal, 8)
    }

    private var leatherette: some View {
        Color(hex: 0x241C14)
            .overlay {
                // The grain. Cheap, fixed, and never animated — a texture that
                // repaints with the preview is a texture that costs frames.
                Canvas { context, size in
                    for row in stride(from: 0, to: size.height, by: 4) {
                        for col in stride(from: 0, to: size.width, by: 4) {
                            let offset = row.truncatingRemainder(dividingBy: 8) == 0 ? 0.0 : 2.0
                            context.fill(
                                Path(ellipseIn: CGRect(x: col + offset, y: row, width: 1, height: 1)),
                                with: .color(.white.opacity(0.05))
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }

    private var pull: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation.height }
            .onEnded { value in
                drag = 0
                // Velocity as well as distance: a quick flick should close it
                // even if the finger barely travelled.
                let flick = value.predictedEndTranslation.height
                if flick < -40 { open = true }
                else if flick > 40 { open = false }
                Haptics.detent()
            }
    }
}

// MARK: - 10 · The Crown

/// One knurled crown on the right edge, borrowed from a watch: press it to
/// choose what it drives, roll it to set the value.
///
/// The whole control is a single object that never grows, which is the point —
/// there is no second knob to add when a fourth setting appears, only another
/// stop on the same crown.
struct CrownControl: View {
    @EnvironmentObject var app: AppState
    var rotation: Angle = .zero

    /// What the crown is currently wired to.
    enum Target: Int, CaseIterable {
        case iso, shutter, white, exposure

        var label: String {
            switch self {
            case .iso: return "ISO"
            case .shutter: return "SHUTTER"
            case .white: return "WHITE"
            case .exposure: return "EXPOSURE"
            }
        }
    }

    @State private var target: Target = .iso
    @State private var panelVisible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            if panelVisible {
                panel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            crown
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: panelVisible)
        .animation(.snappy(duration: 0.22), value: target)
    }

    private var binding: Binding<Double> {
        switch target {
        case .iso: return $app.iso
        case .shutter: return $app.shutter
        case .white: return $app.whiteBalance
        case .exposure: return $app.exposureComp
        }
    }

    private var stops: Int {
        switch target {
        case .iso: return AppState.isoStops.count
        case .shutter: return AppState.shutterStops.count
        case .white: return AppState.whiteBalanceStops.count
        case .exposure: return AppState.evDetents
        }
    }

    private var reading: String {
        switch target {
        case .iso: return app.isoLabel.replacingOccurrences(of: "ISO ", with: "")
        case .shutter: return app.shutterLabel
        case .white: return app.kelvinLabel
        case .exposure: return String(format: "%+.1f", app.evValue)
        }
    }

    private var panel: some View {
        Knob(label: target.label, reading: reading,
             value: binding, stops: stops, diameter: 74, rotation: rotation)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: 16, bottomLeadingRadius: 16,
                    bottomTrailingRadius: 4, topTrailingRadius: 4, style: .continuous
                )
                .fill(LinearGradient(colors: [Color(hex: 0x232323), Color(hex: 0x141414)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16, bottomLeadingRadius: 16,
                        bottomTrailingRadius: 4, topTrailingRadius: 4, style: .continuous
                    )
                    .strokeBorder(Tone.hairline, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.6), radius: 14, x: -4, y: 6)
            }
            .onAppear { scheduleHide() }
    }

    /// Knurled, flush to the edge, and 44 wide before its tap area is even
    /// counted — this is the one control that has to be findable without
    /// looking away from the picture.
    private var crown: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: (0..<22).map { i in
                            .init(color: i.isMultiple(of: 2)
                                  ? Color(hex: 0x3A3A3A) : Color(hex: 0x161616),
                                  location: Double(i) / 21)
                        },
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Tone.hairline, lineWidth: 0.5)
                }
                .frame(width: 26, height: 76)
                .shadow(color: .black.opacity(0.6), radius: 8, x: -3)

            if panelVisible {
                Capsule()
                    .fill(Accent.amber)
                    .frame(width: 3, height: 16)
                    .shadow(color: Accent.amber.opacity(0.9), radius: 5)
            }
        }
        .frame(width: 46, height: 92)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.toggle()
            if panelVisible {
                target = Target(rawValue: (target.rawValue + 1) % Target.allCases.count) ?? .iso
            } else {
                panelVisible = true
            }
            scheduleHide()
        }
        .gesture(roll)
        .accessibilityLabel("Crown, \(target.label)")
        .accessibilityHint("Tap to change what the crown adjusts")
    }

    /// Rolling the crown itself adjusts the current target without ever opening
    /// the panel — the panel is there to tell you what happened, not to be a
    /// prerequisite for it.
    private var roll: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { drag in
                panelVisible = true
                // Up is more, matching the knob's clockwise-is-more.
                let step = -drag.translation.height / 900
                binding.wrappedValue = KnobMath.clamp(binding.wrappedValue + step)
            }
            .onEnded { _ in
                Haptics.detent()
                scheduleHide()
            }
    }

    /// Nothing that isn't a picture survives more than a few seconds of not
    /// being touched.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            panelVisible = false
        }
    }
}

// MARK: - Top Plate · from the design handoff
//
// The handoff's viewfinder: a 210pt warm dark-metal top plate carrying five
// knurled dials, an opaque band the picture starts below rather than an overlay
// on top of it. Everything the app already had is folded in rather than cut —
// the plate's empty head takes the body switches, the handoff's "VIDEO"
// placeholder becomes the real lens selector, and the glass pill it defines for
// HUD chips carries the meter, the status and the zoom.

/// What a dial is doing right now, so the barrel underneath can report it.
///
/// A 44pt dial is a good thing to grab and a poor thing to land a value with.
/// The barrel is the other half of that trade: coarse in the hand, precise on
/// the scale, and gone again the moment you stop.
struct ActiveDial: Equatable {
    /// Which control the barrel is currently attached to. The barrel is a live
    /// control, not a readout, so it has to be able to say what it is driving.
    enum Key: String { case aperture, iso, shutter, white, exposure }

    var key: Key
    var name: String
    var reading: String
    /// 0…1, drives the barrel's travel so the ticks move with the dial.
    var value: Double
}

/// One knurled dial on the plate. Turned like the Knob above — the handoff's own
/// note is that these are rotation-driven controls, with the pro sheet as the
/// expanded view rather than the only way in.
struct PlateDial: View {
    var label: String
    /// Shown inside the dial face. Only the big centre dial uses it.
    var inlineReading: String?
    /// What the barrel calls this control, and what it reads out.
    var barrelKey: ActiveDial.Key
    var barrelName: String
    var barrelReading: String
    @Binding var value: Double
    var stops: Int
    var diameter: CGFloat
    var highlighted: Bool = false
    var rotation: Angle = .zero
    /// Landscape. The label below the dial is dropped and the reading moves
    /// inside the face — a rotated word needs its width in the frame's height,
    /// so "SHUTTER" under the dial climbed back over it once the body turned.
    var compact: Bool = false
    /// True while a *different* dial is being held. The one in hand comes
    /// forward and the rest step back, so the row reads as one control being
    /// used rather than five competing for the eye.
    var receded: Bool = false
    var onTurn: (ActiveDial) -> Void = { _ in }
    var onFocusChange: (Bool) -> Void = { _ in }
    /// Double tap puts this one control back to automatic.
    var onReset: () -> Void = {}
    /// Called once when a turn begins. Shutter and ISO use it to come off A:
    /// touching the dial is what takes a camera out of auto, and without it the
    /// dial moved while the exposure stayed exactly where it was.
    var onEngage: () -> Void = {}

    @State private var lastAngle: Double?
    @State private var lastDetent: Int?
    @State private var engaged = false
    /// Held-down state. @GestureState rather than @State on purpose: it resets
    /// itself the moment the gesture ends *or is cancelled*, so a touch that
    /// slides away can never leave the dial stranded at its enlarged size.
    @GestureState private var pressing = false

    var body: some View {
        VStack(spacing: 4) {
            face
            if !compact {
                Text(label)
                    .font(.mono(7, .semibold))
                    .foregroundStyle(
                        pressing ? Tone.primary
                            : (highlighted ? Accent.amber : Color(hex: 0x8A8478))
                    )
            }
        }
        // Scale, not frame. A size change would reflow the row and shove the
        // neighbouring dials sideways every time one was touched; a transform
        // is invisible to layout, so nothing moves but the dial in the hand.
        .scaleEffect(pressing ? 1.22 : (receded ? 0.94 : 1), anchor: .center)
        .opacity(receded ? 0.42 : 1)
        .zIndex(pressing ? 1 : 0)
        // Enough mass to read as something rising to meet the thumb rather
        // than a number being tweened.
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: pressing)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: receded)
        .onChange(of: pressing) { _, now in onFocusChange(now) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(barrelName)
        .accessibilityValue(barrelReading)
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / Double(max(stops, 1))
            value = KnobMath.clamp(value + (direction == .increment ? step : -step))
            Haptics.detent()
            onTurn(ActiveDial(key: barrelKey, name: barrelName,
                              reading: barrelReading, value: value))
        }
    }

    /// Built the way the object is built, not drawn as a flat circle.
    ///
    /// A real top-plate dial is a machined aluminium disc: a knurled rim you
    /// grip, a milled shoulder catching the light from above, a brushed centre
    /// pad, an engraved index notch, and a hard shadow where it sits into the
    /// body. Each of those is a layer here, lit consistently from the top left,
    /// which is what separates "a knob" from "a circle with lines on it".
    private var face: some View {
        ZStack {
            // The seat it sits down into.
            Circle()
                .fill(Color.black.opacity(0.55))
                .blur(radius: 3)
                .offset(y: diameter * 0.035)

            // Knurled rim. Angular rather than flat so the ridges catch the
            // light round the circumference instead of reading as a texture.
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(hex: 0x6A6459), Color(hex: 0x3A3630),
                            Color(hex: 0x7A7469), Color(hex: 0x2E2B26),
                            Color(hex: 0x5E5850), Color(hex: 0x6A6459)
                        ],
                        center: .center, angle: .degrees(-45)
                    )
                )
                .overlay { knurling }
                .overlay {
                    // Milled shoulder: bright where the light falls, dark
                    // opposite. One highlight, one shadow, same source.
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), .clear,
                                     Color.black.opacity(0.55)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1, diameter * 0.018)
                    )
                }

            // Brushed centre pad, sunk below the rim.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x4A453D), Color(hex: 0x24211D)],
                        center: .init(x: 0.34, y: 0.3),
                        startRadius: 0, endRadius: diameter * 0.42
                    )
                )
                .overlay {
                    // Concentric turning marks, the trace of a lathe.
                    ZStack {
                        ForEach(1..<5, id: \.self) { ring in
                            Circle()
                                .strokeBorder(Color.white.opacity(0.045), lineWidth: 0.5)
                                .padding(diameter * 0.052 * CGFloat(ring))
                        }
                    }
                }
                .overlay {
                    Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1)
                }
                .padding(diameter * 0.19)
                .shadow(color: .black.opacity(0.6), radius: diameter * 0.02, y: 1)

            // Engraved index notch: cut into the metal, so it is a dark groove
            // with a lit lower lip rather than a painted line.
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.75))
                    .frame(width: max(2, diameter * 0.042),
                           height: diameter * 0.17)
                Capsule()
                    .fill(Accent.amber.opacity(pressing ? 1 : 0.92))
                    .frame(width: max(1.5, diameter * 0.028),
                           height: diameter * 0.15)
            }
            .offset(y: -diameter * 0.385)
            .rotationEffect(.degrees(KnobMath.pointerAngle(for: value)))

            // Focus ring, inside its own bounds: the plate clips, and a glow
            // spilling past the metal would be sheared off at the edge.
            Circle()
                .strokeBorder(Accent.amber.opacity(pressing ? 0.9 : 0),
                              lineWidth: max(1.2, diameter * 0.02))
                .padding(diameter * 0.06)

            if let text = compact ? (inlineReading ?? label) : inlineReading {
                Text(text)
                    .font(.mono(max(8, diameter * 0.13), .bold))
                    .foregroundStyle(Color(hex: 0xE8E2D4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: diameter * 0.55)
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                    .rotationEffect(rotation)
            }
        }
        .frame(width: diameter, height: diameter)
        .frame(width: max(diameter, 52), height: max(diameter, 52))
        .shadow(color: .black.opacity(pressing ? 0.7 : 0.45),
                radius: pressing ? diameter * 0.14 : diameter * 0.05,
                y: pressing ? diameter * 0.07 : diameter * 0.02)
        .contentShape(Circle())
        .gesture(turn)
        // Simultaneous, because the turn gesture has a zero minimum distance
        // and would otherwise swallow every tap before the tap recogniser saw
        // it. A tap moves nothing: the turn needs a first movement to arm.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                Haptics.toggle()
                onReset()
            }
        )
    }

    /// The grip. Ridges rather than wedges, each with a lit face and a dark
    /// one, so the rim reads as cut metal from any angle.
    private var knurling: some View {
        ZStack {
            ForEach(0..<60, id: \.self) { i in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.black.opacity(0.34)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(1, diameter * 0.016), height: diameter * 0.12)
                    .offset(y: -diameter * 0.435)
                    .rotationEffect(.degrees(Double(i) * 6))
            }
        }
        .mask(Circle())
    }

    private var turn: some Gesture {
        DragGesture(minimumDistance: 0)
            // Fires on touch-down, before any movement, so the dial is already
            // up by the time the thumb begins to turn it.
            .updating($pressing) { _, state, _ in state = true }
            .onChanged { drag in
                let centre = CGPoint(x: diameter / 2, y: diameter / 2)
                let angle = atan2(drag.location.y - centre.y,
                                  drag.location.x - centre.x) * 180 / .pi
                defer { lastAngle = angle }
                guard let previous = lastAngle else { return }

                if !engaged {
                    engaged = true
                    onEngage()
                }

                value = KnobMath.advance(
                    value, byDegrees: KnobMath.angleDelta(from: previous, to: angle)
                )
                let detent = KnobMath.detent(value, stops: stops)
                if detent != lastDetent {
                    lastDetent = detent
                    Haptics.detent()
                }
                onTurn(ActiveDial(key: barrelKey, name: barrelName,
                                  reading: barrelReading, value: value))
            }
            .onEnded { _ in lastAngle = nil; lastDetent = nil; engaged = false }
    }
}

// MARK: - The barrel a turning dial drops

/// Appears under the plate the moment a dial moves and retires a beat after it
/// stops. Translucent on purpose: it sits over the frame, so it has to let the
/// frame through — blocking the picture to report a number is the wrong trade
/// in a camera.
struct DialBarrel: View {
    var dial: ActiveDial
    var rotation: Angle = .zero
    /// Dragging the barrel drives the same value the dial does. The dial is for
    /// grabbing, the barrel is for landing — a scale you cannot move is just a
    /// label, and this one is long enough to be the better of the two.
    var onScrub: (Double) -> Void = { _ in }

    @State private var lastX: CGFloat?

    var body: some View {
        ZStack {
            // Fine ticks, offset by the value so the scale travels with the dial.
            GeometryReader { geo in
                let spacing: CGFloat = 11
                let travel = CGFloat(dial.value) * spacing * 26
                HStack(spacing: spacing - 1) {
                    ForEach(0..<Int(geo.size.width / spacing) + 30, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i.isMultiple(of: 5) ? 0.42 : 0.16))
                            .frame(width: i.isMultiple(of: 5) ? 1.5 : 1,
                                   height: i.isMultiple(of: 5) ? 20 : 12)
                    }
                }
                .frame(height: geo.size.height, alignment: .center)
                .offset(x: -travel.truncatingRemainder(dividingBy: spacing * 5) - spacing * 8)
            }

            HStack {
                Text(dial.name)
                    .font(.mono(7.5, .semibold))
                    .kerning(1.8)
                    .foregroundStyle(Color(hex: 0x8A8478))
                    .rotationEffect(rotation)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)

            // Fixed index, with the value riding under it.
            Rectangle()
                .fill(Accent.amber)
                .frame(width: 1.5)
                .shadow(color: Accent.amber.opacity(0.7), radius: 4)

            // Background first, then the turned lettering inside a frame that
            // holds it. The other way round the chip drew at the upright size
            // while the reading stood on end and hung out of it.
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Ink.base.opacity(0.8))
                Text(dial.reading)
                    .font(.mono(13, .bold))
                    .foregroundStyle(Tone.primary)
                    .fixedSize()
                    .rotationEffect(rotation)
            }
            .frame(width: 64, height: 40)
        }
        .frame(height: 46)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0x121212).opacity(0.72))
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Tone.hairline, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { drag in
                    let along = DragAxis.along(drag.translation, rotation: rotation)
                    defer { lastX = along }
                    guard let previous = lastX else { return }
                    // 260pt of travel covers the range: long enough that a stop
                    // is a deliberate movement, short enough to cross the whole
                    // ladder without lifting a thumb.
                    onScrub(Double(along - previous) / 260)
                }
                .onEnded { _ in lastX = nil }
        )
        .accessibilityLabel(dial.name)
        .accessibilityValue(dial.reading)
    }
}

/// The film-stock carousel: glass rather than a solid card, so the picture reads
/// through it. Swiping steps stock by stock with a detent each time.
/// The film carousel.
///
/// Nothing in here rotates. A rotated view keeps its *unrotated* layout size, so
/// turning the pieces individually left the strip reserving 90pt of width for a
/// hint that had become 90pt of height — and it spilled straight down onto the
/// focal-length pill. The host turns the whole strip once and reserves the
/// turned footprint, which is the only arrangement where the space it claims
/// matches the space it occupies.
struct FilmCardStack: View {
    @EnvironmentObject var app: AppState
    var rotation: Angle = .zero
    /// Kept for the call sites; the strip no longer turns anything internally.
    var invertNames: Bool = false
    var onOpen: () -> Void

    @State private var drag: CGFloat = 0

    private var index: Int {
        FilmPreset.all.firstIndex { $0.id == app.selectedFilm.id } ?? 0
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                peek(at: index - 1)
                card
                peek(at: index + 1)
            }
            Text("‹ SWIPE FILM ›")
                .font(.mono(8, .semibold))
                .kerning(1.4)
                .foregroundStyle(Color.white.opacity(0.34))
        }
        .contentShape(Rectangle())
        .onTapGesture { Haptics.tap(); onOpen() }
        .gesture(swipe)
        // Fades out at both ends rather than stopping at a hard edge, so the
        // stocks either side read as continuing past the frame instead of
        // being the last two in a list.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white, location: 0.22),
                    .init(color: .white, location: 0.78),
                    .init(color: .white.opacity(0), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: app.selectedFilm)
    }

    /// Along the strip, whichever way the strip is lying. Upright that is a
    /// horizontal drag; turned it is a vertical one, because the strip turned
    /// with the body and the finger follows it.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // Screen-horizontal in both orientations, deliberately.
                //
                // The focal length runs along its own axis, so turning the body
                // turns its gesture too. Film does not: left-to-right is
                // left-to-right whichever way the phone is held. The two being
                // opposite is the point — one is a scale you travel along, the
                // other a shelf you sweep across, and giving both the same axis
                // is what made them feel like they were fighting each other.
                let along = value.translation.width
                let across = value.translation.height
                guard abs(along) > abs(across) else { return }
                let step = along - drag
                if abs(step) > 46 {
                    drag = along
                    move(by: step < 0 ? 1 : -1)
                }
            }
            .onEnded { _ in drag = 0 }
    }

    private func move(by delta: Int) {
        let next = index + delta
        guard FilmPreset.all.indices.contains(next) else {
            Haptics.blocked()
            return
        }
        // One tick per stock crossed — the carousel should feel like a detented
        // wheel, not a scroll view that happens to snap.
        Haptics.detent()
        app.selectedFilm = FilmPreset.all[next]
    }

    private var card: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(app.selectedFilm.swatch)
                .frame(height: 44)
            Text(app.selectedFilm.name.uppercased())
                .font(.mono(6.5, .bold))
                .kerning(0.5)
                .foregroundStyle(Color(hex: 0xFFF6E8).opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .rotationEffect(invertNames ? .degrees(180) : .zero)
        }
        .padding(5)
        .frame(width: 54, height: 74)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hex: 0xC9A45C).opacity(0.30))
        }
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Accent.amber.opacity(0.85), lineWidth: 1.5)
        }
        .overlay(alignment: .top) {
            // The inner light along the top edge is what keeps a translucent
            // card reading as a physical object rather than a tint.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
        }
        .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
        .zIndex(2)
    }

    @ViewBuilder private func peek(at position: Int) -> some View {
        if FilmPreset.all.indices.contains(position) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(FilmPreset.all[position].swatch)
                    .frame(height: 32)
                Text(FilmPreset.all[position].name.uppercased())
                    .font(.mono(5.5, .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(4)
            .frame(width: 40, height: 58)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            }
            .opacity(0.45)
        } else {
            Color.clear.frame(width: 40, height: 58)
        }
    }
}

/// The focal length, as one barrel showing one value.
///
/// It was a row of every length at once, which is a menu, not a barrel. A
/// barrel shows the value in force and nothing else — the rest of the ladder
/// exists, you simply are not at it. Drag across to move along the scale, one
/// detent and one tick of haptics per stop, exactly like the dials above.
///
/// Double tap flips to the front camera and back. The front camera is another
/// focal length rather than a switch elsewhere on the body, and keeping it on
/// this control is what stops "which lens am I shooting through" living in two
/// places — but it is a different *kind* of move along the ladder, so it gets
/// its own gesture rather than a stop that can be scrubbed onto by accident.
struct PlateLensRow: View {
    @ObservedObject var camera: CameraManager
    var selected: String
    var usingFront: Bool
    var rotation: Angle = .zero
    var onSelect: (CameraManager.Lens) -> Void
    var onSelectFront: () -> Void

    @State private var travel: CGFloat = 0
    /// Held-down state. @GestureState for the same reason the dials use it: it
    /// resets the moment the gesture ends or is cancelled, so a thumb that
    /// slides off cannot leave the ladder stuck open over the frame.
    @GestureState private var scrubbing = false

    private var index: Int {
        camera.lenses.firstIndex { $0.id == selected } ?? 0
    }

    private var reading: String {
        camera.lenses.first { $0.id == selected }?.label ?? "1×"
    }

    var body: some View {
        collapsed
            // Hidden only when something replaces it. The ladder was gated to
            // portrait while the pill hid itself in both, so a swipe with the
            // body turned drew nothing at all — the control vanished under the
            // thumb exactly when it was being used.
            .opacity(scrubbing ? 0 : 1)
            // The open ladder is an overlay, so it costs the layout nothing.
            // Sized into the stack it would shove the release and the film
            // strip down the screen every time a lens was touched.
            .overlay {
                // In landscape the focal control stays a compact pill beside
                // the shutter. The large ladder would otherwise cross the
                // rotated histogram band, while a swipe still changes lenses.
                if scrubbing { expanded }
            }
            .contentShape(Capsule())
            .gesture(scrub)
            .simultaneousGesture(frontCameraGesture)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scrubbing)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selected)
            .animation(.snappy(duration: 0.2), value: usingFront)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Focal length")
            .accessibilityValue(usingFront ? "\(reading), front camera" : reading)
            .accessibilityHint("Swipe across to change lens, double tap for the front camera")
            .accessibilityAdjustableAction { direction in
                step(by: direction == .increment ? 1 : -1)
            }
    }

    private var frontCameraGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            Haptics.toggle()
            onSelectFront()
        }
    }

    /// At rest: the value in force and nothing else.
    ///
    /// The pill itself never turns — only the lettering inside it does. It was
    /// built the other way round, with the rotation applied to the content
    /// before the frame that draws the capsule, so the text swung out of its
    /// own background and landed on the film strip while the empty capsule
    /// stayed behind. A fixed frame with the text rotated inside it cannot come
    /// apart like that, whatever angle the body is held at.
    private var collapsed: some View {
        ZStack {
            Capsule().fill(Color.black.opacity(0.45))
            Capsule().fill(.ultraThinMaterial)
            ticks
            Capsule().strokeBorder(Tone.hairline, lineWidth: 0.5)

            // Turned, the lettering has to fit across the pill's short side —
            // 46pt. "0.5×" at 13pt is about 34 and clears it; the same string
            // at 15 with the front glyph beside it is nearer 60 and would hang
            // out of the capsule. So the glyph steps out when the body turns
            // and the front camera is shown by the tint instead.
            HStack(spacing: 6) {
                if usingFront && rotation == .zero {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Accent.amber)
                }
                Text(reading)
                    .font(.mono(rotation == .zero ? 15 : 13, .bold))
                    .foregroundStyle(usingFront ? Tone.primary : Accent.amber)
                    // No numericText transition. It renders the glyphs through
                    // a separate path that does not carry the rotationEffect,
                    // so the reading stayed upright while everything around it
                    // turned — visible in a simulator screenshot at last,
                    // rather than guessed at.
                    .fixedSize()
            }
            .rotationEffect(rotation)
        }
        // Square enough that the lettering fits across the pill turned as well
        // as level — a wide, shallow pill clips its own text at 90 degrees.
        .frame(width: 104, height: 46)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Accent.amber)
                .frame(width: 12, height: 1.5)
                .offset(y: 3)
        }
    }

    /// Under the thumb: the whole ladder, larger, with everything but the value
    /// in force thrown out of focus. You are choosing, so you get to see what
    /// there is to choose from — and only then.
    ///
    /// Built background-first, like the collapsed pill. It was built the other
    /// way — rotation applied to the row, *then* a .background behind it — so
    /// the capsule drew at the upright 220pt-wide frame while the turned row
    /// stood 220pt tall and stuck straight out of it, over the film strip. That
    /// is the same fault as the collapsed pill and the film hint, in the one
    /// place it had not been fixed.
    private var expanded: some View {
        let along = CGFloat(max(camera.lenses.count, 1)) * 50 + 24
        let across: CGFloat = 56

        return ZStack {
            Capsule().fill(Color.black.opacity(0.55))
            Capsule().fill(.ultraThinMaterial)
            Capsule().strokeBorder(Accent.amber.opacity(0.5), lineWidth: 1)

            HStack(spacing: 4) {
                ForEach(camera.lenses) { lens in
                    let active = lens.id == selected
                    Text(lens.label)
                        // Only the lettering turns. The ladder keeps the shape
                        // it has upright — turning the whole thing made it a
                        // vertical capsule, which is not the same control.
                        .rotationEffect(rotation)
                        .font(.mono(active ? 17 : 13, .bold))
                        .foregroundStyle(active ? Accent.amber : Tone.primary)
                        .blur(radius: active ? 0 : 1.4)
                        .opacity(active ? 1 : 0.4)
                        .scaleEffect(active ? 1 : 0.88)
                        .frame(minWidth: 46, minHeight: 44)
                        .background {
                            if active { Capsule().fill(Accent.amber.opacity(0.18)) }
                        }
                }
            }
            .fixedSize()
        }
        // One shape in both orientations, exactly as upright. The ladder used
        // to swap its dimensions with the body, which turned a wide row of
        // focal lengths into an elongated capsule — a different control, not a
        // rotated one.
        .frame(width: along, height: across)
        .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
        .transition(.scale(scale: 0.86).combined(with: .opacity))
    }

    private var ticks: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 7
            HStack(spacing: spacing - 1) {
                ForEach(0..<Int(geo.size.width / spacing) + 12, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(i.isMultiple(of: 4) ? 0.22 : 0.09))
                        .frame(width: 1, height: i.isMultiple(of: 4) ? 11 : 6)
                }
            }
            .frame(height: geo.size.height, alignment: .center)
            .offset(x: -CGFloat(index) * spacing * 2 - spacing * 3)
            .animation(.spring(response: 0.3, dampingFraction: 0.84), value: index)
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }

    /// One stop per 44pt of travel: far enough that a stop is deliberate, close
    /// enough that the whole ladder is one short drag.
    private var scrub: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($scrubbing) { _, state, _ in state = true }
            .onChanged { drag in
                // Whichever axis the thumb actually travelled on, rather than
                // the one the rotation says it should have. Two attempts to
                // derive it from the angle both failed on device while
                // appearing correct in code, so this stops asserting what the
                // gesture must be and reads what it is: a vertical drag scrubs
                // when the body is turned, a horizontal one when it is not,
                // and neither depends on the angle being what we think.
                let t = drag.translation
                let along = abs(t.height) > abs(t.width) ? t.height : t.width
                let moved = along - travel
                // 26, not 44. A lens ladder is four stops; asking for 44pt each
                // made a two-stop change a 90pt drag on a control the size of a
                // thumbnail.
                guard abs(moved) >= 26 else { return }
                travel = along
                // Negative is forward, the same sense the film strip uses. A
                // control that agrees with itself in one orientation and
                // disagrees in the other is worse than one that is simply
                // backwards, so the two are pinned together.
                step(by: moved < 0 ? 1 : -1)
            }
            .onEnded { _ in travel = 0 }
    }

    private func step(by delta: Int) {
        let next = index + delta
        guard camera.lenses.indices.contains(next) else {
            Haptics.blocked()
            return
        }
        Haptics.detent()
        onSelect(camera.lenses[next])
    }
}

/// The mark left behind when something has been swiped away.
///
/// A control that can be hidden needs somewhere to have gone. Without this the
/// swipe is indistinguishable from the feature disappearing, and the way back
/// is a gesture nobody was told about — so what is left is small, points the
/// way the thing will return from, and answers to a tap as well as a swipe.
struct RevealHandle: View {
    var label: String
    var symbol: String
    var rotation: Angle = .zero
    var action: () -> Void

    @State private var breathing = false

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            // Background first, then the turned label inside a frame square
            // enough to hold it either way up. Rotated after its own padding,
            // the lettering stood on end and hung out of the capsule.
            ZStack {
                Capsule().fill(Color.black.opacity(0.5))
                Capsule().fill(.ultraThinMaterial)
                Capsule().strokeBorder(Accent.amber.opacity(0.35), lineWidth: 0.5)

                HStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                    Text(label)
                        .font(.mono(7.5, .semibold))
                        .kerning(1.4)
                }
                .foregroundStyle(Accent.amber.opacity(0.95))
                .fixedSize()
                .rotationEffect(rotation)
            }
            // Square enough to hold the label lying either way. 62x44 was not:
            // turned, a 46pt label needs 46 of height and had 44, so the
            // lettering hung out of the capsule. Caught by a test rather than
            // by another screenshot.
            .frame(width: 64, height: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(breathing ? 1 : 0.62)
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathing)
        .onAppear { breathing = true }
        .accessibilityLabel("Show \(label.lowercased())")
    }
}

// MARK: - Plate metrics

/// Every size on the plate, derived from the width of the phone it is on.
///
/// Nothing here is a fixed point value chosen against one device. The dials
/// keep their relative proportions — the shutter dial is the largest, aperture
/// and exposure the smallest, exactly as on a camera top plate — and the row is
/// then scaled to whatever width it has been given. A Pro Max gets larger dials
/// than an SE because it has the glass for them, and neither is a special case
/// in the code.
///
/// Pure and static so the arithmetic can be tested at every screen size rather
/// than checked on the one phone that happens to be plugged in.
enum PlateMetrics {

    /// Relative sizes, not point sizes. The proportions are the design; the
    /// scale is the device's.
    static let dialWeights: [CGFloat] = [44, 50, 70, 50, 44]
    static let dialSpacing: CGFloat = 4
    static let rowPadding: CGFloat = 8

    /// Floor and ceiling so a very narrow or very wide body cannot produce a
    /// dial too small to grip or so large it eats the frame.
    static let minScale: CGFloat = 0.9
    static let maxScale: CGFloat = 1.8

    /// The multiplier that makes the row exactly fill the width it is given.
    static func dialScale(forWidth width: CGFloat) -> CGFloat {
        let gaps = dialSpacing * CGFloat(dialWeights.count - 1)
        let usable = width - rowPadding * 2 - gaps
        guard usable > 0 else { return minScale }
        let raw = usable / dialWeights.reduce(0, +)
        return min(maxScale, max(minScale, raw))
    }

    static func dialDiameter(weight: CGFloat, forWidth width: CGFloat) -> CGFloat {
        weight * dialScale(forWidth: width)
    }

    /// The switches scale with the body too, and never fall under the 44pt
    /// Apple asks for however narrow the phone is.
    static func switchSide(forWidth width: CGFloat) -> CGFloat {
        min(64, max(44, width * 0.135))
    }

    /// Tallest dial plus room for the label beneath it.
    static func stripHeight(forWidth width: CGFloat) -> CGFloat {
        (dialWeights.max() ?? 70) * dialScale(forWidth: width) + 26
    }

    /// The switch row: the inset above it plus the switch itself.
    static func switchRowHeight(forWidth width: CGFloat, safeTop: CGFloat = 46) -> CGFloat {
        // The real top inset, not a guessed 46: the plate ignores the safe area
        // so its metal reaches the top of the glass, which means it has to put
        // the inset back itself — and at 46 the switch row ran under the
        // Dynamic Island on the bodies that have 59.
        //
        // Then the switches, the gap, the PRO control, and its own small tail.
        max(46, safeTop + 10) + switchSide(forWidth: width)
            + proGap(forWidth: width) + proControlHeight + 6
    }

    /// The film strip's footprint. Square on purpose: a square frame is the
    /// same size turned as upright, so rotating the strip cannot move it or
    /// change what it displaces. Derived from the body like everything else.
    static func filmSide(forWidth width: CGFloat) -> CGFloat {
        min(190, max(120, width * 0.36))
    }

    /// The roll thumbnail, matched across the release so the two flank it
    /// evenly rather than one dwarfing the other.
    static func rollSide(forWidth width: CGFloat) -> CGFloat {
        min(76, max(48, width * 0.14))
    }

    /// The bar that holds film, release and roll. Tall enough for the largest
    /// of them whichever way the body is held.
    static func bottomBarHeight(forWidth width: CGFloat) -> CGFloat {
        max(filmSide(forWidth: width), 96) + 8
    }

    /// The shaded band behind the bottom controls, sized to what it holds —
    /// the bar, the focal row above it, and equal air top and bottom. It was a
    /// flat 260 while the bar grew with the phone, so the controls sat at the
    /// top of the band with a third of it empty underneath.
    static func deckShadeHeight(forWidth width: CGFloat) -> CGFloat {
        bottomBarHeight(forWidth: width) + focalRowHeight + shadeMargin
    }

    /// The focal-length row and the gap under it.
    static let focalRowHeight: CGFloat = 56
    /// The gap between the switch row and the PRO control, and the control's
    /// own height. Scaled to the body like everything else on the plate.
    static func proGap(forWidth width: CGFloat) -> CGFloat {
        min(22, max(12, width * 0.034))
    }
    static let proControlHeight: CGFloat = 34

    /// Air above the group inside the shaded band.
    static let shadeMargin: CGFloat = 10
    /// And under it. Deliberately smaller than the margin above: the group
    /// belongs low in the band, near the hand, not floating in its middle.
    static let bottomInset: CGFloat = 0

    static func plateHeight(proOpen: Bool, forWidth width: CGFloat, safeTop: CGFloat = 46) -> CGFloat {
        proOpen
            // Open, the dial labels sit under the dials and need room inside
            // the plate or "SHUTTER" is clipped at the metal's edge.
            ? switchRowHeight(forWidth: width, safeTop: safeTop) + stripHeight(forWidth: width) + 14
            // Closed, exactly what it holds — the button's own bottom padding
            // and nothing more. Surplus here is blank metal under it.
            : switchRowHeight(forWidth: width, safeTop: safeTop)
    }
}

/// The five dials, half again their original size, on the plate where they
/// started.
///
/// At 1.5x they are 66 / 75 / 105 / 75 / 66 — 387pt of dial against 393pt of
/// narrow phone and 440 of a Pro Max. So it fits on the wide bodies and only
/// just misses on the narrow ones, which is why the row still sits in a scroll
/// view: on a Pro Max it never scrolls and reads as a fixed row, and on a
/// smaller screen the outer dials stay reachable instead of being cropped away.
struct DialStrip: View {
    @EnvironmentObject var app: AppState
    var rotation: Angle = .zero
    var compact: Bool = false
    var onDialTurn: (ActiveDial) -> Void
    var onReset: (ActiveDial.Key) -> Void

    /// The width this row has been given. Every size below comes from it.
    var width: CGFloat

    @State private var focused: ActiveDial.Key?

    private var apertureBinding: Binding<Double> {
        Binding(
            get: {
                let last = Double(AppState.apertureStops.count - 1)
                return last > 0 ? Double(app.apertureIndex) / last : 0
            },
            set: { fresh in
                let last = AppState.apertureStops.count - 1
                app.apertureIndex = min(last, max(0, Int((fresh * Double(last)).rounded())))
            }
        )
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: PlateMetrics.dialSpacing) {
                dial(.aperture, label: AppState.apertureLabels[app.apertureIndex],
                     name: "APERTURE", reading: AppState.apertureLabels[app.apertureIndex],
                     value: apertureBinding, stops: AppState.apertureStops.count, base: 44)

                dial(.iso, label: app.isoLabel, name: "ISO", reading: app.isoLabel,
                     value: $app.iso, stops: AppState.isoStops.count, base: 50)

                dial(.shutter, label: "SHUTTER", name: "SHUTTER", reading: app.shutterLabel,
                     value: $app.shutter, stops: AppState.shutterStops.count, base: 70,
                     inline: app.shutterLabel, highlighted: true)

                dial(.white, label: app.kelvinLabel, name: "WHITE BALANCE",
                     reading: app.kelvinLabel, value: $app.whiteBalance,
                     stops: AppState.whiteBalanceStops.count, base: 50)

                dial(.exposure, label: String(format: "%+.1fEV", app.evValue),
                     name: "EXPOSURE", reading: String(format: "%+.1f EV", app.evValue),
                     value: $app.exposureComp, stops: AppState.evDetents, base: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PlateMetrics.rowPadding)
            .frame(height: PlateMetrics.stripHeight(forWidth: width))
        }
        .scrollIndicators(.hidden)
        // Without this the enlarged dial is cut off at the row's edge the
        // moment it is pressed — a scroll view clips its own content, and the
        // whole point of the press is that it grows.
        .scrollClipDisabled()
        .frame(height: PlateMetrics.stripHeight(forWidth: width))
    }

    private func dial(
        _ key: ActiveDial.Key, label: String, name: String, reading: String,
        value: Binding<Double>, stops: Int, base: CGFloat,
        inline: String? = nil, highlighted: Bool = false
    ) -> some View {
        PlateDial(
            label: label, inlineReading: inline,
            barrelKey: key, barrelName: name, barrelReading: reading,
            value: value, stops: stops,
            diameter: PlateMetrics.dialDiameter(weight: base, forWidth: width),
            highlighted: highlighted, rotation: rotation, compact: compact,
            receded: focused != nil && focused != key,
            onTurn: onDialTurn,
            onFocusChange: { holding in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    focused = holding ? key : (focused == key ? nil : focused)
                }
            },
            onReset: { onReset(key) }
        )
    }
}


/// The metal plate. PRO lives here now rather than at the bottom of the screen,
/// and what it does is open and close the plate: the tap that means "I am
/// setting up" is the same tap that produces the instruments. Closed, the plate
/// is the switches alone and the picture gets the rest of the glass.
struct TopPlateBand: View {
    @EnvironmentObject var app: AppState
    var rotation: Angle = .zero
    var compact: Bool = false
    var onSettings: () -> Void
    var onCycleGrid: () -> Void
    var onCycleAspect: () -> Void
    var aspect: String
    var onDialTurn: (ActiveDial) -> Void
    var onResetDial: (ActiveDial.Key) -> Void = { _ in }
    /// The width the plate has been given, so its sizes follow the phone.
    var width: CGFloat
    /// The real top safe-area inset. The plate ignores the safe area so its
    /// metal reaches the top of the glass, which means it has to put the inset
    /// back itself — at a hardcoded 46 the switch row ran under the Dynamic
    /// Island on the larger bodies, which have 59.
    var safeTop: CGFloat = 46

    /// Deferred to PlateMetrics so the plate is as deep as the phone needs and
    /// no deeper. With PRO off it is the switch row alone: the camera is on
    /// auto and every dial would read AUTO, and a control displaying a value it
    /// is not setting is worse than no control.
    static func height(proOpen: Bool, width: CGFloat, safeTop: CGFloat = 46) -> CGFloat {
        PlateMetrics.plateHeight(proOpen: proOpen, forWidth: width, safeTop: safeTop)
    }

    /// Which dial is being held, so the others can step back.
    @State private var focused: ActiveDial.Key?

    private func focus(_ key: ActiveDial.Key) -> (Bool) -> Void {
        { holding in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                focused = holding ? key : (focused == key ? nil : focused)
            }
        }
    }

    private func receded(_ key: ActiveDial.Key) -> Bool {
        focused != nil && focused != key
    }

    private var apertureBinding: Binding<Double> {
        Binding(
            get: {
                let last = Double(AppState.apertureStops.count - 1)
                return last > 0 ? Double(app.apertureIndex) / last : 0
            },
            set: { fresh in
                let last = AppState.apertureStops.count - 1
                app.apertureIndex = min(last, max(0, Int((fresh * Double(last)).rounded())))
            }
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Semi-transparent, over material rather than a solid slab. The
            // frame now runs behind the plate instead of starting below it, so
            // the top of the picture is visible rather than paid for.
            LinearGradient(colors: [Color(hex: 0x302D28).opacity(0.82),
                                    Color(hex: 0x1C1A17).opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(hex: 0x0A0A0A).opacity(0.6)).frame(height: 1)
                }
                .opacity(app.proMode ? 0 : 1)

            VStack(spacing: 0) {
                utilities.padding(.top, max(46, safeTop + 10))

                // In the stack, not floating over it. As an overlay it sat in a
                // different layer from the switch row, so it collided with the
                // buttons above it and no amount of padding inside the overlay
                // could push it clear — the overlay was anchored, not flowed.
                proControl
                    .padding(.top, PlateMetrics.proGap(forWidth: width))
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .center)

                if app.proMode {
                    DialStrip(rotation: rotation, compact: compact,
                              onDialTurn: onDialTurn, onReset: onResetDial,
                              width: width)
                        .padding(.top, 6)
                        .transition(.opacity.combined(with: .offset(y: -14)))
                }
            }
        }
        .frame(height: Self.height(proOpen: app.proMode, width: width, safeTop: safeTop))
        .frame(maxWidth: .infinity)
        .clipped()
        // Hung under the plate rather than inside it. On the plate it competed
        // with the switch row for the same 46pt of inset and was the first
        // thing the clip took; here it sits on the picture, centred, right
        // where the dials appear from.

        .zIndex(2)
        // Swipe the instruments away when they are in the way: up in portrait,
        // left when the body is turned — both are "push it off the frame" in
        // the direction the plate actually sits.
        //
        // Attached to the plate rather than to the dials, and as .gesture so a
        // child wins: a touch that starts on a dial is a turn, and a long
        // horizontal turn would otherwise read as a swipe and dismiss the very
        // control being used. PRO brings them back.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { drag in
                    guard app.proMode else { return }
                    let away = compact
                        ? drag.translation.width < -44
                        : drag.translation.height < -44
                    guard away else { return }
                    Haptics.toggle()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                        app.proMode = false
                    }
                }
        )
    }

    /// No camera-flip button: front is a focal length now, chosen in the lens
    /// row with the others.
    /// Square, and glyphs rather than words.
    ///
    /// Words were the bug: a rotated "PORTRAIT" needs its width in the frame's
    /// height, so turning the body clipped every label to "PORTI", "GR", "3:".
    /// A square button holds a square glyph at any angle, and squares are also
    /// how these get bigger in both directions at once.
    private var utilities: some View {
        HStack(spacing: 8) {
            if app.cameraManager.supportsPortrait {
                utility(systemImage: "person.and.background.dotted",
                        on: app.portrait, label: "Portrait") {
                    app.togglePortrait()
                }
            }

            utility(systemImage: "grid", on: false, label: "Grid", action: onCycleGrid)
            utility(text: aspect, on: false, label: "Aspect ratio", action: onCycleAspect)
            utility(systemImage: "gearshape", on: false, label: "Settings", action: onSettings)

            if app.proMode {
                utility(systemImage: "arrow.counterclockwise", on: false,
                        label: "Reset controls") {
                    app.resetControls()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }

    /// The dedicated control under the utilities reveals or hides the dial
    /// deck. Its arrow turns with gravity, not with the locked interface.
    private var proControl: some View {
        Button {
            togglePro()
        } label: {
            HStack(spacing: 4) {
                Text("PRO")
                    .font(.mono(8, .bold))
                    .kerning(1.1)
                Image(systemName: app.proMode ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(app.proMode ? Accent.amber : Color(hex: 0xC9C2B4))
            // Deliberately not rotated. The word is three letters and reads
            // perfectly well upright at any angle; turning it only made it
            // harder to find. The arrow carries the state instead.
            .frame(width: 84, height: 34)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.16))
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                app.proMode ? Accent.amber.opacity(0.68) : Color.white.opacity(0.22),
                                lineWidth: 0.8
                            )
                    }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { drag in
                guard max(abs(drag.translation.width), abs(drag.translation.height)) > 38 else { return }
                togglePro()
            }
        )
        .accessibilityLabel(app.proMode ? "Hide pro controls" : "Show pro controls")
    }

    private func togglePro() {
        Haptics.toggle()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            app.proMode.toggle()
        }
    }

    private func utility(
        systemImage: String? = nil, text: String? = nil,
        on: Bool, label: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.toggle()
            action()
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 19, weight: .medium))
                } else if let text {
                    Text(text).font(.mono(11, .semibold)).kerning(0.4).fixedSize()
                }
            }
            .foregroundStyle(on ? Ink.base : Color(hex: 0xA09A8D))
            .rotationEffect(rotation)
            // One width for every switch on the plate. The gear used to be an
            // icon in a 28pt box beside a much wider PORTRAIT, which read as
            // two classes of control when they are the same class — and made
            // the most-used one the hardest to hit.
            // Square, and sized from the body rather than pinned at a number:
            // square so a rotated glyph never outgrows its own button, and
            // never under the 44pt Apple asks for however narrow the phone.
            .frame(width: PlateMetrics.switchSide(forWidth: width),
                   height: PlateMetrics.switchSide(forWidth: width))
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(on ? Accent.amber : Color.black.opacity(0.34))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(on ? .clear : Color.white.opacity(0.09), lineWidth: 1)
                    }
                    .padding(4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Everything below the plate: the HUD chips, the film carousel, the dial rail,
/// the focal-length row, and the bottom bar.
///
/// PRO sits in the bottom bar and gates the dial rail: on, the rail slides up
/// under the hand; off, the camera is on auto and there is nothing to set.
struct TopPlateDeck: View {
    @EnvironmentObject var app: AppState
    var rotation: Angle = .zero
    /// True when the body is turned. The controls do not move — only the film
    /// strip changes station, to the ground-facing edge.
    var landscape: Bool = false
    var histogramStyle: String
    var aspect: String
    var onSettings: () -> Void
    var onFilmSim: () -> Void
    var onLibrary: () -> Void
    var onFire: () -> Void
    var onDialTurn: (ActiveDial) -> Void = { _ in }
    var onResetDial: (ActiveDial.Key) -> Void = { _ in }
    /// The width the deck has been given, so its sizes follow the phone.
    var width: CGFloat = 393
    /// True while the dial barrel is on screen. The barrel hangs directly under
    /// the plate — above the instruments, where the dials it belongs to are —
    /// so the instruments step down by its depth for as long as it is there
    /// rather than living permanently below a gap that is usually empty.
    var barrelShowing: Bool = false

    var body: some View {
        // The focal control stays in the same station in both orientations;
        // only its engraving rotates with the body.
        portraitDeck
    }

    private var portraitDeck: some View {
        VStack(spacing: 0) {
            // Turned, the instruments go on a rotated band at the sky edge —
            // laid out horizontally inside it and rotated as one piece. Rotating
            // each readout inside a portrait-shaped frame is what clipped the
            // meter to ".8 0" and lapped it over the zoom.
            Spacer(minLength: 0)

            // Film immediately before the focal length, turned or not. It was
            // on the leading edge in landscape, which put it across the frame
            // from the lens it belongs beside.
            filmBand

            lensRow.padding(.bottom, 12)
            // Equal air under the bar as above the focal row, so the group sits
            // centred in the shaded band rather than pinned to its top.
            bottomBar.padding(.bottom, PlateMetrics.bottomInset)
        }
        // Histogram and metering directly under the dials, on the trailing
        // side — the top of the frame when the body is turned, and out of the
        // way of both the release and the film strip.
        .overlay(alignment: .topTrailing) {
            instruments
                .padding(.trailing, 14)
                // Upright the plate is directly above, and the dial barrel
                // drops out from under it whenever a dial is turned. The barrel
                // belongs there — beside the dials it reports on — so the
                // readouts sit *below* it and step down only while it is out.
                // At rest there is nothing between them and the plate, which is
                // what a flat 64 was costing: the histogram sat low all the
                // time to leave room for something usually absent.
                .padding(.top, landscape ? 12 : (barrelShowing ? Self.barrelClearance : 12))
                .animation(.easeOut(duration: 0.22), value: barrelShowing)
        }
        // Landscape film is not drawn here at all. Pinned to .bottom it landed
        // on the shutter — the release lives at that edge too. Turned, "the
        // bottom" is a different edge of the glass entirely, so the screen
        // places it against the one actually facing the ground.
    }

    /// Film now lives beside the shutter in both orientations. Keeping an empty
    /// band here prevents the old sky-edge carousel from returning in portrait
    /// or becoming a rotated slab over the live image in landscape.
    @ViewBuilder private var filmBand: some View {
        EmptyView()
    }

    /// The same strip, without the portrait padding, for the screen to hang on
    /// a rotated band when the body is turned.
    static func landscapeFilm(rotation: Angle, onOpen: @escaping () -> Void) -> some View {
        FilmCardStack(rotation: .zero, invertNames: false, onOpen: onOpen)
    }

    /// The instruments as one horizontal row, for the sky-edge band.
    ///
    /// Nothing inside is rotated: the band turns as a whole, so every readout
    /// keeps its natural width and none of them can clip. That is the same
    /// reason the switches became squares.
    static func landscapeInstruments(
        camera: CameraManager, zoom: Double, histogramStyle: String
    ) -> some View {
        HStack(spacing: 8) {
            LiveHistogramView(frames: camera.frames, style: histogramStyle)
            // Capped. The status line is a sentence when something is wrong
            // ("camera access denied — settings › latitude"), and at full width
            // it pushed the histogram clean off the other edge of the screen.
            CameraStatusPill(camera: camera)
                .frame(maxWidth: 132)
                .fixedSize(horizontal: false, vertical: true)
            MeterReadout(frames: camera.frames, rotation: .zero)

            if let wide = camera.lenses.first(where: { $0.id == "wide" }) {
                Text(String(format: "%.1f×", zoom / Double(wide.zoom)))
                    .font(.mono(9, .semibold))
                    .foregroundStyle(Accent.amber)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background { RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45)) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                LiveHistogramView(frames: app.cameraManager.frames, style: histogramStyle)
                CameraStatusPill(camera: app.cameraManager)
                MeterReadout(frames: app.cameraManager.frames, rotation: rotation)

                if let wide = app.cameraManager.lenses.first(where: { $0.id == "wide" }) {
                    Text(String(format: "%.1f×", app.zoom / Double(wide.zoom)))
                        .font(.mono(9, .semibold))
                        .foregroundStyle(Accent.amber)
                        .rotationEffect(rotation)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background { RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45)) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// The dial barrel's own height (46) plus the air above and below it. The
    /// barrel hangs under the plate and the instruments start beneath it.
    static let barrelClearance: CGFloat = 68

    /// Laid out horizontally and turned as one piece, so no readout is rotated
    /// inside a frame sized for it upright — the fault that clipped the meter
    /// to ".8 0" and lapped it over the zoom.
    private var instruments: some View {
        TopPlateDeck.landscapeInstruments(
            camera: app.cameraManager,
            zoom: app.zoom,
            histogramStyle: histogramStyle
        )
        .fixedSize()
        .rotationEffect(rotation)
        // Turned, the row becomes a column: it books 64 across and 330 down,
        // which is the footprint it actually occupies once rotated. Booking the
        // upright 300x62 is what left it outside its own frame and clipped away
        // to nothing.
        // Centred, not top-aligned. rotationEffect turns a view about the
        // centre of its *own* layout box, so aligning the outer frame to the
        // top leaves the rendered column hanging ~127pt above that frame —
        // off the top of the deck, which is why it disappeared entirely once
        // the body was turned. Centring puts the rendering where the frame is.
        .frame(width: landscape ? 64 : nil,
               height: landscape ? 330 : nil,
               alignment: .center)
        .allowsHitTesting(false)
    }

    private var lensRow: some View {
        PlateLensRow(
            camera: app.cameraManager,
            selected: app.lensID,
            usingFront: app.usingFrontCamera,
            rotation: rotation,
            onSelect: { app.selectLens($0) },
            onSelectFront: { app.flipCamera() }
        )
    }

    private var bottomBar: some View {
        ZStack {
            LeafShutterButton(action: onFire)

            HStack(spacing: 0) {
                // Film sits beside the release and centred on it — the same
                // station in both orientations, turning with the body rather
                // than jumping to another edge. Its own frame swaps with the
                // turn, so the turned strip books the space it occupies.
                FilmCardStack(rotation: rotation, invertNames: false, onOpen: onFilmSim)
                    .fixedSize()
                    .scaleEffect(0.92)
                    .rotationEffect(rotation)
                    // Scaling and rotating both leave the layout size alone, so
                    // the frame has to be the size the strip ends up: turned and
                    // at 0.66 that is about 66 x 112. Booking more than it
                    // occupies is what pushed it off centre from the release.
                    // One square frame in both orientations. The icons were
                    // being re-framed on turn, which moved them across the bar
                    // — asked not to. A square is the same size at any angle,
                    // so the strip turns in place and displaces nothing.
                    .frame(width: PlateMetrics.filmSide(forWidth: width),
                           height: PlateMetrics.filmSide(forWidth: width))
                    .contentShape(Rectangle())

                Spacer(minLength: 0)

                Button { onLibrary() } label: {
                    LibraryThumbnail(gallery: app.gallery)
                        // Matched to the film strip across the release: the two
                        // flank it, and a roll a third the size of the stock
                        // beside it read as an afterthought.
                        .scaleEffect(1.5)
                        .rotationEffect(rotation)
                        // The same width the film strip claims on the other
                        // side. They flank the release, so unequal flanks put
                        // the release off centre however it is aligned.
                        .frame(width: PlateMetrics.filmSide(forWidth: width),
                               height: PlateMetrics.rollSide(forWidth: width))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Library")
            }
            .padding(.horizontal, 22)
        }
        .frame(height: PlateMetrics.bottomBarHeight(forWidth: width))
    }
}

// MARK: - Leaf shutter release

/// The release, built as an actual leaf shutter rather than a white circle.
///
/// A leaf shutter is a ring of overlapping blades that sweep closed from the rim
/// inward and open the same way — unlike a focal-plane curtain, it has no
/// travelling slit, and the aperture stays circular through the whole movement.
/// That is what makes it worth drawing: the closure reads as a real mechanism at
/// any speed, and it is legible even at the size of a thumb.
///
/// The geometry is a pure function so the blade positions can be tested rather
/// than trusted — five blades that fail to meet leave a hole in the middle at
/// full closure, which looks like a rendering bug and is really arithmetic.
enum LeafShutterGeometry {

    /// Blades in the ring. Odd numbers read as mechanical rather than as a
    /// flower; five is what most real leaf shutters use.
    static let bladeCount = 5

    /// How far one blade has swung, 0 fully open and 1 fully shut.
    ///
    /// Blades overlap, so each only travels its own share of the circle plus a
    /// margin — swinging every blade the full turn would stack them all on one
    /// side and leave the opposite side open.
    static func bladeAngle(index: Int, closure: Double) -> Double {
        let seat = Double(index) * (360.0 / Double(bladeCount))
        return seat + clampedClosure(closure) * (360.0 / Double(bladeCount)) * 1.08
    }

    /// The open radius as a fraction of the button. At full closure this reaches
    /// zero, which is the property that matters: any residual radius is a hole
    /// in the middle of a shut shutter.
    static func apertureRadius(closure: Double) -> Double {
        let eased = 1 - pow(1 - clampedClosure(closure), 1.7)
        return max(0, 1 - eased)
    }

    static func clampedClosure(_ value: Double) -> Double { min(1, max(0, value)) }
}

/// 78pt against the handoff's 62 — the release is the one control reached for
/// without looking, and the blades need room to read as blades.
struct LeafShutterButton: View {
    var diameter: CGFloat = 78
    var action: () -> Void

    @State private var closure: Double = 0
    @State private var pressed = false

    var body: some View {
        ZStack {
            // Outer ring — the shutter housing.
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: diameter, height: diameter)

            // The blades themselves, seated just inside the housing.
            ZStack {
                ForEach(0..<LeafShutterGeometry.bladeCount, id: \.self) { index in
                    LeafBlade()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0xF6F3ED), Color(hex: 0xBFB9AD)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            LeafBlade().stroke(Color.black.opacity(0.16), lineWidth: 0.5)
                        }
                        .rotationEffect(.degrees(
                            LeafShutterGeometry.bladeAngle(index: index, closure: closure)
                        ))
                }
            }
            .frame(width: diameter - 12, height: diameter - 12)
            .clipShape(Circle())

            // The opening. Shows the scene through the blades rather than a
            // hole cut to the background, so it reads as an aperture.
            Circle()
                .fill(Ink.base.opacity(0.9))
                .frame(
                    width: (diameter - 12) * LeafShutterGeometry.apertureRadius(closure: closure) * 0.62,
                    height: (diameter - 12) * LeafShutterGeometry.apertureRadius(closure: closure) * 0.62
                )
                .overlay {
                    Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
                }
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(pressed ? 0.94 : 1)
        .contentShape(Circle())
        .accessibilityLabel("Shutter")
        .accessibilityAddTraits(.isButton)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    withAnimation(.easeIn(duration: 0.09)) { closure = 1 }
                }
                .onEnded { _ in
                    pressed = false
                    action()
                    // Shut, then open — the exposure is the closed moment, and
                    // reopening immediately is what makes it a shutter firing
                    // rather than a button being held.
                    withAnimation(.easeOut(duration: 0.17).delay(0.05)) { closure = 0 }
                }
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: pressed)
    }
}

/// One blade: a wedge with a curved outer edge, hinged at the rim the way a real
/// leaf blade pivots on its post.
private struct LeafBlade: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let span = 360.0 / Double(LeafShutterGeometry.bladeCount) * 1.55

        var path = Path()
        path.move(to: centre)
        path.addArc(
            center: centre, radius: radius,
            startAngle: .degrees(-span / 2 - 90),
            endAngle: .degrees(span / 2 - 90),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Developing a save

/// What the editor shows while an edit is written back onto its asset.
///
/// A save that takes a moment and shows nothing reads as a tap that missed, and
/// this one genuinely takes a moment — Photos has to render the frame and swap
/// it in. The metaphor is the one the rest of the app uses: the picture comes up
/// out of the bath, a line sweeping down it as it develops.
struct DevelopingOverlay: View {
    enum Phase: Equatable {
        case developing
        case done(String)
        case failed(String)
    }

    var phase: Phase
    var image: UIImage?

    @State private var sweep: CGFloat = 0
    @State private var settled = false

    var body: some View {
        ZStack {
            Ink.base.opacity(0.86).ignoresSafeArea()

            VStack(spacing: 26) {
                frame
                caption
            }
            .padding(32)
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
        .onChange(of: phase) { _, new in
            guard case .done = new else { return }
            withAnimation(.spring(response: 0.44, dampingFraction: 0.7)) { settled = true }
        }
    }

    private var frame: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // Comes up from flat and dark, the way a print does.
                    .saturation(developing ? 0.15 : 1)
                    .brightness(developing ? -0.16 : 0)
                    .overlay {
                        if developing { developingSweep }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .animation(.easeOut(duration: 0.8), value: developing)
            }
        }
        .frame(maxWidth: 300, maxHeight: 300)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Accent.amber.opacity(developing ? 0.5 : 0.18), lineWidth: 1)
        }
        .scaleEffect(settled ? 1 : 0.97)
        .shadow(color: .black.opacity(0.6), radius: 26, y: 12)
    }

    /// The line travelling down the print. Deliberately soft — a hard edge reads
    /// as a scanner, not a bath.
    private var developingSweep: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, Accent.amber.opacity(0.34), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: geo.size.height * 0.42)
            .offset(y: -geo.size.height * 0.42 + sweep * geo.size.height * 1.42)
            .blur(radius: 8)
        }
        .allowsHitTesting(false)
    }

    private var caption: some View {
        VStack(spacing: 9) {
            switch phase {
            case .developing:
                ProgressView()
                    .tint(Accent.amber)
                Text("DEVELOPING")
                    .font(.mono(9, .semibold))
                    .kerning(3)
                    .foregroundStyle(Tone.secondary)
            case .done(let message):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Accent.amber)
                Text(message.uppercased())
                    .font(.mono(9, .semibold))
                    .kerning(2)
                    .foregroundStyle(Tone.secondary)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(hex: 0xE2685A))
                Text(message)
                    .font(.ui(13, .medium))
                    .foregroundStyle(Tone.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: phase)
    }

    private var developing: Bool {
        if case .developing = phase { return true }
        return false
    }
}
