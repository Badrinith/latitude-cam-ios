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

    private var face: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x2C2924))
                .overlay { knurling }
                .overlay {
                    Circle().strokeBorder(Ink.base, lineWidth: diameter > 60 ? 3 : 2)
                }
                // The focus ring sits inside the dial's own bounds rather than
                // haloing them: the plate clips, and a glow spilling past the
                // metal would be sheared off at its edge.
                .overlay {
                    Circle()
                        .strokeBorder(Accent.amber.opacity(pressing ? 0.9 : 0), lineWidth: 1.5)
                        .padding(diameter > 60 ? 4 : 3)
                }
                .shadow(color: .black.opacity(pressing ? 0.75 : (diameter > 60 ? 0.6 : 0.5)),
                        radius: pressing ? 10 : (diameter > 60 ? 3 : 2),
                        y: pressing ? 6 : 2)

            Capsule()
                .fill(Accent.amber)
                .frame(width: diameter > 60 ? 3 : 2, height: diameter > 60 ? 12 : 8)
                .offset(y: -diameter / 2 + (diameter > 60 ? 9 : 6))
                .rotationEffect(.degrees(KnobMath.pointerAngle(for: value)))

            if let text = compact ? (inlineReading ?? label) : inlineReading {
                Text(text)
                    .font(.mono(compact ? 8 : 9, .bold))
                    .foregroundStyle(Color(hex: 0xE8E2D4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: diameter * 0.82)
                    .rotationEffect(rotation)
            }
        }
        .frame(width: diameter, height: diameter)
        // The two smallest dials are 44pt — right on Apple's minimum, and these
        // are turned rather than tapped, so the hit area is grown past the face.
        .frame(width: max(diameter, 52), height: max(diameter, 52))
        .contentShape(Circle())
        .gesture(turn)
    }

    /// Alternating wedges, the handoff's 4° ridges.
    private var knurling: some View {
        ZStack {
            ForEach(0..<45, id: \.self) { i in
                Path { path in
                    path.move(to: CGPoint(x: diameter / 2, y: diameter / 2))
                    path.addArc(
                        center: CGPoint(x: diameter / 2, y: diameter / 2),
                        radius: diameter / 2,
                        startAngle: .degrees(Double(i) * 8),
                        endAngle: .degrees(Double(i) * 8 + 4),
                        clockwise: false
                    )
                }
                .fill(Color(hex: 0x4A453C))
            }
        }
        .frame(width: diameter, height: diameter)
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

            Text(dial.reading)
                .font(.mono(13, .bold))
                .foregroundStyle(Tone.primary)
                .rotationEffect(rotation)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Ink.base.opacity(0.8))
                }
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
                    defer { lastX = drag.location.x }
                    guard let previous = lastX else { return }
                    // 260pt of travel covers the range: long enough that a stop
                    // is a deliberate movement, short enough to cross the whole
                    // ladder without lifting a thumb.
                    onScrub(Double(drag.location.x - previous) / 260)
                }
                .onEnded { _ in lastX = nil }
        )
        .accessibilityLabel(dial.name)
        .accessibilityValue(dial.reading)
    }
}

/// The film-stock carousel: glass rather than a solid card, so the picture reads
/// through it. Swiping steps stock by stock with a detent each time.
struct FilmCardStack: View {
    @EnvironmentObject var app: AppState
    var rotation: Angle = .zero
    /// Turned, the strip sits on the ground-facing edge and its lettering comes
    /// up the other way — so the names take an extra half turn to face the
    /// reader. The cards themselves keep the plain rotation; it is only the
    /// text that was upside down.
    var invertNames: Bool = false
    var onOpen: () -> Void

    private var nameRotation: Angle {
        invertNames ? rotation + .degrees(180) : rotation
    }

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
                .rotationEffect(nameRotation)
        }
        .contentShape(Rectangle())
        .onTapGesture { Haptics.tap(); onOpen() }
        .gesture(swipe)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: app.selectedFilm)
    }

    /// Horizontal only, and only when the drag is clearly horizontal — a
    /// vertical component belongs to the system edge gestures, not to us.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let step = value.translation.width - drag
                if abs(step) > 46 {
                    drag = value.translation.width
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
        .rotationEffect(rotation)
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
                    .rotationEffect(invertNames ? .degrees(180) : .zero)
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
            .rotationEffect(rotation)
        } else {
            Color.clear.frame(width: 40, height: 58)
        }
    }
}

/// The focal-length selector, in the handoff's glass-pill material. It takes the
/// slot the reference fills with a "VIDEO" placeholder — a real lens outranks a
/// stand-in for a mode that does not exist yet.
///
/// The front camera is one of the focal lengths rather than a switch somewhere
/// else on the body. That is what it physically is: another lens pointing the
/// other way, and choosing it is the same decision as choosing between 1× and
/// 2× — "which lens am I shooting through".
struct PlateLensRow: View {
    @ObservedObject var camera: CameraManager
    var selected: String
    var usingFront: Bool
    var rotation: Angle = .zero
    var onSelect: (CameraManager.Lens) -> Void
    var onSelectFront: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(camera.lenses) { lens in
                item(label: lens.label,
                     active: !usingFront && lens.id == selected,
                     accessibility: "\(lens.label) lens") {
                    if usingFront { onSelectFront() } else { onSelect(lens) }
                }
            }

            Rectangle()
                .fill(Tone.hairline)
                .frame(width: 0.5, height: 18)
                .padding(.horizontal, 3)

            item(label: nil, symbol: "person.fill",
                 active: usingFront,
                 accessibility: usingFront ? "Front camera, selected" : "Front camera",
                 action: onSelectFront)
        }
        .padding(4)
        .background { Capsule().fill(Color.black.opacity(0.45)) }
        .background { Capsule().fill(.ultraThinMaterial) }
        .animation(.snappy(duration: 0.22), value: usingFront)
        .animation(.snappy(duration: 0.22), value: selected)
    }

    private func item(
        label: String? = nil, symbol: String? = nil,
        active: Bool, accessibility: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.detent()
            action()
        } label: {
            Group {
                if let label {
                    Text(label).font(.mono(10, .semibold))
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(active ? Accent.amber : Tone.primary.opacity(0.7))
            .rotationEffect(rotation)
            .frame(minWidth: 34, minHeight: 28)
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .background {
                if active { Capsule().fill(Accent.amber.opacity(0.22)).padding(.vertical, 8) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
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

    /// Open, with all five dials showing.
    static let height: CGFloat = 222
    /// Closed — the switch strip alone. No dials, because with PRO off the
    /// camera is on auto and every one of them would read AUTO: a control that
    /// displays a value it is not setting is worse than no control, and it was
    /// costing the frame 70pt to say so.
    static let collapsedHeight: CGFloat = 108

    static func height(proOpen: Bool) -> CGFloat { proOpen ? height : collapsedHeight }

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
            LinearGradient(colors: [Color(hex: 0x302D28), Color(hex: 0x1C1A17)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(hex: 0x0A0A0A)).frame(height: 2)
                }

            VStack(spacing: 0) {
                utilities.padding(.top, 46)

                if app.proMode {
                    dials
                        .padding(.top, 8)
                        .padding(.horizontal, 6)
                        .transition(.opacity.combined(with: .offset(y: -14)))
                }
            }
        }
        .frame(height: Self.height(proOpen: app.proMode))
        .frame(maxWidth: .infinity)
        .clipped()
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

            // Only while the dials are out. With PRO off there is nothing
            // manual set, so there is nothing to put back.
            if app.proMode {
                utility(systemImage: "arrow.counterclockwise", on: false,
                        label: "Reset controls") {
                    app.resetControls()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
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
            // 54 square. Bigger than the handoff's 28 in both directions, and
            // square so a rotated glyph never outgrows its own button.
            .frame(width: 54, height: 54)
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

    private var dials: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Group {
                PlateDial(label: AppState.apertureLabels[app.apertureIndex],
                          barrelKey: .aperture, barrelName: "APERTURE",
                          barrelReading: AppState.apertureLabels[app.apertureIndex],
                          value: apertureBinding,
                          stops: AppState.apertureStops.count,
                          diameter: 44, rotation: rotation, compact: compact,
                          receded: receded(.aperture), onTurn: onDialTurn,
                          onFocusChange: focus(.aperture))

                PlateDial(label: app.isoLabel,
                          barrelKey: .iso, barrelName: "ISO", barrelReading: app.isoLabel,
                          value: $app.iso,
                          stops: AppState.isoStops.count,
                          diameter: 50, rotation: rotation, compact: compact,
                          receded: receded(.iso), onTurn: onDialTurn,
                          onFocusChange: focus(.iso),
                          onEngage: { app.autoExposure = false })

                PlateDial(label: "SHUTTER", inlineReading: app.shutterLabel,
                          barrelKey: .shutter, barrelName: "SHUTTER", barrelReading: app.shutterLabel,
                          value: $app.shutter, stops: AppState.shutterStops.count,
                          diameter: 70, highlighted: true, rotation: rotation,
                          compact: compact, receded: receded(.shutter), onTurn: onDialTurn,
                          onFocusChange: focus(.shutter),
                          onEngage: { app.autoExposure = false })

                PlateDial(label: app.kelvinLabel,
                          barrelKey: .white, barrelName: "WHITE BALANCE", barrelReading: app.kelvinLabel,
                          value: $app.whiteBalance,
                          stops: AppState.whiteBalanceStops.count,
                          diameter: 50, rotation: rotation, compact: compact,
                          receded: receded(.white), onTurn: onDialTurn,
                          onFocusChange: focus(.white))

                PlateDial(label: String(format: "%+.1fEV", app.evValue),
                          barrelKey: .exposure, barrelName: "EXPOSURE",
                          barrelReading: String(format: "%+.1f EV", app.evValue),
                          value: $app.exposureComp, stops: AppState.evDetents,
                          diameter: 44, rotation: rotation, compact: compact,
                          receded: receded(.exposure), onTurn: onDialTurn,
                          onFocusChange: focus(.exposure))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Everything below the plate: the HUD chips, the film carousel (or the pro
/// barrels in its place), the focal-length row, and the bottom bar.
///
/// PRO is not down here any more — it moved to the plate, where it belongs with
/// the instruments it reveals.
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

    var body: some View {
        VStack(spacing: 0) {
            // Turned, the instruments go on a rotated band at the sky edge —
            // laid out horizontally inside it and rotated as one piece. Rotating
            // each readout inside a portrait-shaped frame is what clipped the
            // meter to ".8 0" and lapped it over the zoom.
            if !landscape { hud }
            Spacer(minLength: 0)

            // Portrait keeps film in the stack with everything else.
            if !landscape { filmBand }

            lensRow.padding(.bottom, 10)
            bottomBar.padding(.bottom, 30)
        }
        // Landscape film is not drawn here at all. Pinned to .bottom it landed
        // on the shutter — the release lives at that edge too. Turned, "the
        // bottom" is a different edge of the glass entirely, so the screen
        // places it against the one actually facing the ground.
    }

    /// Film, always. The barrel cluster used to take this band whenever PRO was
    /// on, but PRO now reveals the dials on the plate — which drive the same
    /// four values. Two sets of controls for one set of numbers is one set too
    /// many, so the cluster is gone from here and film keeps the band.
    private var filmBand: some View {
        FilmCardStack(rotation: rotation, invertNames: landscape, onOpen: onFilmSim)
            .padding(.bottom, 14)
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
            CameraStatusPill(camera: camera)
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

            HStack {
                // Back where it was. Its job is now the plate: on, and all five
                // dials come down; off, and the shutter dial holds the fort.
                Button {
                    Haptics.toggle()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                        app.proMode.toggle()
                    }
                } label: {
                    Text("PRO")
                        .font(.mono(12, .bold))
                        .kerning(0.9)
                        .foregroundStyle(app.proMode ? Ink.base : Tone.secondary)
                        .rotationEffect(rotation)
                        .frame(width: 62, height: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(app.proMode ? Accent.amber : Color.white.opacity(0.07))
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pro controls")

                Spacer(minLength: 0)

                Button { onLibrary() } label: {
                    LibraryThumbnail(gallery: app.gallery)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Library")
            }
            .padding(.horizontal, 26)
        }
        .frame(height: 78)
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
