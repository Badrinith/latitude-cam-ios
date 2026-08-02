//
//  ViewfinderScreen.swift
//  LatitudeCam
//
//  The home/camera screen, plus the Manual Controls sheet it presents.
//

import SwiftUI

struct ViewfinderScreen: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            StripePattern.viewfinder
                .ignoresSafeArea()
                .overlay {
                    Text("LIVE VIEWFINDER")
                        .font(.mono(12, .medium))
                        .foregroundStyle(Color.white.opacity(0.22))
                }

            ThirdsGrid().ignoresSafeArea()

            chrome

            if app.proSheetOpen {
                BottomSheet(onDismiss: { app.proSheetOpen = false }) {
                    ManualControlsSheet()
                }
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.proSheetOpen)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            // Top row — settings pill on the left, HUD readouts centred.
            ZStack {
                HStack(spacing: 8) {
                    readout(app.shutterLabel)
                    readout(app.isoLabel)
                    readout(app.kelvinLabel)
                }

                HStack {
                    Button { app.go(.settings) } label: {
                        Text("SETTINGS")
                            .font(.mono(10, .semibold))
                            .kerning(0.5)
                            .foregroundStyle(Color.white.opacity(0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glass(radius: 16)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Histogram (left) and capture-option buttons (right)
            HStack(alignment: .top) {
                histogram
                Spacer()
                VStack(spacing: 8) {
                    optionButton { Text("3:2").font(.mono(9, .semibold)).foregroundStyle(Tone.primary) }
                    optionButton { Text("RAW").font(.mono(8, .semibold)).foregroundStyle(Accent.amber) }
                    optionButton {
                        Circle()
                            .strokeBorder(Tone.primary, lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()

            filmstrip
                .padding(.bottom, 24)

            bottomBar
                .padding(.bottom, 8)
        }
    }

    private func readout(_ text: String) -> some View {
        Text(text)
            .font(.mono(12, .medium))
            .foregroundStyle(Tone.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glass(radius: 8)
    }

    private var histogram: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach([0.35, 0.60, 0.85, 1.0, 0.65, 0.45, 0.25], id: \.self) { h in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Accent.amber)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34 * h)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(width: 96, height: 44, alignment: .bottom)
        .glass(radius: 8)
    }

    private func optionButton<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .frame(width: 32, height: 32)
            .glass(radius: 16)
    }

    private var filmstrip: some View {
        HStack(spacing: 10) {
            ForEach(FilmPreset.all) { preset in
                let selected = preset.id == app.selectedFilm.id
                Button {
                    app.selectedFilm = preset
                    app.go(.filmSim)
                } label: {
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(preset.swatch)
                            .frame(width: 44, height: 44)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        selected ? Accent.amber : Color.white.opacity(0.2),
                                        lineWidth: 1.5
                                    )
                            }
                        Text(preset.shortName)
                            .font(.mono(9, .medium))
                            .foregroundStyle(selected ? Accent.amber : Color.white.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private var bottomBar: some View {
        HStack(spacing: 56) {
            Button { app.proSheetOpen = true } label: {
                Text("PRO")
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Accent.amber)
            }
            .buttonStyle(.plain)

            Button { app.go(.review) } label: {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 70, height: 70)
                    .overlay {
                        Circle().fill(.white).frame(width: 58, height: 58)
                    }
            }
            .buttonStyle(.plain)

            Button { app.go(.library) } label: {
                StripePattern.thumbnail
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Manual Controls sheet

struct ManualControlsSheet: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manual Controls")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Tone.primary)
                Spacer()
                Button { app.proSheetOpen = false } label: {
                    Text("Done")
                        .font(.ui(13, .semibold))
                        .foregroundStyle(Accent.amber)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)

            SliderRow(label: "Shutter Speed", value: "\(app.shutterLabel)s", position: $app.shutter)
                .padding(.bottom, 16)

            SliderRow(
                label: "ISO",
                value: app.isoLabel.replacingOccurrences(of: "ISO ", with: ""),
                position: $app.iso
            )
            .padding(.bottom, 16)

            SliderRow(
                label: "White Balance",
                value: app.kelvinLabel,
                position: $app.whiteBalance,
                temperatureTrack: true
            )
            .padding(.bottom, 16)

            SliderRow(
                label: "Exposure Comp.",
                value: app.exposureLabel,
                position: $app.exposureComp,
                bipolar: true
            )
            .padding(.bottom, 20)

            ToggleRow(label: "Focus Peaking", isOn: $app.focusPeaking)
            ToggleRow(label: "ProRAW", isOn: $app.proRAW)
        }
    }
}
