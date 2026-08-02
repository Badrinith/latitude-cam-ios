//
//  CameraManager.swift
//  LatitudeCam
//
//  Camera Integration: Capture, Preview, and Image Processing
//  Combines Film Profiles + Exposure Control for real-time editing
//

import Foundation
import UIKit
import AVFoundation

// MARK: - Camera Manager

/// Central controller for camera capture and real-time image processing
/// Integrates:
/// - Film profiles (Phase 0.1)
/// - Exposure control (Phase 0.2)
/// - Camera capture (Phase 0.3)
public class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    @Published var currentISO: Int = 100
    @Published var currentShutterTime: Double = 1.0
    
    private var currentFilmProfileValue: FilmProfile = AmberFilm()
    var currentFilmProfile: FilmProfile {
        get { currentFilmProfileValue }
    }
    
    private var exposureMeter: ExposureMeter
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    
    // Callbacks
    var onPreviewUpdate: (() -> Void)?
    
    // MARK: - Initialization
    
    override public init() {
        self.exposureMeter = ExposureMeter(baseISO: 100, baseShutter: 1.0)
        super.init()
        
        // Load persisted settings if available
        loadSettings()
    }
    
    // MARK: - Film Profile Control
    
    public func setFilmProfile(_ profile: FilmProfile) {
        currentFilmProfileValue = profile
        saveSettings()
        onPreviewUpdate?()
    }
    
    // MARK: - Exposure Control
    
    public func setISO(_ iso: Int) {
        currentISO = iso
        saveSettings()
        onPreviewUpdate?()
    }

    public func setShutterTime(_ time: Double) {
        currentShutterTime = time
        saveSettings()
        onPreviewUpdate?()
    }
    
    // MARK: - Image Processing Pipeline
    
    /// Process a single pixel through the complete pipeline
    /// Order: Film → Exposure
    public func processPixel(_ pixel: Pixel) -> Pixel {
        // Step 1: Apply film profile
        let afterFilm = currentFilmProfile.apply(to: pixel)
        
        // Step 2: Apply exposure adjustments (ISO + Shutter)
        let afterExposure = exposureMeter.adjust(
            afterFilm,
            toISO: currentISO,
            exposureTime: currentShutterTime
        )
        
        return afterExposure
    }
    
    /// Process entire image array through pipeline
    public func processImage(_ pixels: [Pixel]) -> [Pixel] {
        return pixels.map { processPixel($0) }
    }
    
    // MARK: - Photo Capture
    
    /// Capture photo from camera with current settings applied
    public func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        // Initialize camera session if needed
        if captureSession == nil {
            setupCameraSession()
        }
        
        // Start capture session
        guard let session = captureSession else {
            completion(nil)
            return
        }
        
        if !session.isRunning {
            DispatchQueue.global(qos: .default).async {
                session.startRunning()
            }
        }
        
        // Schedule capture on background thread
        DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + 0.5) {
            self.capturePhotoInternal(completion: completion)
        }
    }
    
    private func capturePhotoInternal(completion: @escaping (UIImage?) -> Void) {
        // In a real implementation, this would:
        // 1. Capture from AVCaptureDevice
        // 2. Convert to CGImage
        // 3. Extract pixel data
        // 4. Apply processImage() to each pixel
        // 5. Return processed UIImage
        
        // For Phase 0.3, we create a test image
        let testImage = createTestImage()
        completion(testImage)
    }
    
    private func createTestImage() -> UIImage {
        // Create a simple test image for development
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        
        // Fill with gradient
        let context = UIGraphicsGetCurrentContext()!
        let colors = [UIColor.red.cgColor, UIColor.blue.cgColor]
        let colorspace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorspace, colors: colors as CFArray, locations: nil)!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return image
    }
    
    // MARK: - Camera Setup
    
    private func setupCameraSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo
        
        guard let camera = AVCaptureDevice.default(for: .video) else {
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            session.addInput(input)
            
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "CameraQueue"))
            session.addOutput(output)
            
            self.captureSession = session
            self.videoOutput = output
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        currentISO = defaults.integer(forKey: "LatitudeCam.ISO")
        if currentISO == 0 { currentISO = 100 }
        
        let shutterTime = defaults.double(forKey: "LatitudeCam.ShutterTime")
        if shutterTime > 0 { currentShutterTime = shutterTime }
        
        // Load film profile type
        if let filmType = defaults.string(forKey: "LatitudeCam.FilmProfile") {
            switch filmType {
            case "amber": currentFilmProfileValue = AmberFilm()
            case "slate": currentFilmProfileValue = SlateFilm()
            case "rust": currentFilmProfileValue = RustFilm()
            case "mono": currentFilmProfileValue = MonoFilm()
            default: currentFilmProfileValue = AmberFilm()
            }
        }
    }
    
    public func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(currentISO, forKey: "LatitudeCam.ISO")
        defaults.set(currentShutterTime, forKey: "LatitudeCam.ShutterTime")
        
        // Save film profile type
        let filmType: String
        if currentFilmProfile is AmberFilm { filmType = "amber" }
        else if currentFilmProfile is SlateFilm { filmType = "slate" }
        else if currentFilmProfile is RustFilm { filmType = "rust" }
        else if currentFilmProfile is MonoFilm { filmType = "mono" }
        else { filmType = "amber" }
        
        defaults.set(filmType, forKey: "LatitudeCam.FilmProfile")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Handle dropped frames
    }
}
