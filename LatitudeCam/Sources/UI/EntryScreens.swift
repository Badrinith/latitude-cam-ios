//
//  EntryScreens.swift
//  LatitudeCam
//
//  Launch → Onboarding → Login
//

import SwiftUI

// MARK: - Launch

struct LaunchScreen: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Ink.raised.ignoresSafeArea()
            VStack(spacing: 18) {
                LatitudeMark(size: 96)
                Text("Latitude")
                    .font(.ui(22, .semibold))
                    .kerning(-0.2)
                    .foregroundStyle(Tone.primary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { app.go(.onboarding) }
    }
}

// MARK: - Onboarding

struct OnboardingScreen: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                LatitudeMark(size: 56)
                    .padding(.bottom, 28)

                Text("Shoot like film.\nControl it like pro.")
                    .font(.ui(30, .bold))
                    .foregroundStyle(Tone.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                Text("Manual exposure, ISO, and white balance — with color science drawn from classic film stocks.")
                    .font(.ui(14))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280, alignment: .leading)
                    .padding(.bottom, 36)

                VStack(alignment: .leading, spacing: 18) {
                    FeatureRow(
                        title: "Manual controls",
                        detail: "Shutter, ISO, WB, EV, focus peaking"
                    ) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.card)
                    }

                    FeatureRow(
                        title: "Film simulations",
                        detail: "Amber Stock, Slate, Rust, Mono & more"
                    ) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FilmSwatch.amber)
                    }

                    FeatureRow(
                        title: "ProRAW capture",
                        detail: "Full-resolution DNG alongside your look"
                    ) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Ink.card)
                            .overlay {
                                Text("RAW")
                                    .font(.mono(9, .semibold))
                                    .foregroundStyle(Accent.amber)
                            }
                    }
                }

                Spacer(minLength: 24)

                PrimaryButton("Get Started") { app.go(.login) }
            }
            .padding(.horizontal, 28)
            .padding(.top, 60)
            .padding(.bottom, 20)
        }
    }
}

private struct FeatureRow<Badge: View>: View {
    var title: String
    var detail: String
    @ViewBuilder var badge: Badge

    var body: some View {
        HStack(spacing: 14) {
            badge.frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Tone.primary)
                Text(detail)
                    .font(.ui(12))
                    .foregroundStyle(Tone.tertiary)
            }
        }
    }
}

// MARK: - Login

struct LoginScreen: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                LatitudeMark(size: 56)
                    .padding(.bottom, 24)

                Text("Sign in to Latitude")
                    .font(.ui(26, .bold))
                    .foregroundStyle(Tone.primary)
                    .padding(.bottom, 8)

                Text("Sync your rolls, presets, and settings across devices.")
                    .font(.ui(14))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 36)

                VStack(spacing: 12) {
                    Button { app.go(.viewfinder) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo").font(.system(size: 15))
                            Text("Continue with Apple")
                        }
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Ink.raised)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Tone.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button { app.go(.viewfinder) } label: {
                        Text("Continue with Email")
                            .font(.ui(15, .semibold))
                            .foregroundStyle(Tone.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Ink.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Tone.hairline, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 24)

                Button { app.go(.viewfinder) } label: {
                    Text("Skip for now")
                        .font(.ui(13, .medium))
                        .foregroundStyle(Tone.quaternary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 70)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Shared

struct PrimaryButton: View {
    var title: String
    var action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(15, .semibold))
                .foregroundStyle(Ink.raised)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Accent.amber, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
