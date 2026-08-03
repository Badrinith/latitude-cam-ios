//
//  FilmKnob.swift
//  LatitudeCam
//
//  The film selector: one frame of 35mm per stock, riding an arc centred on the
//  shutter. Each frame shows the live scene already developed through that film,
//  so you are choosing between four versions of the shot in front of you rather
//  than between four names.
//

import SwiftUI

struct FilmKnob: View {
    var presets: [FilmPreset]
    @Binding var selection: FilmPreset
    @ObservedObject var previews: FilmPreviewBuffer
    /// Frames already shot on each stock, printed in the rebate.
    var counts: [String: Int]
    var onOpenDetail: () -> Void
    /// Distance from the bottom of the deck to the shutter's centre. The shutter
    /// is the hub the roll turns around, so the two must agree exactly.
    var hubFromBottom: CGFloat = 59

    /// Continuous position in stops. Whole numbers sit on a detent.
    @State private var position: Double = 0
    @State private var velocity: Double = 0
    @State private var dragStart: Double?
    @State private var settled = true

    static let radius: CGFloat = 108
    static let pitch: Double = 42
    /// Narrow enough to hide the stock diametrically opposite the loaded one.
    /// A drum shows you its front and its shoulders, never its back — and with an
    /// even number of stocks, rendering that far one puts a lone frame on one
    /// side of the arc with nothing facing it.
    static let visibleSweep: Double = 55
    private let pointsPerStop: CGFloat = 90

    private var index: Int { presets.firstIndex { $0.id == selection.id } ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let hub = CGPoint(x: geo.size.width / 2, y: geo.size.height - hubFromBottom)

            ZStack {
                MilledRim(hub: hub, radius: Self.radius, pitch: Self.pitch, sweep: Self.visibleSweep)

                ForEach(Array(presets.enumerated()), id: \.element.id) { slot, preset in
                    let angle = Self.wrap(Double(slot) - position, count: presets.count) * Self.pitch
                    if abs(angle) <= Self.visibleSweep {
                        FilmFrame(
                            preset: preset,
                            thumbnail: previews.thumbnails[preset.id],
                            count: counts[preset.id] ?? 0,
                            isLoaded: abs(angle) < Self.pitch / 2
                        )
                        .scaleEffect(Self.scale(for: angle))
                        .rotationEffect(.degrees(Self.tilt(for: angle)))
                        .opacity(Self.opacity(for: angle))
                        .position(Self.point(hub: hub, angle: angle, radius: Self.radius))
                        .zIndex(100 - abs(angle))
                        .onTapGesture { turn(to: slot) }
                    }
                }

                Triangle()
                    .fill(Accent.amber)
                    .frame(width: 10, height: 6)
                    .position(Self.point(hub: hub, angle: 0, radius: Self.radius + 48))
            }
            .contentShape(Rectangle())
            .gesture(turnGesture)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Film simulation")
        .accessibilityValue(selection.name)
        .accessibilityAdjustableAction { direction in
            turn(to: index + (direction == .increment ? 1 : -1))
        }
        .onAppear { position = Double(index) }
        .onChange(of: selection.id) { _, _ in
            // Keeps the knob honest when the stock is changed from Film Sim.
            guard settled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                position = position + Self.wrap(Double(index) - position, count: presets.count)
            }
        }
    }

    // MARK: - Geometry

    /// Shortest signed distance around a loop of `count` stops.
    static func wrap(_ delta: Double, count: Int) -> Double {
        let n = Double(count)
        return (delta.truncatingRemainder(dividingBy: n) + n + n / 2)
            .truncatingRemainder(dividingBy: n) - n / 2
    }

    static func point(hub: CGPoint, angle: Double, radius: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: hub.x + radius * CGFloat(sin(radians)),
            y: hub.y - radius * CGFloat(cos(radians))
        )
    }

    static func scale(for angle: Double) -> CGFloat {
        CGFloat(max(0.6, 0.62 + 0.38 * cos(angle * .pi / 180)))
    }

    static func opacity(for angle: Double) -> Double {
        max(0.28, 0.32 + 0.68 * pow(max(cos(angle * .pi / 180), 0), 1.4))
    }

    /// Frames stay tangent to the arc instead of self-levelling — gondolas that
    /// do not correct. Capped so the rebate stays readable, and the loaded stock
    /// is always upright.
    static func tilt(for angle: Double) -> Double {
        min(max(angle * 0.6, -28), 28)
    }

    // MARK: - Turning

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = position
                    settled = false
                    Haptics.prepare()
                }
                let from = dragStart ?? position
                let next = from - Double(value.translation.width / pointsPerStop)
                report(crossing: next)
                position = next
                velocity = -Double(value.velocity.width / pointsPerStop) / 60
            }
            .onEnded { _ in
                dragStart = nil
                // Momentum carries the roll on, then the nearest detent takes it.
                let carried = position + velocity * 8
                turn(to: Int(carried.rounded()))
                velocity = 0
            }
    }

    /// Clicks once per stop crossed, in either direction.
    private func report(crossing next: Double) {
        if Int(next.rounded()) != Int(position.rounded()) { Haptics.detent() }
    }

    private func turn(to slot: Int) {
        let count = presets.count
        let resolved = ((slot % count) + count) % count

        if presets[resolved].id == selection.id && settled {
            // Tapping the loaded stock opens its full controls.
            Haptics.tap()
            onOpenDetail()
            return
        }

        Haptics.detent()
        settled = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            position = Double(slot)
        }
        selection = presets[resolved]
        // Renormalise after the spring so the position never drifts unbounded.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            position = Double(resolved)
            settled = true
        }
    }
}

// MARK: - One frame of 35mm

private struct FilmFrame: View {
    var preset: FilmPreset
    var thumbnail: UIImage?
    var count: Int
    var isLoaded: Bool

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                perforations
                window
                perforations
            }
            .padding(.vertical, 5)
            .frame(width: 56)
            .background(Color(hex: 0x0B0B0C))
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(
                        isLoaded ? Accent.amber : Color.white.opacity(0.13),
                        lineWidth: isLoaded ? 1.5 : 0.5
                    )
            }
            .shadow(color: .black.opacity(0.65), radius: 6, y: 3)

            // Edge printing: film carries its stock name and frame number in the
            // rebate, in this exact orange.
            Text(count > 0
                 ? "\(preset.shortName.uppercased()) · \(count)"
                 : preset.shortName.uppercased())
                .font(.mono(8, .semibold))
                .kerning(1.0)
                .foregroundStyle(isLoaded ? Accent.amber : Accent.amberDeep)
                .fixedSize()
        }
        .animation(.snappy(duration: 0.18), value: isLoaded)
    }

    private var perforations: some View {
        HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.black)
                    .frame(width: 4, height: 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 0.5)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    }
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 3)
    }

    /// The live scene developed through this stock. Falls back to the swatch
    /// before the first frame arrives, or when there is no camera at all.
    private var window: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                preset.swatch
            }
        }
        .frame(width: 48, height: 37)
        .clipped()
        .padding(.horizontal, 4)
    }
}

// MARK: - Rim

/// The knurl. A fine mark every 4° with a longer amber one at each stop, so the
/// arc reads as the milled edge of a knob rather than a drawn line.
private struct MilledRim: View {
    var hub: CGPoint
    var radius: CGFloat
    var pitch: Double
    var sweep: Double

    var body: some View {
        Canvas { context, _ in
            var track = Path()
            track.addArc(
                center: hub, radius: radius,
                startAngle: .degrees(-sweep - 90), endAngle: .degrees(sweep - 90),
                clockwise: false
            )
            context.stroke(track, with: .color(.white.opacity(0.11)), lineWidth: 1)

            var angle = -sweep
            while angle <= sweep {
                let onStop = abs(angle.truncatingRemainder(dividingBy: pitch)) < 2
                let length: CGFloat = onStop ? 8 : 3
                let inner = FilmKnob.point(hub: hub, angle: angle, radius: radius - length)
                let outer = FilmKnob.point(hub: hub, angle: angle, radius: radius + length)

                var mark = Path()
                mark.move(to: inner)
                mark.addLine(to: outer)
                context.stroke(
                    mark,
                    with: .color(onStop ? Accent.amber.opacity(0.5) : .white.opacity(0.16)),
                    lineWidth: 1
                )
                angle += 4
            }
        }
        .allowsHitTesting(false)
    }
}
