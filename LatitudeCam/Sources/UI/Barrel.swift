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

// MARK: - Orientation
//
// The app is locked to portrait, as a camera should be — the picture must not
// reflow because the body turned. But once the body is sideways every readout is
// sideways too, so the glyphs counter-rotate in place. This is what a camera does
// with the icons in its finder, and it is the whole of "landscape support" for a
// screen that is otherwise a live image.

final class DeviceOrientation: ObservableObject {
    @Published private(set) var angle: Angle = .zero

    private var token: NSObjectProtocol?

    init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        token = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.update() }
        update()
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func update() {
        let next: Angle
        switch UIDevice.current.orientation {
        case .landscapeLeft:  next = .degrees(90)
        case .landscapeRight: next = .degrees(-90)
        case .portrait:       next = .zero
        // faceUp, faceDown, upside-down and unknown all keep the last good angle
        // rather than snapping upright on a table.
        default:              return
        }
        guard next != angle else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { angle = next }
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
    /// Counter-rotation that keeps the engraving upright when the body is turned.
    var glyphRotation: Angle = .zero

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
                    Text(values[slot])
                        .font(.mono(slot == clamped ? 15 : 12, slot == clamped ? .bold : .medium))
                        .foregroundStyle(engravingColour(slot))
                        .shadow(color: .black.opacity(0.6), radius: 1, y: 0.5)
                        .rotationEffect(glyphRotation)
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
        // A tinted scale keeps its own colours; the live one simply burns brighter
        // than its neighbours rather than turning into the accent.
        if let tints, tints.indices.contains(slot) {
            return slot == clamped ? tints[slot] : tints[slot].opacity(0.42)
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

    private var turn: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
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
// Below the shutter, where it cannot cover the picture. The 340pt knob arc this
// replaces sat over the lower third of every frame.

struct FilmBarrel: View {
    @Binding var selection: FilmPreset
    var presets: [FilmPreset] = FilmPreset.all
    var onOpenDetail: () -> Void

    @StateObject private var orientation = DeviceOrientation()

    private var index: Binding<Int> {
        Binding(
            get: { presets.firstIndex(of: selection) ?? 0 },
            set: { selection = presets[min(max($0, 0), presets.count - 1)] }
        )
    }

    var body: some View {
        VStack(spacing: 5) {
            Barrel(
                values: presets.map { $0.name.uppercased() },
                index: index,
                height: 44,
                pitch: 96,
                radius: 9,
                // Each stock engraved in its own colour, so the barrel shows what
                // the frame will look like rather than only what it is called.
                tints: presets.map(\.engraved),
                glyphRotation: orientation.angle
            )
            .overlay(alignment: .top) {
                Triangle()
                    .fill(Accent.amber)
                    .frame(width: 8, height: 5)
                    .offset(y: -3)
            }

            // The swatch is the one thing the engraving cannot say.
            HStack(spacing: 6) {
                Circle()
                    .fill(selection.engraved)
                    .frame(width: 7, height: 7)
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5) }
                Text(selection.blurb.uppercased())
                    .font(.mono(7, .medium))
                    .kerning(0.8)
                    .foregroundStyle(Tone.quaternary)
            }
            .rotationEffect(orientation.angle)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                onOpenDetail()
            }
        }
        .padding(.horizontal, 18)
    }
}

// MARK: - Pro cluster
//
// Collapsed to chips above the shutter; one tap inflates the chosen control into
// a barrel at thumb height. Nothing ever occupies the middle of the frame.

struct BarrelCluster: View {
    @EnvironmentObject var app: AppState

    /// nil while collapsed.
    @State private var focus: String?
    @State private var idle: Task<Void, Never>?

    @StateObject private var orientation = DeviceOrientation()

    private struct Control: Identifiable {
        let id: String
        let label: String
        let chip: String
    }

    private var controls: [Control] {
        [
            .init(id: "shutter", label: "SHUTTER", chip: app.shutterLabel),
            .init(id: "iso", label: "ISO", chip: app.isoLabel),
            .init(id: "wb", label: "WHITE BALANCE", chip: app.kelvinLabel),
            .init(id: "ev", label: "EXPOSURE", chip: app.exposureLabel)
        ]
    }

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
                    .rotationEffect(orientation.angle)
                Spacer()
                Text(control.chip)
                    .font(.mono(11, .bold))
                    .foregroundStyle(Accent.amber)
                    .rotationEffect(orientation.angle)
            }
            .padding(.horizontal, 2)

            barrel(for: control.id)
                .overlay(alignment: .top) {
                    Triangle()
                        .fill(Accent.amber)
                        .frame(width: 9, height: 6)
                        .offset(y: -4)
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
                hasAuto: true,
                glyphRotation: orientation.angle
            )
        case "iso":
            Barrel(
                values: AppState.isoLabels,
                index: binding(get: { app.isoIndex }, set: { app.isoIndex = $0 }),
                hasAuto: true,
                glyphRotation: orientation.angle
            )
        case "wb":
            Barrel(
                values: AppState.whiteBalanceLabels,
                index: binding(get: { app.whiteBalanceIndex }, set: { app.whiteBalanceIndex = $0 }),
                glyphRotation: orientation.angle
            )
        default:
            Barrel(
                values: AppState.exposureLabels,
                index: binding(get: { app.exposureIndex }, set: { app.exposureIndex = $0 }),
                glyphRotation: orientation.angle
            )
        }
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
        HStack(spacing: 6) {
            ForEach(controls) { control in
                Button { open(control.id) } label: {
                    Text(control.chip)
                        .font(.mono(10, .medium))
                        .foregroundStyle(focus == control.id ? Ink.base : Tone.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .rotationEffect(orientation.angle)
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
