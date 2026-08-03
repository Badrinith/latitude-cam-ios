//
//  SplashScreen.swift
//  LatitudeCam
//
//  One instrument doing three jobs: the leader's sweep hand counts, the aperture
//  performs every transition, and the film ring advances underneath. The ring is
//  the same detented object the viewfinder uses, so the sequence teaches the
//  gesture before the camera opens.
//

import SwiftUI

// MARK: - Content

struct SplashFeature: Identifiable {
    let id: String
    let title: String
    let caption: String
}

// MARK: - Director
//
// The sequence lives outside the view so its timing and haptic score can be
// tested, and so a tap can cancel it cleanly from anywhere.

@MainActor
final class SplashDirector: ObservableObject {

    @Published private(set) var step = 0
    @Published private(set) var irisOpen = false
    @Published private(set) var flooded = false
    @Published private(set) var showSkipHint = false
    @Published private(set) var isFinished = false

    /// Four, not six. At this pace a fifth beat gives each caption under a second
    /// — too short to actually read.
    static let features: [SplashFeature] = [
        .init(id: "exposure", title: "Manual Exposure",
              caption: "Shutter, ISO and white balance — every one on click stops"),
        .init(id: "film", title: "Film Simulations",
              caption: "Amber Stock, Slate, Rust and Mono, applied to the live feed"),
        .init(id: "histogram", title: "Live Histogram",
              caption: "Exposure and focus peaking read while you frame"),
        .init(id: "roll", title: "Your Roll",
              caption: "Edit freely — the original never leaves the roll")
    ]

    static let openDuration: Double = 1.35
    static let closeDuration: Double = 0.40
    static let outroDuration: Double = 1.00

    static var beatDuration: Double { openDuration + closeDuration }
    static var totalDuration: Double {
        Double(features.count) * beatDuration + outroDuration
    }

    private var run: Task<Void, Never>?
    private var onFinish: (() -> Void)?

    func start(reduceMotion: Bool, onFinish: @escaping () -> Void) {
        guard run == nil else { return }
        self.onFinish = onFinish

        // Reduced motion still gets the content, just not the machinery.
        guard !reduceMotion else {
            irisOpen = true
            run = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
            return
        }

        run = Task { [weak self] in
            guard let self else { return }

            for index in Self.features.indices {
                self.step = index
                withAnimation(.easeOut(duration: 0.42)) { self.irisOpen = true }
                // The first beat is an arrival; the rest are the ring advancing.
                if index == 0 { Haptics.tap() } else { Haptics.detent() }

                try? await Task.sleep(for: .seconds(Self.openDuration))
                guard !Task.isCancelled else { return }

                if index == 0 { self.showSkipHint = true }

                withAnimation(.easeIn(duration: 0.26)) { self.irisOpen = false }
                Haptics.detent()

                try? await Task.sleep(for: .seconds(Self.closeDuration))
                guard !Task.isCancelled else { return }
            }

            self.step = Self.features.count
            withAnimation(.easeOut(duration: 0.55)) {
                self.flooded = true
                self.irisOpen = true
            }
            Haptics.shutter()

            try? await Task.sleep(for: .seconds(Self.outroDuration))
            guard !Task.isCancelled else { return }
            self.finish()
        }
    }

    /// Tapping anywhere goes straight through. A splash you cannot dismiss stops
    /// being a welcome the second time you see it.
    func skip() {
        guard !isFinished else { return }
        Haptics.tap()
        finish()
    }

    private func finish() {
        run?.cancel()
        run = nil
        isFinished = true
        onFinish?()
        onFinish = nil
    }

    var isOutro: Bool { step >= Self.features.count }
    var currentFeature: SplashFeature? {
        Self.features.indices.contains(step) ? Self.features[step] : nil
    }
}

// MARK: - Aperture

/// A six-blade iris. `openness` above 1 clears the frame entirely, which is how
/// the sequence hands off to the app rather than cutting.
struct IrisAperture: Shape {
    var openness: Double

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // Half the shorter side, not the diagonal: at openness 1 the hexagon has
        // to sit inside its frame to read as an aperture. Using the diagonal made
        // it circumscribe the frame, which just looks like a square.
        let reach = min(rect.width, rect.height) / 2
        let radius = reach * max(0, openness)
        guard radius > 0.5 else { return path }

        for blade in 0..<6 {
            let angle = Double(blade) / 6 * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: centre.x + cos(angle) * radius,
                y: centre.y + sin(angle) * radius
            )
            if blade == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Screen

struct SplashScreen: View {
    var onFinish: () -> Void

    @StateObject private var director = SplashDirector()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false

    private let dialSize: CGFloat = 196
    private let irisSize: CGFloat = 164
    private let pitch: CGFloat = 200

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            crosshair
            instrument
            ring
            caption
            outro

            if director.showSkipHint && !director.isOutro {
                VStack {
                    Spacer()
                    Text("Tap to skip")
                        .font(.mono(9, .medium))
                        .kerning(0.14 * 9)
                        .foregroundStyle(Tone.quaternary)
                        .padding(.bottom, 34)
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { director.skip() }
        .animation(.easeInOut(duration: 0.3), value: director.showSkipHint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latitude. \(director.currentFeature?.title ?? "Shoot like film")")
        .accessibilityHint("Double tap to skip the introduction")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            sweeping = true
            director.start(reduceMotion: reduceMotion, onFinish: onFinish)
        }
    }

    // MARK: Leader framing

    private var crosshair: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geo.size.height * 0.42))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.42))
                path.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
            }
            .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
        .ignoresSafeArea()
        .opacity(director.isOutro ? 0 : 1)
        .animation(.easeOut(duration: 0.5), value: director.isOutro)
    }

    // MARK: The dial

    private var instrument: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    .frame(width: dialSize + 22, height: dialSize + 22)

                Circle()
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    .frame(width: dialSize, height: dialSize)

                // One revolution per feature, so the screen is visibly counting
                // toward the viewfinder rather than idling.
                Circle()
                    .fill(AngularGradient(
                        stops: [
                            .init(color: Accent.amber.opacity(0.45), location: 0),
                            .init(color: .clear, location: 0.13),
                            .init(color: .clear, location: 1)
                        ],
                        center: .center
                    ))
                    // A thin annulus riding just outside the aperture, so the
                    // hand sweeps the barrel rather than washing over the glyph.
                    .mask {
                        Circle()
                            .strokeBorder(Color.black, lineWidth: 13)
                            .frame(width: dialSize, height: dialSize)
                    }
                    .frame(width: dialSize, height: dialSize)
                    .rotationEffect(.degrees(sweeping ? 360 : 0))
                    .animation(
                        reduceMotion ? nil
                        : .linear(duration: SplashDirector.beatDuration).repeatForever(autoreverses: false),
                        value: sweeping
                    )
                    .opacity(director.isOutro ? 0 : 1)

                glyphWindow
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
        }
        .ignoresSafeArea()
    }

    /// The glyph is only ever seen through the aperture — the blades are the cut.
    private var glyphWindow: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0x2B2119), Color(hex: 0x100D0A)],
                center: .init(x: 0.5, y: 0.38), startRadius: 4, endRadius: irisSize * 0.8
            )

            if let feature = director.currentFeature {
                SplashGlyph(id: feature.id)
                    .frame(width: 64, height: 64)
                    .transition(.opacity)
            }
        }
        .frame(
            width: director.flooded ? nil : irisSize,
            height: director.flooded ? nil : irisSize
        )
        .modifier(FloodFrame(flooded: director.flooded))
        .mask {
            IrisAperture(openness: director.irisOpen ? (director.flooded ? 3.2 : 1) : 0)
                .frame(
                    width: director.flooded ? 1200 : irisSize,
                    height: director.flooded ? 2400 : irisSize
                )
        }
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                .frame(width: irisSize, height: irisSize)
                .opacity(director.flooded ? 0 : 1)
        }
    }

    // MARK: Film ring

    private var ring: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Triangle()
                    .fill(Accent.amber)
                    .frame(width: 10, height: 6)
                    .padding(.bottom, 8)

                HStack(spacing: 0) {
                    ForEach(Array(SplashDirector.features.enumerated()), id: \.element.id) { index, feature in
                        Text(feature.title.uppercased())
                            .font(.mono(10, .semibold))
                            .kerning(1.4)
                            .foregroundStyle(index == director.step ? Tone.primary : Tone.quaternary)
                            .frame(width: pitch)
                    }
                }
                .offset(x: geo.size.width / 2 - (CGFloat(min(director.step, SplashDirector.features.count - 1)) + 0.5) * pitch)
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.22),
                            .init(color: .black, location: 0.78),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .animation(.spring(response: 0.42, dampingFraction: 0.82), value: director.step)

                Rectangle()
                    .fill(Tone.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 34)
                    .padding(.top, 10)

                HStack(spacing: 7) {
                    ForEach(SplashDirector.features.indices, id: \.self) { index in
                        Circle()
                            .fill(index == director.step ? Accent.amber : Color.white.opacity(0.18))
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.top, 12)
                .animation(.easeOut(duration: 0.25), value: director.step)
            }
            .position(x: geo.size.width / 2, y: geo.size.height * 0.42 + dialSize / 2 + 60)
        }
        .ignoresSafeArea()
        .opacity(director.isOutro ? 0 : 1)
        .animation(.easeOut(duration: 0.35), value: director.isOutro)
    }

    private var caption: some View {
        GeometryReader { geo in
            Group {
                if let feature = director.currentFeature {
                    Text(feature.caption)
                        .font(.ui(12.5))
                        .foregroundStyle(Tone.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260)
                        .transition(.opacity)
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height * 0.42 + dialSize / 2 + 134)
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.3), value: director.step)
    }

    private var outro: some View {
        VStack(spacing: 11) {
            Text("Latitude")
                .font(.ui(26, .bold))
                .foregroundStyle(Tone.primary)
            Text("SHOOT LIKE FILM")
                .font(.mono(9, .semibold))
                .kerning(1.8)
                .foregroundStyle(Accent.amber)
        }
        .opacity(director.isOutro ? 1 : 0)
        .animation(.easeOut(duration: 0.45), value: director.isOutro)
    }
}

/// Flooding needs an unconstrained frame; keeping it in a modifier avoids an
/// optional-frame branch that SwiftUI would otherwise treat as two views.
private struct FloodFrame: ViewModifier {
    var flooded: Bool
    func body(content: Content) -> some View {
        if flooded {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
        }
    }
}

// MARK: - Glyphs

struct SplashGlyph: View {
    var id: String

    var body: some View {
        switch id {
        case "film":
            ZStack {
                ForEach(0..<3) { layer in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Accent.amber, lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(layer == 2 ? Accent.amber.opacity(0.16) : .clear)
                        )
                        .frame(width: 44, height: 30)
                        .opacity(layer == 0 ? 0.35 : layer == 1 ? 0.6 : 1)
                        .offset(x: CGFloat(layer) * 8 - 8, y: CGFloat(layer) * 9 - 9)
                }
            }

        case "histogram":
            HStack(alignment: .bottom, spacing: 3) {
                ForEach([0.26, 0.52, 0.82, 1.0, 0.68, 0.40, 0.20], id: \.self) { height in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Accent.amber)
                        .frame(height: 46 * height)
                }
            }
            .frame(height: 46)

        case "roll":
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Accent.amber, lineWidth: 2)
                .overlay {
                    Circle()
                        .strokeBorder(Accent.amber, lineWidth: 2)
                        .padding(11)
                }

        default: // exposure — a control dial with its index up
            Circle()
                .strokeBorder(Accent.amber, lineWidth: 2)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Accent.amber)
                        .frame(width: 2, height: 22)
                        .padding(.top, 6)
                }
        }
    }
}
