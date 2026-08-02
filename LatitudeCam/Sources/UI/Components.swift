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

// MARK: - Rule-of-thirds grid

struct ThirdsGrid: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1...2 {
                    let x = geo.size.width / 3 * CGFloat(i)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))

                    let y = geo.size.height / 3 * CGFloat(i)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
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

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.ui(12, .medium))
                    .foregroundStyle(Tone.secondary)
                Spacer()
                Text(value)
                    .font(.mono(12, .semibold))
                    .foregroundStyle(Accent.amber)
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

                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .offset(x: (w * position) - 8)
                }
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { position = min(max(0, $0.location.x / w), 1) }
                )
            }
            .frame(height: 16)
        }
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

// MARK: - Toggle row

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
            withAnimation(.snappy(duration: 0.2)) { isOn.toggle() }
        }
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
        Button(action: action) {
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
