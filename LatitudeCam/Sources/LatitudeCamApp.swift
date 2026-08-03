//
//  LatitudeCamApp.swift
//  LatitudeCam
//

import SwiftUI

@main
struct LatitudeCamApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Ink.base.ignoresSafeArea()

            switch app.screen {
            case .splash:     SplashScreen { app.finishSplash() }
            case .onboarding: OnboardingScreen()
            case .login:      LoginScreen()
            case .viewfinder: ViewfinderScreen()
            case .filmSim:    FilmSimScreen()
            case .library:    LibraryScreen()
            case .edit:       EditScreen()
            case .review:     ReviewScreen()
            case .settings:   SettingsScreen()
            }
        }
    }
}
