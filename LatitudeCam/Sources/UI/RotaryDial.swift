//
//  RotaryDial.swift
//  LatitudeCam
//
//  A top-plate control dial. Engraved values turn around a milled rim under a
//  fixed red index, the way a Fuji shutter dial or a Leica speed dial reads.
//
//  Both bodies put an A at the end of the scale: hand the exposure back to the
//  camera by turning past the last marked stop. That position is kept here.
//

import SwiftUI

struct RotaryDial: View {
    var label: String
    /// Engraved values, in order. Index 0 is the A position when `hasAuto`.
    var values: [String]
    @Binding var index: Int
    /// Turning past the first stop reaches A.
    var hasAuto = false
    /// The stop that means "no adjustment", marked so it can be found by feel.
    var neutralIndex: Int?
    var highlighted = false

    @State private var dragStart: Int?
    @State private var spin: Double = 0

    private let size: CGFloat = 132
    private let pointsPerStop: CGFloat = 46
    /// Degrees between engraved values. Wide enough that "1/125" clears its
    /// neighbours at this radius — at 30° the shutter scale ran together into an
    /// unreadable band.
    private let pitch: Double = 46
    /// Only the stops either side of the index are engraved. A real dial shows
    /// you the value under the mark and hints at what is next, not the whole scale.
    private let engravedSweep: Double = 50

    private var clamped: Int { min(max(index, 0), max(0, values.count - 1)) }
    private var isAuto: Bool { hasAuto && clamped == 0 }

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                plate
                engravings
                indexMark
                centre
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(turn)

            Text(label.uppercased())
                .font(.mono(9, .semibold))
                .kerning(1.2)
                .foregroundStyle(highlighted ? Accent.amber : Tone.quaternary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(values.indices.contains(clamped) ? values[clamped] : "")
        .accessibilityAdjustableAction { direction in
            select(clamped + (direction == .increment ? 1 : -1))
        }
    }

    // MARK: - The dial itself

    /// Brushed top plate with a milled edge — the knurl is what makes it read as
    /// something you grip rather than a circle with numbers on it.
    private var plate: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(hex: 0x2A2A2C), Color(hex: 0x151517),
                            Color(hex: 0x323235), Color(hex: 0x141416),
                            Color(hex: 0x2A2A2C)
                        ],
                        center: .center
                    )
                )

            Canvas { context, canvasSize in
                let hub = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let outer = canvasSize.width / 2
                var tick = 0.0
                while tick < 360 {
                    let radians = (tick - 90 + spin) * .pi / 180
                    var mark = Path()
                    mark.move(to: CGPoint(
                        x: hub.x + (outer - 7) * CGFloat(cos(radians)),
                        y: hub.y + (outer - 7) * CGFloat(sin(radians))
                    ))
                    mark.addLine(to: CGPoint(
                        x: hub.x + outer * CGFloat(cos(radians)),
                        y: hub.y + outer * CGFloat(sin(radians))
                    ))
                    context.stroke(mark, with: .color(.white.opacity(0.13)), lineWidth: 1)
                    tick += 4.5
                }
            }

            Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
    }

    private var engravings: some View {
        GeometryReader { geo in
            let hub = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = geo.size.width / 2 - 19

            ForEach(values.indices, id: \.self) { slot in
                let angle = Double(slot - clamped) * pitch
                if abs(angle) <= engravedSweep {
                    Text(values[slot])
                        .font(.mono(slot == clamped ? 11 : 9, slot == clamped ? .bold : .medium))
                        .foregroundStyle(engravingColour(slot))
                        .rotationEffect(.degrees(angle))
                        .position(
                            x: hub.x + radius * CGFloat(sin(angle * .pi / 180)),
                            y: hub.y - radius * CGFloat(cos(angle * .pi / 180))
                        )
                        .opacity(max(0.3, cos(angle * .pi / 180)))
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: clamped)
    }

    private func engravingColour(_ slot: Int) -> Color {
        if slot == clamped { return Accent.amber }
        if slot == neutralIndex { return Tone.secondary }
        if hasAuto && slot == 0 { return Tone.secondary }
        return Color(hex: 0xC9C2B6).opacity(0.55)
    }

    /// Leica paints its index red. Amber is this app's equivalent, and keeping it
    /// outside the plate means it never fights the engraving underneath.
    private var indexMark: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Accent.amber)
                .frame(width: 9, height: 6)
            Spacer(minLength: 0)
        }
        .frame(height: size)
    }

    private var centre: some View {
        VStack(spacing: 2) {
            Text(values.indices.contains(clamped) ? values[clamped] : "—")
                .font(.mono(isAuto ? 20 : 17, .bold))
                .foregroundStyle(isAuto ? Accent.amber : Tone.primary)
                .contentTransition(.numericText())

            if isAuto {
                Text("AUTO")
                    .font(.mono(7, .semibold))
                    .kerning(1.4)
                    .foregroundStyle(Tone.quaternary)
            }
        }
        .frame(width: size - 54, height: size - 54)
        .background(
            Circle().fill(
                RadialGradient(
                    colors: [Color(hex: 0x1C1C1E), Color(hex: 0x0E0E10)],
                    center: .init(x: 0.5, y: 0.35), startRadius: 2, endRadius: size / 2
                )
            )
        )
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        }
    }

    // MARK: - Turning

    private var turn: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = clamped
                    Haptics.prepare()
                }
                let from = dragStart ?? clamped
                let raw = CGFloat(from) - value.translation.width / pointsPerStop
                let target = min(max(Int(raw.rounded()), 0), values.count - 1)

                if target != clamped {
                    Haptics.detent()
                    index = target
                    spin += Double(target - clamped) * pitch
                } else if Int(raw.rounded()) != target {
                    // Ran into the end of the scale.
                    reportEndOfTravel()
                }
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Dials used to stop dead at either end with no signal. A soft double tick
    /// says "that is as far as it goes" without looking down.
    @State private var lastEndTick = Date.distantPast
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { index = target }
    }
}
