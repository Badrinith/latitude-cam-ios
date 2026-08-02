import SwiftUI

// MARK: - Launch Screen

struct LaunchScreen: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            LatitudePalette.backgroundSheet.ignoresSafeArea()

            VStack(spacing: 18) {
                Image("AppIcon")
                    .resizable()
                    .frame(width: 96, height: 96)
                    .cornerRadius(22)

                Text("Latitude")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(LatitudePalette.textPrimary)
            }
        }
        .onTapGesture {
            appState.currentScreen = .onboarding
        }
    }
}

// MARK: - Onboarding Screen

struct OnboardingScreen: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            LatitudePalette.backgroundDark.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: LatitudeSpacing.md) {
                    Image("AppIcon")
                        .resizable()
                        .frame(width: 56, height: 56)
                        .cornerRadius(14)
                        .padding(.bottom, LatitudeSpacing.md)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Shoot like film.\nControl it like pro.")
                            .font(.system(size: LatitudeTypography.Headline.size, weight: .bold))
                            .foregroundColor(LatitudePalette.textPrimary)
                            .lineSpacing(LatitudeTypography.Headline.lineHeight - LatitudeTypography.Headline.size)

                        Text("Professional manual controls, original film color science, and a camera viewfinder designed for photographers.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(LatitudePalette.textSecondary)
                            .lineLimit(4)
                    }
                    .frame(maxWidth: 280, alignment: .leading)

                    VStack(spacing: 18) {
                        FeatureRow(icon: "🎨", title: "Film Simulations", description: "Amber, Slate, Rust, Mono")
                        FeatureRow(icon: "⚙️", title: "Manual Controls", description: "ISO, Shutter, White Balance")
                        FeatureRow(icon: "📊", title: "Histogram", description: "Real-time exposure analysis")
                    }
                    .padding(.top, 20)
                }
                .padding(LatitudeSpacing.xl)

                Spacer()

                Button(action: { appState.currentScreen = .login }) {
                    Text("Get Started")
                        .font(.system(size: LatitudeTypography.Button.size, weight: .semibold))
                        .foregroundColor(LatitudePalette.backgroundSheet)
                        .frame(maxWidth: .infinity)
                        .padding(LatitudeSpacing.md)
                        .background(LatitudePalette.accentAmber)
                        .cornerRadius(LatitudeRadius.medium)
                }
                .padding(LatitudeSpacing.xl)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: LatitudeSpacing.sm) {
            Text(icon).font(.system(size: 28))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: LatitudeTypography.Label.size, weight: .semibold))
                    .foregroundColor(LatitudePalette.textPrimary)
                Text(description)
                    .font(.system(size: LatitudeTypography.Description.size, weight: .regular))
                    .foregroundColor(LatitudePalette.textTertiary)
            }
        }
    }
}

// MARK: - Login Screen

struct LoginScreen: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            LatitudePalette.backgroundDark.ignoresSafeArea()

            VStack(spacing: LatitudeSpacing.xl) {
                VStack(spacing: LatitudeSpacing.md) {
                    Image("AppIcon")
                        .resizable()
                        .frame(width: 56, height: 56)
                        .cornerRadius(14)

                    VStack(spacing: 8) {
                        Text("Sign in to Latitude")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(LatitudePalette.textPrimary)

                        Text("Access your photo library and sync across devices.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(LatitudePalette.textSecondary)
                    }
                }
                .padding(.top, LatitudeSpacing.xl)

                VStack(spacing: LatitudeSpacing.sm) {
                    Button(action: { appState.currentScreen = .viewfinder }) {
                        HStack {
                            Image(systemName: "apple.logo")
                            Text("Continue with Apple")
                        }
                        .font(.system(size: LatitudeTypography.Button.size, weight: .semibold))
                        .foregroundColor(LatitudePalette.backgroundSheet)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(LatitudePalette.textPrimary)
                        .cornerRadius(LatitudeRadius.medium)
                    }

                    Button(action: { appState.currentScreen = .viewfinder }) {
                        HStack {
                            Image(systemName: "envelope")
                            Text("Continue with Email")
                        }
                        .font(.system(size: LatitudeTypography.Button.size, weight: .semibold))
                        .foregroundColor(LatitudePalette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(LatitudePalette.backgroundCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: LatitudeRadius.medium)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .cornerRadius(LatitudeRadius.medium)
                    }
                }

                Spacer()

                Button(action: { appState.currentScreen = .viewfinder }) {
                    Text("Skip for now")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }
            .padding(LatitudeSpacing.xl)
        }
    }
}

// MARK: - Viewfinder (Camera) Screen

struct ViewfinderScreen: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            // Camera feed placeholder
            Image(systemName: "camera.fill")
                .font(.system(size: 80))
                .foregroundColor(LatitudePalette.textSecondary)
                .ignoresSafeArea()

            VStack(alignment: .leading) {
                HStack {
                    Button(action: { appState.currentScreen = .settings }) {
                        Text("SETTINGS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(LatitudePalette.textPrimary)
                            .glassPill()
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        HUDReadout(label: "1/240", icon: "⏱")
                        HUDReadout(label: "ISO 100", icon: "☀️")
                        HUDReadout(label: "5600K", icon: "🌡")
                    }

                    Spacer()
                }
                .padding(LatitudeSpacing.md)

                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        // Mini histogram
                        HStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(LatitudePalette.accentAmber)
                                    .frame(height: CGFloat.random(in: 20...40))
                            }
                        }
                        .frame(height: 44)
                        .padding(8)
                        .background(LatitudePalette.glassBackground)
                        .cornerRadius(LatitudeRadius.medium)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        IconButton(icon: "3:2", label: "Aspect")
                        IconButton(icon: "RAW", label: "RAW")
                        IconButton(icon: "◎", label: "Focus")
                    }
                }
                .padding(LatitudeSpacing.md)

                VStack(spacing: 12) {
                    FilmstripRow(selectedFilm: appState.currentFilmProfile) { film in
                        appState.currentFilmProfile = film
                        appState.currentScreen = .filmSim
                    }

                    HStack {
                        Button(action: { appState.proControlsOpen.toggle() }) {
                            Text("PRO")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(LatitudePalette.accentAmber)
                        }

                        Spacer()

                        Button(action: { appState.currentScreen = .review }) {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .background(Circle().fill(Color.white))
                                .frame(width: 70, height: 70)
                        }

                        Spacer()

                        Button(action: { appState.currentScreen = .library }) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 20))
                                .foregroundColor(LatitudePalette.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(LatitudePalette.backgroundCard)
                                .cornerRadius(8)
                        }
                    }
                    .padding(LatitudeSpacing.md)
                }
            }
        }
    }
}

struct HUDReadout: View {
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Text(icon).font(.system(size: 12))
            Text(label)
                .font(.system(size: LatitudeTypography.Mono.size, weight: .semibold, design: .monospaced))
                .foregroundColor(LatitudePalette.textPrimary)
        }
        .glassPill()
    }
}

struct IconButton: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(LatitudePalette.textPrimary)
                .frame(width: 32, height: 32)
                .background(LatitudePalette.glassBackground)
                .cornerRadius(LatitudeRadius.small)

            Text(label)
                .font(.system(size: 8, weight: .regular))
                .foregroundColor(LatitudePalette.textTertiary)
        }
    }
}

struct FilmstripRow: View {
    let selectedFilm: String
    var onSelect: (String) -> Void

    let films = ["Amber", "Slate", "Rust", "Mono"]
    let colors: [String: Color] = [
        "Amber": LatitudePalette.filmAmber,
        "Slate": LatitudePalette.filmSlate,
        "Rust": LatitudePalette.filmRust,
        "Mono": LatitudePalette.filmMono
    ]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(films, id: \.self) { film in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colors[film] ?? .gray)
                        .frame(height: 44)

                    Text(film)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(selectedFilm == film ? LatitudePalette.accentAmber : LatitudePalette.textSecondary)
                }
                .overlay(
                    selectedFilm == film ?
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(LatitudePalette.accentAmber, lineWidth: 1.5) : nil
                )
                .onTapGesture {
                    onSelect(film)
                }
            }
        }
        .padding(.horizontal, LatitudeSpacing.md)
    }
}

// MARK: - Film Sim Screen

struct FilmSimScreen: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            LatitudePalette.backgroundDark.ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: { appState.currentScreen = .viewfinder }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Viewfinder")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(LatitudePalette.accentAmber)
                    }

                    Spacer()

                    Text("Film Sim")
                        .font(.system(size: LatitudeTypography.Title.size, weight: .bold))
                        .foregroundColor(LatitudePalette.textPrimary)

                    Spacer()
                }
                .padding(LatitudeSpacing.md)

                VStack(spacing: LatitudeSpacing.md) {
                    Text("Intensity")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(LatitudePalette.textPrimary)

                    Slider(value: .constant(0.8))
                        .tint(LatitudePalette.accentAmber)
                }
                .padding(LatitudeSpacing.md)

                Spacer()
            }
        }
    }
}

// MARK: - Library Screen

struct LibraryScreen: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            LatitudePalette.backgroundDark.ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: { appState.currentScreen = .viewfinder }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(LatitudePalette.accentAmber)
                    }

                    Spacer()

                    Text("Library")
                        .font(.system(size: LatitudeTypography.Title.size, weight: .bold))
                        .foregroundColor(LatitudePalette.textPrimary)

                    Spacer()
                }
                .padding(LatitudeSpacing.md)

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(0..<9, id: \.self) { index in
                            RoundedRectangle(cornerRadius: LatitudeRadius.card)
                                .fill(LatitudePalette.backgroundCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: LatitudeRadius.card)
                                        .stroke(LatitudePalette.textSecondary, lineWidth: 1)
                                )
                                .frame(height: 120)
                        }
                    }
                    .padding(LatitudeSpacing.md)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Review Screen

struct ReviewScreen: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            LatitudePalette.backgroundSheet.ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: { appState.currentScreen = .viewfinder }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(LatitudePalette.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(LatitudePalette.glassBackground)
                            .cornerRadius(LatitudeRadius.pill)
                    }

                    Spacer()

                    Text("AMBER STOCK · RAW")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LatitudePalette.textPrimary)
                        .glassPill()

                    Spacer()
                }
                .padding(LatitudeSpacing.md)

                Spacer()

                HStack(spacing: LatitudeSpacing.xl) {
                    Text("Discard")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(LatitudePalette.textSecondary)

                    Spacer()

                    Button(action: { appState.exportSheetOpen.toggle() }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(LatitudePalette.backgroundSheet)
                            )
                    }

                    Spacer()

                    Text("Save")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(LatitudePalette.accentAmber)
                }
                .padding(LatitudeSpacing.md)
            }
        }
    }
}

// MARK: - Settings Screen

struct SettingsScreen: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            LatitudePalette.backgroundDark.ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: { appState.currentScreen = .viewfinder }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(LatitudePalette.accentAmber)
                    }

                    Spacer()

                    Text("Settings")
                        .font(.system(size: LatitudeTypography.Title.size, weight: .bold))
                        .foregroundColor(LatitudePalette.textPrimary)

                    Spacer()
                }
                .padding(LatitudeSpacing.md)

                ScrollView {
                    VStack(alignment: .leading, spacing: LatitudeSpacing.lg) {
                        SettingsSection(title: "Capture") {
                            SettingsRow(title: "Grid & Composition", detail: "Rule of Thirds")
                        }

                        SettingsSection(title: "Film Simulations") {
                            SettingsRow(title: "Default", detail: "Amber Stock")
                        }

                        SettingsSection(title: "Manual Controls") {
                            SettingsRow(title: "Focus Peaking", detail: "Amber")
                        }

                        SettingsSection(title: "About") {
                            SettingsRow(title: "Version", detail: "0.1.0")
                        }
                    }
                    .padding(LatitudeSpacing.md)
                }

                Spacer()
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))

            VStack {
                content()
            }
            .background(LatitudePalette.backgroundCard)
            .cornerRadius(LatitudeRadius.card)
        }
    }
}

struct SettingsRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(LatitudePalette.textPrimary)

            Spacer()

            Text(detail)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(LatitudePalette.textSecondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.3))
        }
        .padding(LatitudeSpacing.md)
    }
}
