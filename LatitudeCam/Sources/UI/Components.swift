//
//  Components.swift
//  LatitudeCam
//
//  Shared building blocks: the Latitude mark, glass chrome, sliders, chips.
//

import SwiftUI

// MARK: - Latitude mark
//
// The "L" monogram: a cream vertical stroke, a light-to-amber foot, and a small
// lens glyph at the joint. Drawn as vectors so it stays crisp at every size the
// design calls for (96pt on launch, 56pt on onboarding/login).

struct LatitudeMark: View {
    var size: CGFloat
    /// Base metrics are authored against the 96pt launch-screen mark.
    private var s: CGFloat { size / 96 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                .fill(Ink.raised)
                .overlay(
                    RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )

            // Vertical stroke
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(Tone.primary)
                .frame(width: 12 * s, height: 51 * s)
                .offset(x: 30 * s, y: 20 * s)

            // Foot stroke, cream → amber
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Tone.primary, location: 0),
                            .init(color: Accent.amber, location: 0.7),
                            .init(color: Accent.amberDeep, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 37 * s, height: 12 * s)
                .offset(x: 30 * s, y: 61 * s)

            // Lens glyph — ring with a knocked-out halo so it reads over the foot
            ZStack {
                Circle()
                    .fill(Ink.raised)
                    .frame(width: 19 * s, height: 19 * s)
                Circle()
                    .strokeBorder(Accent.amber, lineWidth: 2 * s)
                    .background(Circle().fill(Ink.raised))
                    .frame(width: 14 * s, height: 14 * s)
                Circle()
                    .fill(Accent.amber)
                    .frame(width: 5 * s, height: 5 * s)
            }
            .offset(x: 43.5 * s, y: 51.5 * s)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Stripe placeholder
//
// Stands in for the camera feed and photo thumbnails until real capture lands,
// matching the handoff's `repeating-linear-gradient(115deg, …)` placeholders.

struct StripePattern: View {
    var base: Color
    var stripe: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))

            // 115° gradient axis ⇒ stripes lean ~25° off vertical.
            let lean = size.height * 0.466
            var x = -lean
            while x < size.width + lean {
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height))
                line.addLine(to: CGPoint(x: x + lean, y: 0))
                context.stroke(line, with: .color(stripe), lineWidth: 2)
                x += 4
            }
        }
        .drawingGroup()
    }

    static var viewfinder: StripePattern {
        .init(base: Color(hex: 0x151515), stripe: Color(hex: 0x1A1A1A))
    }

    // Stripe deltas run slightly wider than the design's hex pairs; at the
    // handoff's exact values the texture washes out to a flat slab on-device.
    static var photo: StripePattern {
        .init(base: Color(hex: 0x242424), stripe: Color(hex: 0x30302F))
    }

    static var warmPhoto: StripePattern {
        .init(base: Color(hex: 0x221A12), stripe: Color(hex: 0x2E2318))
    }

    static var thumbnail: StripePattern {
        .init(base: Color(hex: 0x2A2A2A), stripe: Color(hex: 0x383838))
    }
}

// MARK: - Glass chrome

struct GlassBackground: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            // A flat black tint would vanish against the dark viewfinder, so the
            // chrome leans on the material and a hairline to stay legible over
            // both the placeholder and a real (bright) camera feed.
            .background(.ultraThinMaterial, in: shape)
            .background(Color.black.opacity(0.2), in: shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5) }
            .clipShape(shape)
    }
}

extension View {
    func glass(radius: CGFloat = 8) -> some View {
        modifier(GlassBackground(radius: radius))
    }
}

// MARK: - Composition grid

/// Draws whichever guide the Grid & Composition setting names. Both styles are
/// the same two-lines-per-axis shape, so they differ only in where the lines sit.
struct CompositionGrid: View {
    var style: String

    private var fractions: [CGFloat]? {
        switch style {
        case "Rule of Thirds": return [1.0 / 3.0, 2.0 / 3.0]
        case "Golden Ratio":   return [0.382, 0.618]
        default:               return nil   // Off
        }
    }

    var body: some View {
        GeometryReader { geo in
            if let fractions {
                Path { path in
                    for f in fractions {
                        let x = geo.size.width * f
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))

                        let y = geo.size.height * f
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}


// MARK: - Slider row

struct SliderRow: View {
    var label: String
    var value: String
    @Binding var position: Double
    /// Blue → white → amber track used by white balance.
    var temperatureTrack = false
    /// Exposure compensation: centre tick, and fill runs out from zero.
    var bipolar = false
    /// Number of click-stops engraved on the track. 0 leaves it smooth.
    var detents: Int = 0
    /// Parks the thumb on the stop rather than between stops. True wherever the
    /// underlying value is quantised, so the thumb never claims a precision the
    /// reading does not have.
    var snaps = false
    /// Draws attention to the control the user tapped in the viewfinder HUD.
    var highlighted = false

    @State private var lastDetent: Int?
    @State private var crossedCentre: Bool?

    /// The stop a position falls in. Matches AppState.stop(), so a click can
    /// never fire without the underlying value also changing.
    static func detentIndex(position: Double, detents: Int) -> Int {
        guard detents > 0 else { return 0 }
        return min(detents - 1, max(0, Int(position * Double(detents))))
    }

    /// The centre of a stop's band — where a detented thumb rests.
    static func detentCentre(index: Int, detents: Int) -> Double {
        guard detents > 0 else { return 0 }
        return (Double(index) + 0.5) / Double(detents)
    }

    private var trackHeight: CGFloat { detents > 0 ? 22 : 16 }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.ui(12, .medium))
                    .foregroundStyle(highlighted ? Accent.amber : Tone.secondary)
                Spacer()
                Text(value)
                    .font(.mono(12, .semibold))
                    .foregroundStyle(Accent.amber)
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackFill)
                        .frame(height: 4)

                    if bipolar {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 1, height: 12)
                            .offset(x: w / 2)

                        // Fill spans from the zero tick out to the thumb.
                        Capsule()
                            .fill(Accent.amber)
                            .frame(width: abs(position - 0.5) * w, height: 4)
                            .offset(x: min(position, 0.5) * w)
                    } else if !temperatureTrack {
                        Capsule()
                            .fill(Accent.amber)
                            .frame(width: max(0, w * position), height: 4)
                    }

                    // Stops engraved below the track, the way they are on a ring.
                    if detents > 0 {
                        ForEach(0..<detents, id: \.self) { i in
                            let active = i == Self.detentIndex(position: position, detents: detents)
                            Rectangle()
                                .fill(active ? Accent.amber : Color.white.opacity(0.22))
                                .frame(width: 1, height: active ? 7 : 4)
                                .offset(
                                    x: (CGFloat(i) + 0.5) / CGFloat(detents) * w,
                                    y: 11
                                )
                        }
                    }

                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .offset(x: (w * position) - 8)
                }
                .frame(height: trackHeight, alignment: .top)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let raw = min(max(0, drag.location.x / w), 1)
                            if lastDetent == nil { Haptics.prepare() }
                            report(raw)
                            position = resolve(raw)
                        }
                        .onEnded { _ in
                            lastDetent = nil
                            crossedCentre = nil
                        }
                )
            }
            .frame(height: trackHeight)
        }
    }

    /// Clicks once per stop crossed. A bipolar slider with no stops still marks
    /// the neutral point, which is the one place on that track worth finding
    /// without looking.
    private func report(_ next: Double) {
        if detents > 0 {
            let index = Self.detentIndex(position: next, detents: detents)
            if index != lastDetent {
                if lastDetent != nil { Haptics.detent() }
                lastDetent = index
            }
        } else if bipolar {
            let past = next >= 0.5
            if past != crossedCentre {
                if crossedCentre != nil { Haptics.detent() }
                crossedCentre = past
            }
        }
    }

    private func resolve(_ raw: Double) -> Double {
        guard snaps, detents > 0 else { return raw }
        return Self.detentCentre(
            index: Self.detentIndex(position: raw, detents: detents), detents: detents
        )
    }

    private var trackFill: AnyShapeStyle {
        if temperatureTrack {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: 0x5A8FD6), Tone.primary, Color(hex: 0xD9A55C)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(0.15))
    }
}

// MARK: - Command dial
//
// A milled barrel with the values engraved on it, turning under a fixed index —
// the way an X-series command dial reads. A slider can sit anywhere along its
// track, which is the wrong promise for a control whose value only ever lands on
// a stop. Here the value under the index *is* the setting, and every stop costs
// one click of the finger.

struct DialRow: View {
    var label: String
    var values: [String]
    @Binding var index: Int
    /// Draws attention to the control the user tapped in the viewfinder HUD.
    var highlighted = false
    /// The stop that means "no adjustment" — marked so it can be found by feel.
    var neutralIndex: Int?

    @State private var dragOffset: CGFloat = 0
    @State private var dragStart: Int?

    private let pitch: CGFloat = 68
    private let barrel: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.ui(12, .medium))
                .foregroundStyle(highlighted ? Accent.amber : Tone.secondary)

            ZStack {
                barrelFace

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(values.indices, id: \.self) { position in
                            stop(position)
                                .frame(width: pitch)
                                .contentShape(Rectangle())
                                .onTapGesture { select(position) }
                        }
                    }
                    .offset(x: geo.size.width / 2 - (CGFloat(clamped) + 0.5) * pitch + dragOffset)
                    .frame(height: geo.size.height, alignment: .center)
                }
                .frame(height: barrel)
                .clipped()
                .mask(edgeFade)

                indexMark
            }
            .frame(height: barrel)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(highlighted ? Accent.amber.opacity(0.5) : Tone.hairline, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
            .gesture(turn)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(values.indices.contains(clamped) ? values[clamped] : "")
        .accessibilityAdjustableAction { direction in
            select(clamped + (direction == .increment ? 1 : -1))
        }
    }

    private var clamped: Int { min(max(index, 0), max(0, values.count - 1)) }

    /// Vertical shading plus fine knurling — the barrel has to read as a turned
    /// cylinder, or the values look like they are printed on a flat card.
    private var barrelFace: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.62), Color.white.opacity(0.05), Color.black.opacity(0.62)],
                startPoint: .top, endPoint: .bottom
            )
            Canvas { context, size in
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)),
                        with: .color(.white.opacity(0.05))
                    )
                    x += 4
                }
            }
        }
        .background(Ink.card)
    }

    private func stop(_ position: Int) -> some View {
        let current = position == clamped
        let neutral = position == neutralIndex
        return VStack(spacing: 4) {
            Text(values[position])
                .font(.mono(current ? 15 : 12, current ? .bold : .medium))
                .foregroundStyle(current ? Accent.amber : Tone.quaternary)
                .lineLimit(1)
                .fixedSize()

            Rectangle()
                .fill(current ? Accent.amber : (neutral ? Tone.secondary : Color.white.opacity(0.22)))
                .frame(width: current || neutral ? 1.5 : 1, height: current ? 9 : neutral ? 7 : 5)
        }
        .animation(.snappy(duration: 0.16), value: current)
    }

    private var indexMark: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Accent.amber)
                .frame(width: 9, height: 5)
            Spacer(minLength: 0)
        }
        .frame(height: barrel)
    }

    private var edgeFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var turn: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = clamped
                    Haptics.prepare()
                }
                let start = dragStart ?? clamped
                let raw = CGFloat(start) - value.translation.width / pitch
                let target = min(max(Int(raw.rounded()), 0), values.count - 1)

                if target != clamped {
                    Haptics.detent()
                    index = target
                }
                // Track the finger between stops so the barrel feels held.
                dragOffset = value.translation.width + CGFloat(target - start) * pitch
            }
            .onEnded { _ in
                dragStart = nil
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) { dragOffset = 0 }
            }
    }

    private func select(_ position: Int) {
        let target = min(max(position, 0), values.count - 1)
        guard target != clamped else { return }
        Haptics.detent()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) { index = target }
    }
}

// MARK: - Toggle row

/// A row of mutually exclusive chips. Plain buttons rather than a Menu — a Menu
/// inside the bottom sheet swallowed the taps that were meant to open it.
struct ChipRow: View {
    var label: String
    var options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.ui(13, .medium))
                .foregroundStyle(Tone.primary)

            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let active = option == selection
                    Button {
                        guard !active else { return }
                        Haptics.detent()
                        selection = option
                    } label: {
                        Text(option)
                            .font(.mono(11, .medium))
                            .foregroundStyle(active ? Ink.base : Tone.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(
                                active ? Accent.amber : Color.white.opacity(0.08),
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Tone.separator).frame(height: 0.5)
        }
    }
}

struct ToggleRow: View {
    var label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.ui(13, .medium))
                .foregroundStyle(Tone.primary)
            Spacer()
            Capsule()
                .fill(isOn ? Accent.amber : Color.white.opacity(0.15))
                .frame(width: 44, height: 26)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .padding(2)
                }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Tone.separator).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.toggle()
            withAnimation(.snappy(duration: 0.2)) { isOn.toggle() }
        }
    }
}

// MARK: - Shutter release
//
// The disc sinks under the finger the way a real release travels before it
// trips. Paired with the heaviest haptic in the app, the press is legible
// without looking away from the frame.

/// A leaf iris that closes and reopens on every exposure.
///
/// The blades do the thing the button triggers rather than depicting it. The
/// meter reading used to sit in the opening; at 76pt across, with blades taking
/// the outer third, there was never enough clear aperture to set two lines of
/// type in. It lives at the top of the screen now, where it has room.
struct ShutterButton: View {
    var action: () -> Void

    /// 0 fully open, 1 fully closed.
    @State private var closure: CGFloat = 0
    @State private var pressed = false

    private let size: CGFloat = 76
    /// Blades overhang the frame so their outer corners stay clipped away rather
    /// than showing as a hexagon when the iris is open.
    private var petal: CGFloat { size * 1.06 }

    var body: some View {
        Button {
            actuate()
            action()
        } label: {
            ZStack {
                core
                blades
            }
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2.5)
            }
            .scaleEffect(pressed ? 0.94 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Take photo")
    }

    // MARK: Parts

    private var core: some View {
        Circle().fill(
            RadialGradient(
                colors: [Color(hex: 0xFFFFFF), Color(hex: 0xDCD7CE)],
                center: .init(x: 0.5, y: 0.32), startRadius: 1, endRadius: size * 0.7
            )
        )
    }

    private var blades: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x3C3C42), Color(hex: 0x17171A)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                    }
                    .frame(width: petal, height: petal)
                    // Swept out past the rim when open, drawn in over the centre
                    // when closed. The slight y offset is what gives the blades
                    // their overlap rather than meeting edge to edge.
                    .offset(x: bladeOffset, y: -petal * 0.05)
                    .rotationEffect(.degrees(Double(index) * 60))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var bladeOffset: CGFloat {
        let open = size * 0.60
        let shut = size * 0.04
        return open + (shut - open) * closure
    }

    // MARK: Actuation

    /// Shut, hold, open — the timing of a leaf shutter rather than a button
    /// animation. Asymmetric on purpose: blades snap closed and ease open, which
    /// is how the real thing sounds and how it should feel.
    private func actuate() {
        pressed = true
        withAnimation(.easeIn(duration: 0.07)) { closure = 1 }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.17)) { closure = 0 }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { pressed = false }
        }
    }
}

// MARK: - Film ring
//
// The signature control: film names engraved on a barrel that turns under a
// fixed index mark, one detent per stock. A row of swatches would have been the
// obvious answer, but this is a camera — the thing you reach for without looking
// is a ring, and a ring tells you where you are by clicking.

struct FilmRing: View {
    var presets: [FilmPreset]
    @Binding var selection: FilmPreset
    var onOpenDetail: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var dragStart: Int?

    private let pitch: CGFloat = 116

    private var index: Int {
        presets.firstIndex(where: { $0.id == selection.id }) ?? 0
    }

    var body: some View {
        VStack(spacing: 5) {
            indexMark

            // GeometryReader takes the width it is given instead of the width of
            // the strip inside it. Without that the four stops measure ~464pt and
            // push the entire viewfinder chrome off both edges of the screen.
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(presets.enumerated()), id: \.element.id) { position, preset in
                        stop(preset, isCurrent: position == index)
                            .frame(width: pitch)
                            .contentShape(Rectangle())
                            .onTapGesture { select(position) }
                    }
                }
                .offset(x: geo.size.width / 2 - (CGFloat(index) + 0.5) * pitch + dragOffset)
                .frame(height: geo.size.height, alignment: .center)
            }
            .frame(height: 34)
            .clipped()
            .mask(barrelFade)
            .contentShape(Rectangle())
            .gesture(turn)

            Rectangle()
                .fill(Tone.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Film simulation")
        .accessibilityValue(selection.name)
        .accessibilityAdjustableAction { direction in
            select(index + (direction == .increment ? 1 : -1))
        }
    }

    private var indexMark: some View {
        ZStack {
            Triangle()
                .fill(Accent.amber)
                .frame(width: 7, height: 5)
        }
        .frame(height: 6)
    }

    private func stop(_ preset: FilmPreset, isCurrent: Bool) -> some View {
        VStack(spacing: 5) {
            Text(preset.name.uppercased())
                .font(.mono(isCurrent ? 11 : 10, isCurrent ? .bold : .medium))
                .kerning(isCurrent ? 1.1 : 0.6)
                .foregroundStyle(isCurrent ? Accent.amber : Tone.quaternary)
                .lineLimit(1)
                .fixedSize()

            Circle()
                .fill(preset.swatch)
                .frame(width: isCurrent ? 7 : 5, height: isCurrent ? 7 : 5)
                .overlay {
                    Circle().strokeBorder(
                        isCurrent ? Color.white.opacity(0.35) : .clear, lineWidth: 0.5
                    )
                }
        }
        .opacity(isCurrent ? 1 : 0.45)
        .animation(.snappy(duration: 0.18), value: isCurrent)
        .contentShape(Rectangle())
    }

    /// Names dissolve into the curve of the barrel rather than being cut off.
    private var barrelFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.22),
                .init(color: .black, location: 0.78),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var turn: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = index
                    Haptics.prepare()
                }
                let start = dragStart ?? index
                let raw = CGFloat(start) - value.translation.width / pitch
                let target = min(max(Int(raw.rounded()), 0), presets.count - 1)

                if target != index {
                    Haptics.detent()
                    selection = presets[target]
                }
                // Track the finger between detents so the barrel feels held.
                dragOffset = value.translation.width + CGFloat(target - start) * pitch
            }
            .onEnded { _ in
                dragStart = nil
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { dragOffset = 0 }
            }
    }

    private func select(_ position: Int) {
        let clamped = min(max(position, 0), presets.count - 1)
        guard clamped != index else {
            // Tapping the stock already under the index opens its full controls.
            Haptics.tap()
            onOpenDetail()
            return
        }
        Haptics.detent()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            selection = presets[clamped]
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Pill chip

struct Chip: View {
    var title: String
    var isActive: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(11, .semibold))
                .foregroundStyle(isActive ? Ink.raised : Tone.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isActive ? AnyShapeStyle(Accent.amber) : AnyShapeStyle(Color.white.opacity(0.1)))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FilterChip: View {
    var title: String
    var isActive: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(12, .semibold))
                .foregroundStyle(isActive ? Ink.raised : Tone.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(isActive ? AnyShapeStyle(Accent.amber) : AnyShapeStyle(Ink.card))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen header

struct BackLink: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text("‹ \(title)")
                .font(.ui(13, .semibold))
                .foregroundStyle(Accent.amber)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom sheet

struct BottomSheet<Content: View>: View {
    var onDismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                content
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
            .background(Ink.raised)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: -20)
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Screen navigation
//
// Every screen away from the viewfinder was returning through the same bare
// "‹ Viewfinder" in amber — correct, invisible, and identical whether you were
// leaving Settings or abandoning an edit. These give the return a shape: an iris
// closing back down to the finder, with the screen's own name beside it.

/// Returns to the camera. The glyph is the iris from the shutter release, small
/// and closed — going back to the viewfinder is the same idea as taking the
/// picture, so it uses the same object.
struct ViewfinderReturn: View {
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Accent.amber, lineWidth: 1.2)
                        .frame(width: 15, height: 15)
                    // Three strokes across the ring read as blades without needing
                    // six of them at this size.
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(Accent.amber)
                            .frame(width: 1.2, height: 7)
                            .offset(y: -3.4)
                            .rotationEffect(.degrees(Double(index) * 120))
                    }
                }
                Text("VIEWFINDER")
                    .font(.mono(9, .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Accent.amber)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(Accent.amber.opacity(0.12))
                    .overlay { Capsule().strokeBorder(Accent.amber.opacity(0.35), lineWidth: 0.5) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to viewfinder")
    }
}

/// A plain return to another screen in the app — the library, say. Deliberately
/// quieter than ViewfinderReturn: leaving the camera behind is the bigger move,
/// and the two should not compete.
struct ScreenReturn: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                Text(title.uppercased())
                    .font(.mono(9, .semibold))
                    .kerning(1)
            }
            .foregroundStyle(Tone.secondary)
            .padding(.vertical, 7)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A committing action — Save. Filled, so it reads as the end of something
/// rather than as one more control.
struct PrimaryAction: View {
    var title: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.success()
            action()
        } label: {
            Text(title.uppercased())
                .font(.mono(9.5, .bold))
                .kerning(1.1)
                .foregroundStyle(enabled ? Ink.base : Tone.quaternary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(enabled ? AnyShapeStyle(Accent.amber)
                                           : AnyShapeStyle(Color.white.opacity(0.08)))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// The header every screen away from the camera shares. A serif title, because
/// these are the reading screens — the camera is the instrument, these are the
/// notebook.
struct ScreenHeader<Trailing: View>: View {
    var title: String
    var leading: AnyView
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                leading
                Spacer()
                trailing
            }

            HStack {
                Text(title)
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(Tone.primary)
                Spacer()
            }
        }
    }
}
