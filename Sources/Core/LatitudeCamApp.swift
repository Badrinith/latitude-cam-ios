//
//  LatitudeCamApp.swift
//  LatitudeCam
//
//  Phase 0: Film Photography on iPhone
//

import SwiftUI

@main
struct LatitudeCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Latitude Cam - Phase 0")
                .font(.title)
            Text("Film Photography on iPhone")
                .font(.subheadline)
        }
        .padding()
    }
}
