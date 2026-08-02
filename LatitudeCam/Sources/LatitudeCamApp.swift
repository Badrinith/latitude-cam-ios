//
//  LatitudeCamApp.swift
//  LatitudeCam
//
//  Pro camera app with original film-look color grading.
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
            case .launch:     LaunchScreen()
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
