//
//  CameraView.swift
//  LatitudeCam
//
//  User Interface: Camera View with Real-Time Adjustment Controls
//

import SwiftUI

public struct CameraView: View {
    @StateObject private var camera = CameraManager()
    @State private var isCapturing = false
    @State private var capturedImage: UIImage?
    @State private var showSettings = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Camera preview background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Latitude Cam")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gear")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                
                Spacer()
                
                // Preview placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 300)
                    .overlay(
                        VStack {
                            Image(systemName: "camera")
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                            Text("Camera Preview")
                                .foregroundColor(.white)
                        }
                    )
                
                Spacer()
                
                // Control Panel
                VStack(spacing: 16) {
                    // Film Selection
                    VStack(alignment: .leading) {
                        Text("Film Profile")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 8) {
                            ForEach(["Amber", "Slate", "Rust", "Mono"], id: \.self) { filmName in
                                Button(action: {
                                    let film: FilmProfile
                                    switch filmName {
                                    case "Amber": film = AmberFilm()
                                    case "Slate": film = SlateFilm()
                                    case "Rust": film = RustFilm()
                                    case "Mono": film = MonoFilm()
                                    default: film = AmberFilm()
                                    }
                                    camera.setFilmProfile(film)
                                }) {
                                    Text(filmName)
                                        .font(.caption2)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    // ISO Control
                    VStack(alignment: .leading) {
                        Text("ISO: \(camera.currentISO)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack {
                            Text("100")
                                .font(.caption2)
                            
                            Slider(
                                value: Binding(
                                    get: { Double(camera.currentISO) },
                                    set: { camera.setISO(Int($0)) }
                                ),
                                in: 100...1600
                            )
                            
                            Text("1600")
                                .font(.caption2)
                        }
                    }
                    
                    // Shutter Control
                    VStack(alignment: .leading) {
                        Text("Shutter: \(String(format: "%.2f", camera.currentShutterTime))x")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack {
                            Text("0.25x")
                                .font(.caption2)
                            
                            Slider(
                                value: Binding(
                                    get: { camera.currentShutterTime },
                                    set: { camera.setShutterTime($0) }
                                ),
                                in: 0.25...4.0
                            )
                            
                            Text("4.0x")
                                .font(.caption2)
                        }
                    }
                    
                    // Capture Button
                    Button(action: capturePhoto) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                                    .frame(width: 75, height: 75)
                            )
                    }
                    .disabled(isCapturing)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(16)
            }
            .padding()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(camera: camera)
        }
    }
    
    private func capturePhoto() {
        isCapturing = true
        camera.capturePhoto { image in
            capturedImage = image
            isCapturing = false
            camera.saveSettings()
        }
    }
}

// Settings View
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var camera: CameraManager
    
    var body: some View {
        NavigationView {
            Form {
                Section("Camera Settings") {
                    LabeledContent("ISO", value: "\(camera.currentISO)")
                    LabeledContent("Shutter", value: String(format: "%.2f", camera.currentShutterTime))
                }
                
                Section("About") {
                    Text("Latitude Cam v0.1 - Phase 0")
                    Text("Film photography on iPhone")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CameraView()
}
