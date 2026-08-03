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
            if let shot = app.capturedImage {
                Image(uiImage: shot)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                StripePattern.warmPhoto
                    .ignoresSafeArea()
                    .overlay {
                        Text("NOTHING CAPTURED")
                            .font(.mono(12, .medium))
                            .foregroundStyle(Color.white.opacity(0.2))
                    }
            }

            VStack(spacing: 0) {
                ZStack {
                    Text("\(app.selectedFilm.name.uppercased()) · \(app.proRAW ? "RAW" : "HEIF")")
                        .font(.mono(10, .semibold))
                        .kerning(0.5)
                        .foregroundStyle(Accent.amber)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glass(radius: 16)

                    HStack {
                        Button { app.discardCapture() } label: {
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
                    Button {
                        Haptics.tap()
                        app.discardCapture()
                    } label: {
                        Text("Discard")
                            .font(.ui(13, .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.tap()
                        app.exportSheetOpen = true
                    } label: {
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

                    Button {
                        Haptics.success()
                        app.saveCapturedPhoto()
                        app.go(.viewfinder)
                    } label: {
                        Text("Save")
                            .font(.ui(13, .semibold))
                            .foregroundStyle(Accent.amber)
                    }
                    .buttonStyle(.plain)
                    .disabled(app.capturedImage == nil)
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

/// Bridges UIActivityViewController into SwiftUI. The popover anchor is required
/// or this traps on iPad, where a sheet has no implicit source rect.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.permittedArrowDirections = []
            popover.sourceRect = CGRect(
                x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY,
                width: 0, height: 0
            )
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ExportSheet: View {
    @EnvironmentObject var app: AppState
    @State private var shareOpen = false

    private let options = ["Save to Library", "Save & Keep Shooting", "Share…"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export")
                .font(.ui(15, .semibold))
                .foregroundStyle(Tone.primary)
                .padding(.bottom, 16)

            ForEach(options, id: \.self) { option in
                Button { select(option) } label: {
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
        .sheet(isPresented: $shareOpen) {
            if let image = app.capturedImage {
                ShareSheet(items: [image])
            }
        }
    }

    private func select(_ option: String) {
        Haptics.tap()
        switch option {
        case "Save to Library":
            app.exportSheetOpen = false
            app.saveCapturedPhoto()
            app.go(.library)
        case "Save & Keep Shooting":
            app.exportSheetOpen = false
            app.saveCapturedPhoto()
            app.go(.viewfinder)
        default:
            // Keep the export sheet mounted — it owns the share presentation.
            shareOpen = true
        }
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @EnvironmentObject var app: AppState

    // Bound straight to the same defaults keys the viewfinder, render pipeline
    // and gallery read, so a change here takes effect without any plumbing.
    @AppStorage(Pref.grid) private var grid = "Rule of Thirds"
    @AppStorage(Pref.aspect) private var aspect = "3:2"
    @AppStorage(Pref.jpegQuality) private var jpegQuality = "High"
    @AppStorage(Pref.peakingColor) private var peakingColor = "Amber"
    @AppStorage(Pref.histogramStyle) private var histogramStyle = "Luma"
    @AppStorage(Pref.haptics) private var haptics = true
    @AppStorage(Pref.hapticStrength) private var hapticStrength = "Strong"

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
                        OptionRow(title: "Grid & Composition",
                                  options: Pref.gridOptions, selection: $grid)
                        OptionRow(title: "Aspect Ratio",
                                  options: Pref.aspectOptions, selection: $aspect)
                        OptionRow(title: "JPEG Quality",
                                  options: Pref.jpegQualityOptions, selection: $jpegQuality,
                                  isLast: true)
                    }

                    SettingsGroup(header: "Manual Controls") {
                        OptionRow(title: "Focus Peaking Color",
                                  options: Pref.peakingColorOptions, selection: $peakingColor)
                        OptionRow(title: "Histogram Style",
                                  options: Pref.histogramStyleOptions, selection: $histogramStyle)
                        ToggleSettingsRow(title: "Haptics", isOn: $haptics)
                        OptionRow(title: "Haptic Strength",
                                  options: Pref.hapticStrengthOptions, selection: $hapticStrength,
                                  isLast: true)
                    }

                    SettingsGroup(header: "Look") {
                        ActionRow(title: "Reset to Default Look",
                                  detail: app.selectedFilm.name, isLast: true) {
                            app.resetLook()
                        }
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
        // The peaking tint lives in defaults, so the pipeline needs a nudge to
        // pick up a change made here.
        .onChange(of: peakingColor) { _, _ in app.syncCamera() }
    }
}

/// A settings row backed by a fixed list of choices.
private struct OptionRow: View {
    var title: String
    var options: [String]
    @Binding var selection: String
    var isLast = false

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            SettingsRow(title: title, detail: selection, isLast: isLast)
        }
        .buttonStyle(.plain)
        .onChange(of: selection) { _, _ in Haptics.detent() }
    }
}

/// A switch row. Haptics is the one setting that has to be reachable without
/// the feedback it controls, so it reads as a plain switch rather than a picker.
private struct ToggleSettingsRow: View {
    var title: String
    @Binding var isOn: Bool
    var isLast = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.ui(17))
                .foregroundStyle(Tone.primary)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Accent.amber)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Tone.separator).frame(height: 0.5).padding(.leading, 18)
            }
        }
        .onChange(of: isOn) { _, on in
            // Fires only when switching on, so you feel what you just enabled.
            if on { Haptics.toggle() }
        }
    }
}

/// A settings row that runs an action instead of holding a value.
private struct ActionRow: View {
    var title: String
    var detail: String
    var isLast = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.toggle()
            action()
        } label: {
            SettingsRow(title: title, detail: detail, isLast: isLast)
        }
        .buttonStyle(.plain)
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
