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
