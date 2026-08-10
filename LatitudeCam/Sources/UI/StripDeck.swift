//
//  StripDeck.swift
//  LatitudeCam
//
//  The fifth control style: one knurled barrel, and a meter down the edge.
//
//  The first attempt at this was a line of small type that became a wheel when
//  tapped. On glass it was unreadable and felt like nothing — a row of labels,
//  not a control. This is the correction: a single machined barrel big enough
//  to find without looking, with a reading you can take at arm's length.
//
//  It is driven as one gesture, not several. Slide **across** it to move
//  between settings; slide **along** it to change the one you are on. Both at
//  once, without lifting — because a finger already on a control is the best
//  place to start the next adjustment from, and making someone lift, aim and
//  land again is how a camera app becomes a menu.
//
//  Two rules from the last pass still hold, and are still tested:
//  everything stacks upward from the bottom of the screen so no station can
//  land on another, and every size comes from the body rather than a constant.
//

import SwiftUI

// MARK: - Sizes, from the body

enum StripMetrics {

    /// Type first, then the barrel that holds it.
    ///
    /// The depth used to set the type size, which meant the only way to make a
    /// reading legible was to make the whole control bigger. Backwards: the
    /// reading has to be readable at a size that stays out of the way, and the
    /// barrel is however deep that requires. Both come from the body.
    static func readingSize(forWidth width: CGFloat) -> CGFloat {
        min(21, max(16, width * 0.044))
    }

    static func labelSize(forWidth width: CGFloat) -> CGFloat {
        min(10, max(8, width * 0.021))
    }

    /// The longest engraving the barrel ever has to carry, laid on its side.
    /// Monospace advance is about 0.6 of the point size, and "1/1000" is the
    /// longest reading on any ladder.
    private static func laidOverLength(forWidth width: CGFloat) -> CGFloat {
        CGFloat("1/1000".count) * readingSize(forWidth: width) * 0.6
    }

    /// The barrel's depth.
    ///
    /// Upright it is the type plus its air, and no more — a slim band across
    /// the body rather than a slab. Turned, it has to be deep enough for that
    /// same lettering rotated: a turned word needs its *width* in the frame's
    /// height, the rule that once clipped the plate's switches to "PORTI".
    static func barrelHeight(forWidth width: CGFloat, turned: Bool = false) -> CGFloat {
        let reading = readingSize(forWidth: width)
        let upright = (reading * 1.5 + labelSize(forWidth: width) * 2.4).rounded()
        guard turned else { return upright }
        return max(upright, (laidOverLength(forWidth: width) + reading * 1.6).rounded())
    }

    /// The meter's breadth. Narrow on the picture, wide to the thumb — its
    /// touch target is set separately and is more than twice this.
    static func meterBreadth(forWidth width: CGFloat) -> CGFloat {
        min(36, max(28, width * 0.078))
    }

    /// Air between stations. One value, so the rhythm is even.
    static func gap(forWidth width: CGFloat) -> CGFloat {
        min(14, max(9, width * 0.028))
    }

    /// The release row.
    ///
    /// This style's own, not the plate's. The plate's row is sized around a
    /// 158pt film strip that this deck does not carry, and inheriting it pushed
    /// the arcs a third of the way up the screen — nowhere near the shutter
    /// they are supposed to sit against.
    static func releaseHeight(forWidth width: CGFloat) -> CGFloat {
        min(124, max(98, width * 0.25))
    }

    /// Where each station sits, measured up from the bottom of the screen.
    ///
    /// A running total, not a set of independent offsets. That is the whole
    /// defence against overlap: a station cannot be placed without first
    /// accounting for everything beneath it.
    struct Stack {
        var releaseBottom: CGFloat
        var releaseTop: CGFloat
        /// PRO and reset, tucked inside the inner ring, above the shutter.
        var handleBottom: CGFloat
        var handleTop: CGFloat
        /// The shutter's centre, measured up from the bottom of the screen.
        /// The rings are struck from here.
        var shutterCentre: CGFloat
    }

    static let handleHeight: CGFloat = 32

    static func stack(forWidth width: CGFloat, safeBottom: CGFloat,
                      turned: Bool = false) -> Stack {
        let gap = gap(forWidth: width)
        let releaseBottom = max(safeBottom, gap)
        let releaseHeight = releaseHeight(forWidth: width)
        let releaseTop = releaseBottom + releaseHeight
        let handleBottom = releaseTop + gap * 0.5
        return Stack(
            releaseBottom: releaseBottom, releaseTop: releaseTop,
            handleBottom: handleBottom, handleTop: handleBottom + handleHeight,
            shutterCentre: releaseBottom + releaseHeight / 2
        )
    }

    /// How far across a barrel counts as "show me the other one".
    static let crossThreshold: CGFloat = 34

    /// The inner ring's radius, measured from the shutter's centre.
    ///
    /// Half the screen, so the ring passes through both screen edges at the
    /// shutter's own height — which is what makes reaching the edges a fact
    /// about the geometry instead of a constant to tune.
    static func innerRadius(forWidth width: CGFloat) -> CGFloat {
        width / 2
    }

    /// The outer ring clears the inner one by a band and a hair.
    static func outerRadius(forWidth width: CGFloat, turned: Bool = false) -> CGFloat {
        innerRadius(forWidth: width)
            + barrelHeight(forWidth: width, turned: turned)
            + gap(forWidth: width) * 0.5
    }

    /// The topmost point a ring reaches above the shutter's centre.
    static func reachAboveShutter(forWidth width: CGFloat, turned: Bool = false) -> CGFloat {
        outerRadius(forWidth: width, turned: turned)
            + barrelHeight(forWidth: width, turned: turned) / 2
    }

    /// How far a full sweep of the meter travels, as a fraction of its length.
    static let meterTravel: CGFloat = 0.62

    /// How far the thumb moves to step one stop along the barrel.
    static func stopPitch(forWidth width: CGFloat) -> CGFloat {
        min(30, max(20, width * 0.058))
    }

    /// And to cross from one setting to the next. Deliberately much larger than
    /// the stop pitch: changing *what* you are setting is the rarer, more
    /// consequential move, and it must not happen by accident while turning.
    static func settingPitch(forWidth width: CGFloat) -> CGFloat {
        max(96, width * 0.28)
    }
}

// MARK: - The barrel

/// A ring of engravings sweeping around the shutter.
///
/// **Why it circles the release.** A thumb resting on the shutter pivots about
/// the shutter; every point on this ring is the same distance from that pivot,
/// so the whole scale is equally easy to reach without moving the hand. It also
/// makes reaching the screen edges structural: a ring centred on the release
/// with radius `width / 2` passes through both edges by construction.
///
/// **It does not cover the picture.** The band is translucent and its touch
/// area is the ring itself, so everything inside and outside it — which is most
/// of the frame — still shows the photograph and still takes a tap.
struct ArcBarrel: View {
    var items: [String]
    var index: Int
    var rotation: Angle = .zero
    /// The shutter's centre, in this view's own space.
    var centre: CGPoint
    var radius: CGFloat
    var thickness: CGFloat
    var live: Bool = false
    var presence: Double = 1
    var onStep: (Int) -> Void
    var onTap: () -> Void
    var onCross: () -> Void
    var onWake: () -> Void

    @GestureState private var holding = false
    @GestureState private var drag: CGFloat = 0
    @State private var carried: CGFloat = 0
    @State private var crossed = false

    /// Distance along the rim between engravings, from the type so they are
    /// spaced to be legible and no further apart than that.
    private var pitch: CGFloat {
        min(120, max(78, StripMetrics.readingSize(forWidth: radius * 2) * 4.2))
    }

    private var angularPitch: Double { Double(pitch / radius) }

    private var band: ArcBand {
        ArcBand(centre: centre, radius: radius, thickness: thickness)
    }

    var body: some View {
        ZStack {
            rim
            engravings
            indexMark
        }
        // Only the ring takes touches. The picture inside and outside it stays
        // live, which is the difference between controls *on* the viewfinder
        // and controls *over* it.
        .contentShape(band)
        .opacity(presence)
        .scaleEffect(presence < 1 ? 0.97 : 1, anchor: .bottom)
        .animation(.easeOut(duration: 0.32), value: presence)
        .gesture(roll)
        .simultaneousGesture(TapGesture().onEnded { onWake(); onTap() })
    }

    private var rim: some View {
        ZStack {
            band
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x413C34).opacity(0.86),
                                 Color(hex: 0x26231E).opacity(0.82),
                                 Color(hex: 0x1B1916).opacity(0.86)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .background { band.fill(.ultraThinMaterial) }

            ArcBand(centre: centre, radius: radius, thickness: thickness, edge: .centre)
                .stroke(Color.white.opacity(0.05),
                        style: StrokeStyle(lineWidth: thickness, dash: [1.6, 5.4]))

            ArcBand(centre: centre, radius: radius, thickness: thickness, edge: .top)
                .stroke(Color.white.opacity(live ? 0.26 : 0.15), lineWidth: 1)
            ArcBand(centre: centre, radius: radius, thickness: thickness, edge: .bottom)
                .stroke(Color.black.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
        .allowsHitTesting(false)
    }

    /// The words, standing upright on the ring.
    ///
    /// Upright, not tangential. Engravings on a real dial follow the rim, but
    /// tilted type is the thing this control keeps getting wrong, and the ring
    /// already carries the curve.
    private var engravings: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { i, label in
                let theta = Double(i - index) * angularPitch + Double(drag / radius)
                let here = abs(theta) < angularPitch * 0.5
                let near = 1 - min(1, abs(theta) / (angularPitch * 3.2))

                Text(label)
                    .font(.mono(here ? StripMetrics.readingSize(forWidth: radius * 2)
                                     : StripMetrics.readingSize(forWidth: radius * 2) * 0.6,
                                here ? .bold : .medium))
                    .foregroundStyle(here ? (live ? Accent.amber : Tone.primary)
                                          : Color(hex: 0x9A9488))
                    .lineLimit(1)
                    .fixedSize()
                    .shadow(color: .black.opacity(0.85), radius: 2, y: 1)
                    .rotationEffect(rotation)
                    .position(
                        x: centre.x + radius * sin(theta),
                        y: centre.y - radius * cos(theta)
                    )
                    .opacity(0.12 + 0.88 * Double(near))
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: index)
    }

    /// The mark the ring runs under, at the top of the sweep.
    private var indexMark: some View {
        VStack(spacing: 0) {
            bar
            Spacer(minLength: 0)
            bar
        }
        .frame(height: thickness * 0.94)
        .position(x: centre.x, y: centre.y - radius)
        .allowsHitTesting(false)
    }

    private var bar: some View {
        Rectangle()
            .fill(live ? Accent.amber : Color.white.opacity(0.45))
            .frame(width: 2, height: thickness * 0.15)
            .shadow(color: Accent.amber.opacity(live ? 0.6 : 0), radius: 3)
    }

    private var roll: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($holding) { _, state, _ in state = true }
            .updating($drag) { value, state, _ in
                state = value.translation.width - self.carried
            }
            .onChanged { value in
                onWake()

                let across = value.translation.height
                if !crossed, abs(across) > StripMetrics.crossThreshold,
                   abs(across) > abs(value.translation.width) {
                    crossed = true
                    onCross()
                    return
                }
                guard !crossed else { return }

                let moved = value.translation.width - carried
                guard abs(moved) >= pitch else { return }
                let steps = Int(moved / pitch)
                carried += CGFloat(steps) * pitch
                onStep(-steps)
            }
            .onEnded { _ in carried = 0; crossed = false }
    }
}

// MARK: - 05 · the edge meter

/// Exposure compensation, as a strip down the side of the frame.
///
/// Driven by a *relative* drag: wherever the thumb lands is the starting point.
/// Absolute positioning would mean reaching the top of the frame to ask for +2,
/// which on a large phone is two-handed — the thing this style exists to avoid.
struct EdgeMeter: View {
    @Binding var value: Double
    var reading: String
    var detents: Int
    var rotation: Angle = .zero
    var breadth: CGFloat
    var length: CGFloat

    @GestureState private var dragging = false
    @State private var startValue: Double?
    @State private var lastDetent: Int?

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.42))
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 1) }
                .background(.ultraThinMaterial, in: Capsule())

            VStack(spacing: 0) {
                sign("+")
                Spacer(minLength: 0)
                sign("−")
            }
            .padding(.vertical, 7)

            GeometryReader { geo in
                let travel = geo.size.height * StripMetrics.meterTravel
                let centre = geo.size.height / 2
                ZStack {
                    ForEach(0..<5, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i == 2 ? 0.22 : 0.13))
                            .frame(width: i == 2 ? breadth * 0.5 : breadth * 0.3, height: 1)
                            .position(x: geo.size.width / 2,
                                      y: centre + travel * (CGFloat(i) - 2) / 4)
                    }

                    Circle()
                        .fill(Accent.amber)
                        .shadow(color: Accent.amber.opacity(0.5), radius: dragging ? 7 : 0)
                        .frame(width: breadth * 0.6, height: breadth * 0.6)
                        .position(x: geo.size.width / 2,
                                  y: centre - travel * (CGFloat(value) - 0.5))
                        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: value)
                }
            }
            .padding(.vertical, breadth * 0.7)
        }
        .frame(width: breadth, height: length)
        .rotationEffect(rotation)
        .overlay {
            // Wider than what is drawn. A slim thing on the picture is right;
            // a slim thing to hit is not.
            Color.clear
                .frame(width: max(breadth * 2.1, 60), height: length)
                .rotationEffect(rotation)
                .contentShape(Rectangle())
                .gesture(scrub)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exposure compensation")
        .accessibilityValue(reading)
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / Double(max(detents, 1))
            value = KnobMath.clamp(value + (direction == .increment ? step : -step))
            Haptics.detent()
        }
    }

    private func sign(_ text: String) -> some View {
        Text(text)
            .font(.mono(9, .semibold))
            .foregroundStyle(Color(hex: 0x6A6459))
            .rotationEffect(rotation)
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { drag in
                let base = startValue ?? value
                if startValue == nil { startValue = value }
                let along = -DragAxis.along(drag.translation, rotation: rotation)
                let span = length * StripMetrics.meterTravel
                guard span > 0 else { return }
                value = KnobMath.clamp(base + Double(along / span))

                let detent = KnobMath.detent(value, stops: max(detents, 1))
                if detent != lastDetent {
                    lastDetent = detent
                    Haptics.detent()
                }
            }
            .onEnded { _ in startValue = nil; lastDetent = nil }
    }
}

// MARK: - The deck

struct StripDeck: View {
    @EnvironmentObject var app: AppState
    var rotation: Angle = .zero
    var edge: DeviceOrientation.Edge = .bottom
    var onSettings: () -> Void
    var onCycleGrid: () -> Void
    var onCycleAspect: () -> Void
    var aspect: String
    var onFilmSim: () -> Void
    var onLibrary: () -> Void
    var onFire: () -> Void

    /// The settings the first barrel walks, in reading order.
    static let order: [ActiveDial.Key] = [.shutter, .aperture, .iso, .white, .focus, .exposure]

    /// Short enough to read engraved on metal. "WHITE BALANCE" is a caption.
    static func engraved(_ key: ActiveDial.Key) -> String {
        switch key {
        case .shutter:  return "SHUTTER"
        case .aperture: return "APERTURE"
        case .iso:      return "ISO"
        case .white:    return "WHITE"
        case .focus:    return "FOCUS"
        case .exposure: return "EV"
        }
    }

    @State private var setting: ActiveDial.Key = .shutter
    @State private var valuesOpen = false
    /// The arcs are behind PRO now. At rest this style is a picture, a shutter
    /// and a roll of film — which was always its argument.
    @State private var proOpen = false
    /// Whether the controls are being attended to. They fade out when left
    /// alone, so the picture gets the glass back — the whole argument for this
    /// style — and come back on a touch.
    @State private var awake = true
    @State private var idle: Task<Void, Never>?

    /// What is left of a band once it has been put away. Low, but not nothing:
    /// the arcs slide down behind the release row and leave a sliver showing,
    /// which is both the affordance and the handle.
    private static let ghost: Double = 0.22

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let width = size.width
            let turned = edge != .bottom
            let stack = StripMetrics.stack(forWidth: width,
                                           safeBottom: geo.safeAreaInsets.bottom,
                                           turned: turned)
            let thickness = StripMetrics.barrelHeight(forWidth: width, turned: turned)
            let breadth = StripMetrics.meterBreadth(forWidth: width)
            let inset = StripMetrics.gap(forWidth: width)
            // Everything circles this.
            let shutter = CGPoint(x: width / 2, y: size.height - stack.shutterCentre)

            ZStack(alignment: .bottom) {
                meter(in: size, breadth: breadth, inset: inset)

                if proOpen {
                    ArcBarrel(
                        items: Self.order.map(Self.engraved),
                        index: Self.order.firstIndex(of: setting) ?? 0,
                        rotation: rotation, centre: shutter,
                        radius: StripMetrics.innerRadius(forWidth: width),
                        thickness: thickness,
                        live: awake && !valuesOpen,
                        presence: awake ? 1 : Self.ghost,
                        onStep: stepSetting, onTap: toggleValues,
                        onCross: toggleValues, onWake: wake
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))

                    if valuesOpen {
                        valueRing(shutter: shutter, width: width, thickness: thickness)
                            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
                    }
                }

                proHandle
                    .padding(.bottom, stack.handleBottom)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                releaseRow(width: width)
                    .padding(.bottom, stack.releaseBottom)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: size.width, height: size.height)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: valuesOpen)
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: proOpen)
        }
    }

    private func stepSetting(_ steps: Int) {
        let current = Self.order.firstIndex(of: setting) ?? 0
        let next = min(max(current + steps, 0), Self.order.count - 1)
        guard next != current else { return }
        Haptics.detent()
        setting = Self.order[next]
    }

    private func valueRing(shutter: CGPoint, width: CGFloat, thickness: CGFloat) -> some View {
        let ladder = app.ladder(for: setting)
        let items = ladder.hasAuto ? ["AUTO"] + ladder.labels : ladder.labels
        let index = ladder.isAuto ? 0 : (ladder.hasAuto ? ladder.index + 1 : ladder.index)

        return ArcBarrel(
            items: items, index: index,
            rotation: rotation, centre: shutter,
            radius: StripMetrics.outerRadius(forWidth: width,
                                             turned: edge != .bottom),
            thickness: thickness,
            live: awake, presence: awake ? 1 : Self.ghost,
            onStep: { steps in
                let next = min(max(index + steps, 0), items.count - 1)
                guard next != index else { return }
                Haptics.detent()
                if ladder.hasAuto {
                    if next == 0 { app.handBackToAuto(setting) }
                    else { app.select(setting, stop: next - 1) }
                } else {
                    app.select(setting, stop: next)
                }
            },
            onTap: toggleValues, onCross: toggleValues, onWake: wake
        )
    }

    private func toggleValues() {
        Haptics.toggle()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            valuesOpen.toggle()
        }
        restartIdle()
    }

    /// Any touch brings them back, and resets the clock.
    private func wake() {
        if !awake {
            withAnimation(.easeOut(duration: 0.2)) { awake = true }
        }
        restartIdle()
    }

    /// Left alone, the bands fade and the value arc goes away entirely. A
    /// camera that keeps its controls up after you have stopped using them is
    /// covering the thing you are trying to look at.
    private func restartIdle() {
        idle?.cancel()
        guard proOpen else { return }
        idle = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                awake = false
                valuesOpen = false
                proOpen = false
            }
        }
    }

    private func togglePro() {
        Haptics.toggle()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            proOpen.toggle()
            awake = true
            if !proOpen { valuesOpen = false }
        }
        restartIdle()
    }

    /// Portrait puts the meter on the trailing edge. Turned, it goes to the top
    /// of the screen — the side away from the release whichever way the body is
    /// held, so the thumbs get one job each.
    @ViewBuilder
    private func meter(in size: CGSize, breadth: CGFloat, inset: CGFloat) -> some View {
        let vertical = edge == .bottom
        // Stops above the outermost ring's reach, so a ring appearing never
        // lands on the meter and the meter never has to move.
        let clearance = StripMetrics.reachAboveShutter(forWidth: size.width,
                                                       turned: edge != .bottom)
            + StripMetrics.releaseHeight(forWidth: size.width) / 2 + inset
        let length = vertical
            ? max(140, size.height - clearance - inset - switchRowDepth)
            : max(140, size.width * 0.62)

        EdgeMeter(
            value: $app.exposureComp,
            reading: app.exposureLabel,
            detents: AppState.evDetents,
            rotation: rotation,
            breadth: breadth,
            length: length
        )
        .position(
            vertical
                ? CGPoint(x: size.width - inset - breadth / 2,
                          y: switchRowDepth + inset + length / 2)
                : CGPoint(x: size.width / 2, y: inset + breadth / 2 + switchRowDepth)
        )
    }

    /// The switch row's depth, so the meter starts below it rather than under
    /// it. Erring large only shortens the meter.
    private var switchRowDepth: CGFloat { 68 }

    private func releaseRow(width: CGFloat) -> some View {
        ZStack {
            LeafShutterButton(action: onFire)

            HStack(spacing: 10) {
                Button(action: onLibrary) {
                    LibraryThumbnail(gallery: app.gallery)
                        .frame(width: PlateMetrics.rollSide(forWidth: width),
                               height: PlateMetrics.rollSide(forWidth: width))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                // The roll of film, back as a strip you thumb through rather
                // than a label that opens a screen. Sized to clear the shutter:
                // the release owns the middle of this row and nothing may reach
                // into it.
                FilmCardStack(rotation: rotation, invertNames: false, onOpen: onFilmSim)
                    .frame(width: filmSide(forWidth: width),
                           height: filmSide(forWidth: width))
            }
            .padding(.horizontal, 14)
        }
        .frame(height: StripMetrics.releaseHeight(forWidth: width))
    }

    /// The film strip's footprint: what is left of the row once the shutter and
    /// the roll thumbnail have taken theirs, so it cannot grow into either.
    private func filmSide(forWidth width: CGFloat) -> CGFloat {
        let shutter: CGFloat = 78
        let roll = PlateMetrics.rollSide(forWidth: width)
        let free = (width - shutter - roll - 28 - 20) / 2
        return min(StripMetrics.releaseHeight(forWidth: width) - 10, max(52, free))
    }

    /// PRO, and the reset that belongs with it.
    ///
    /// Reset sits here rather than on a barrel because it is not a setting —
    /// it is the way out of all of them, and putting it on a scale would mean
    /// rolling past it by accident.
    private var proHandle: some View {
        HStack(spacing: 10) {
            if proOpen {
                Button {
                    Haptics.toggle()
                    app.resetControls()
                    restartIdle()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC9C2B4))
                        .rotationEffect(rotation)
                        .frame(width: 34, height: 30)
                        .background {
                            Capsule().fill(Color.black.opacity(0.4))
                                .overlay { Capsule().strokeBorder(Color.white.opacity(0.14)) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset controls")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Button(action: togglePro) {
                HStack(spacing: 5) {
                    Text("PRO")
                        .font(.mono(9, .bold))
                        .kerning(1.1)
                    Image(systemName: proOpen ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(proOpen ? Accent.amber : Color(hex: 0xC9C2B4))
                .frame(width: 74, height: 30)
                .background {
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                        .overlay {
                            Capsule().strokeBorder(
                                proOpen ? Accent.amber.opacity(0.6) : Color.white.opacity(0.18),
                                lineWidth: 1
                            )
                        }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(proOpen ? "Hide pro controls" : "Show pro controls")
        }
        // A swipe opens it too, in the direction the arcs travel.
        .simultaneousGesture(
            DragGesture(minimumDistance: 18).onEnded { drag in
                guard abs(drag.translation.height) > 24 else { return }
                let opening = drag.translation.height < 0
                guard opening != proOpen else { return }
                togglePro()
            }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: proOpen)
    }

}


/// A ring about an explicit centre, swept wide enough to leave the screen on
/// both sides.
///
/// Centred on the shutter, which is what makes "edge to edge" a property of the
/// geometry rather than a number to tune. A ring of radius `width / 2` centred
/// on the release passes through both screen edges by construction — three
/// earlier versions tried to reach the edges by widening an arc that was
/// centred somewhere else, and each fell short differently.
struct ArcBand: Shape {
    var centre: CGPoint
    var radius: CGFloat
    var thickness: CGFloat
    var edge: Edge = .fill

    enum Edge { case fill, top, bottom, centre }

    /// Past the horizontal on both sides, so the band exits the frame rather
    /// than ending inside it.
    private static let halfSweep = Double.pi / 2 * 1.12

    func path(in rect: CGRect) -> Path {
        let start = Angle.radians(-.pi / 2 - Self.halfSweep)
        let end = Angle.radians(-.pi / 2 + Self.halfSweep)

        var path = Path()
        switch edge {
        case .fill:
            path.addArc(center: centre, radius: radius + thickness / 2,
                        startAngle: start, endAngle: end, clockwise: false)
            path.addArc(center: centre, radius: radius - thickness / 2,
                        startAngle: end, endAngle: start, clockwise: true)
            path.closeSubpath()
        case .top:
            path.addArc(center: centre, radius: radius + thickness / 2,
                        startAngle: start, endAngle: end, clockwise: false)
        case .bottom:
            path.addArc(center: centre, radius: radius - thickness / 2,
                        startAngle: start, endAngle: end, clockwise: false)
        case .centre:
            path.addArc(center: centre, radius: radius,
                        startAngle: start, endAngle: end, clockwise: false)
        }
        return path
    }
}
