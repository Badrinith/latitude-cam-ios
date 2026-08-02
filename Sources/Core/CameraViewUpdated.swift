//
//  CameraView with Real Preview
//

import SwiftUI

public struct CameraViewWithPreview: View {
    @StateObject private var camera = CameraManager()
    @State private var previewImage: UIImage?
    @State private var isCapturing = false
    @State private var capturedImage: UIImage?
    @State private var showComparison = false
    @State private var showSettings = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Latitude Cam")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: { showComparison.toggle() }) {
                            Image(systemName: "square.grid.2x2")
                                .foregroundColor(.white)
                        }
                        
                        Button(action: { showSettings.toggle() }) {
                            Image(systemName: "gear")
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.3))
                
                // Real-time Preview
                ZStack {
                    Color.gray.opacity(0.2)
                    
                    if let image = previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        VStack {
                            Image(systemName: "camera")
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                            Text("Camera Preview")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                
                // Control Panel
                VStack(spacing: 12) {
                    // Film Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Film Profile")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 8) {
                            ForEach(["Amber", "Slate", "Rust", "Mono"], id: \.self) { filmName in
                                Button(action: {
                                    let film: FilmProfile = filmName == "Amber" ? AmberFilm() :
                                                           filmName == "Slate" ? SlateFilm() :
                                                           filmName == "Rust" ? RustFilm() :
                                                           MonoFilm()
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
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("ISO")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(camera.currentISO)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(camera.currentISO) },
                                set: { camera.setISO(Int($0)) }
                            ),
                            in: 100...1600
                        )
                        .tint(.white)
                    }
                    
                    // Shutter Control
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Shutter")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.2f", camera.currentShutterTime))
                                .font(.caption)
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { camera.currentShutterTime },
                                set: { camera.setShutterTime($0) }
                            ),
                            in: 0.25...4.0
                        )
                        .tint(.white)
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
                }
                .padding()
                .background(Color.black.opacity(0.7))
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(camera: camera)
        }
        .onReceive(Timer.publish(every: 0.033).autoconnect()) { _ in
            // Update preview in real-time (simulated)
            // In real implementation, this would receive camera frames
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
