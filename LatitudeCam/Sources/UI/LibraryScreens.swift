//
//  LibraryScreens.swift
//  LatitudeCam
//
//  Film Sim, Library, and Edit.
//

import SwiftUI

// MARK: - Film Sim

struct FilmSimScreen: View {
    @EnvironmentObject var app: AppState

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BackLink(title: "Viewfinder") { app.go(.viewfinder) }
                        .padding(.bottom, 16)

                    Text("Film Sim")
                        .font(.ui(22, .bold))
                        .foregroundStyle(Tone.primary)
                        .padding(.bottom, 16)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(FilmPreset.all) { preset in
                            PresetCard(preset: preset, isSelected: preset.id == app.selectedFilm.id) {
                                withAnimation(.snappy(duration: 0.2)) { app.selectedFilm = preset }
                            }
                        }
                    }
                    .padding(.bottom, 18)

                    LookPanel(title: app.selectedFilm.name)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct PresetCard: View {
    var preset: FilmPreset
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(preset.swatch)
                    .frame(height: 70)
                    .padding(.bottom, 8)

                Text(preset.name)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Tone.primary)

                Text(preset.blurb)
                    .font(.ui(11))
                    .foregroundStyle(Tone.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Accent.amber : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Intensity + grain/halation/vignette — shared by Film Sim and the Edit tab.
struct LookPanel: View {
    @EnvironmentObject var app: AppState
    var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Tone.primary)
                    .padding(.bottom, 12)
            }

            SliderRow(
                label: title == nil ? "\(app.selectedFilm.name) Intensity" : "Intensity",
                value: "\(Int(app.intensity * 100))%",
                position: $app.intensity
            )
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                Chip(title: "Grain", isActive: app.grainOn) { app.grainOn.toggle() }
                Chip(title: "Halation", isActive: app.halationOn) { app.halationOn.toggle() }
                Chip(title: "Vignette", isActive: app.vignetteOn) { app.vignetteOn.toggle() }
            }
        }
        .padding(title == nil ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if title != nil {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Ink.card)
            }
        }
    }
}

// MARK: - Library

struct LibraryScreen: View {
    @EnvironmentObject var app: AppState
    @State private var filter = "All"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    private let dots: [Color] = [
        Accent.amber, FilmSwatch.slate, FilmSwatch.rust,
        FilmSwatch.mono, Accent.amber, FilmSwatch.rust,
        FilmSwatch.slate, Accent.amber, FilmSwatch.mono
    ]

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BackLink(title: "Viewfinder") { app.go(.viewfinder) }
                        .padding(.bottom, 16)

                    Text("Library")
                        .font(.ui(22, .bold))
                        .foregroundStyle(Tone.primary)
                        .padding(.bottom, 16)

                    HStack(spacing: 8) {
                        ForEach(["All", "RAW", "Favorites"], id: \.self) { name in
                            FilterChip(title: name, isActive: filter == name) {
                                withAnimation(.snappy(duration: 0.2)) { filter = name }
                            }
                        }
                    }
                    .padding(.bottom, 14)

                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(dots.indices, id: \.self) { index in
                            Button { app.go(.edit) } label: {
                                StripePattern.photo
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(alignment: .bottomLeading) {
                                        Circle()
                                            .fill(dots[index])
                                            .frame(width: 8, height: 8)
                                            .overlay {
                                                Circle().strokeBorder(
                                                    dots[index] == FilmSwatch.mono
                                                        ? Color.white.opacity(0.3) : .clear,
                                                    lineWidth: 1
                                                )
                                            }
                                            .padding(5)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Edit

struct EditScreen: View {
    @EnvironmentObject var app: AppState
    @State private var tab = "Film"

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    BackLink(title: "Library") { app.go(.library) }
                    Spacer()
                    Text("Edit")
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Tone.primary)
                    Spacer()
                    Button { app.go(.library) } label: {
                        Text("Save")
                            .font(.ui(13, .semibold))
                            .foregroundStyle(Accent.amber)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                StripePattern.photo
                    .overlay {
                        Text("PHOTO PREVIEW")
                            .font(.mono(11, .medium))
                            .foregroundStyle(Color.white.opacity(0.25))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(16)

                HStack(spacing: 22) {
                    ForEach(["Light", "Color", "Film", "Crop"], id: \.self) { name in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { tab = name }
                        } label: {
                            VStack(spacing: 4) {
                                Text(name)
                                    .font(.ui(12, .semibold))
                                    .foregroundStyle(tab == name ? Accent.amber : Tone.quaternary)
                                Rectangle()
                                    .fill(tab == name ? Accent.amber : .clear)
                                    .frame(height: 2)
                            }
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 14)

                LookPanel(title: nil)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
            }
        }
    }
}
