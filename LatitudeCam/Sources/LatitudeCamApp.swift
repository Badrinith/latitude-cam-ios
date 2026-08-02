//
//  LatitudeCamApp.swift
//  LatitudeCam
//
//  Phase 0: Film Photography on iPhone with Professional Design

import SwiftUI

@main
struct LatitudeCamApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppContentView()
                .environmentObject(appState)
        }
    }
}

struct AppContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            LatitudePalette.backgroundDark.ignoresSafeArea()

            Group {
                switch appState.currentScreen {
                case .launch:
                    LaunchScreen()
                case .onboarding:
                    OnboardingScreen()
                case .login:
                    LoginScreen()
                case .viewfinder:
                    ViewfinderScreen()
                case .filmSim:
                    FilmSimScreen()
                case .library:
                    LibraryScreen()
                case .edit:
                    LibraryScreen()
                case .review:
                    ReviewScreen()
                case .settings:
                    SettingsScreen()
                }
            }
        }
    }
}
