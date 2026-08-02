//
//  ReviewSettingsScreens.swift
//  LatitudeCam
//
//  Post-capture Review (with the Export sheet) and Settings.
//

import SwiftUI

// MARK: - Review

struct ReviewScreen: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            StripePattern.warmPhoto
                .ignoresSafeArea()
                .overlay {
                    Text("CAPTURED PHOTO")
                        .font(.mono(12, .medium))
                        .foregroundStyle(Color.white.opacity(0.2))
                }

            VStack(spacing: 0) {
                ZStack {
                    Text("\(app.selectedFilm.name.uppercased()) · RAW")
                        .font(.mono(10, .semibold))
                        .kerning(0.5)
                        .foregroundStyle(Accent.amber)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glass(radius: 16)

                    HStack {
                        Button { app.go(.viewfinder) } label: {
                            Text("✕")
                                .font(.ui(12, .semibold))
                                .foregroundStyle(Tone.primary)
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

                Spacer()

                HStack(spacing: 56) {
                    Button { app.go(.viewfinder) } label: {
                        Text("Discard")
                            .font(.ui(13, .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Button { app.exportSheetOpen = true } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 56, height: 56)
                            .overlay {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Ink.raised)
                                    .offset(y: -1)
                            }
                    }
                    .buttonStyle(.plain)

                    Button { app.go(.viewfinder) } label: {
                        Text("Save")
                            .font(.ui(13, .semibold))
                            .foregroundStyle(Accent.amber)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 16)
            }

            if app.exportSheetOpen {
                BottomSheet(onDismiss: { app.exportSheetOpen = false }) {
                    ExportSheet()
                }
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.exportSheetOpen)
    }
}

struct ExportSheet: View {
    @EnvironmentObject var app: AppState

    private let options = ["Save to Photos (HEIF)", "Export ProRAW (DNG)", "Share…"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export")
                .font(.ui(15, .semibold))
                .foregroundStyle(Tone.primary)
                .padding(.bottom, 16)

            ForEach(options, id: \.self) { option in
                Button { app.exportSheetOpen = false } label: {
                    Text(option)
                        .font(.ui(14, .medium))
                        .foregroundStyle(Tone.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if option != options.last {
                        Rectangle().fill(Tone.separator).frame(height: 0.5)
                    }
                }
            }

            Button { app.exportSheetOpen = false } label: {
                Text("Cancel")
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Accent.amber)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BackLink(title: "Viewfinder") { app.go(.viewfinder) }
                        .padding(.bottom, 16)

                    Text("Settings")
                        .font(.ui(22, .bold))
                        .foregroundStyle(Tone.primary)
                        .padding(.bottom, 20)

                    SettingsGroup(header: "Capture") {
                        SettingsRow(title: "Grid & Composition", detail: "Rule of Thirds")
                        SettingsRow(title: "Save Format", detail: "HEIF + RAW")
                        SettingsRow(title: "Default Aspect Ratio", detail: "3:2", isLast: true)
                    }

                    SettingsGroup(header: "Film Simulations") {
                        SettingsRow(title: "Manage Presets", detail: "")
                        SettingsRow(title: "Default Simulation", detail: app.selectedFilm.name, isLast: true)
                    }

                    SettingsGroup(header: "Manual Controls") {
                        SettingsRow(title: "Focus Peaking Color", detail: "Amber")
                        SettingsRow(title: "Histogram Style", detail: "Luma", isLast: true)
                    }

                    SettingsGroup(header: "About") {
                        SettingsRow(title: "Version", detail: "1.0", showChevron: false, isLast: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    var header: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(header.uppercased())
                .font(.ui(13))
                .kerning(0.3)
                .foregroundStyle(Color(hex: 0xEBEBF5).opacity(0.6))
                .padding(.leading, 4)

            VStack(spacing: 0) { content }
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .padding(.bottom, 24)
    }
}

private struct SettingsRow: View {
    var title: String
    var detail: String
    var showChevron = true
    var isLast = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.ui(17))
                .foregroundStyle(Tone.primary)

            Spacer(minLength: 8)

            if !detail.isEmpty {
                Text(detail)
                    .font(.ui(17))
                    .foregroundStyle(Color(hex: 0xEBEBF5).opacity(0.6))
                    .lineLimit(1)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xEBEBF5).opacity(0.3))
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Tone.separator)
                    .frame(height: 0.5)
                    .padding(.leading, 18)
            }
        }
    }
}
