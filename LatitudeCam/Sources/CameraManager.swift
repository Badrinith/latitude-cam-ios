//
//  CameraManager.swift
//  LatitudeCam
//
//  Capture session, GPU render pipeline, and still capture.
//

import Foundation
import UIKit
import AVFoundation
import CoreImage
import Metal

// MARK: - Frame buffer
//
// Frames land here and nowhere else. Splitting the 30fps stream out of
// CameraManager means chrome that observes the manager (status, controls)
// does not rebuild on every frame — only the preview view does.

public final class FrameBuffer: ObservableObject {
    @Published public internal(set) var image: UIImage?
}

/// Thumbnails of the current scene developed through each stock, keyed by film
/// id. Its own object for the same reason frames have one: the film knob
/// redraws at 4Hz and must not drag the viewfinder along.
public final class FilmPreviewBuffer: ObservableObject {
    @Published public internal(set) var thumbnails: [String: UIImage] = [:]
}

// MARK: - Render settings

/// Everything the render pipeline needs for one frame. A value type so it can be
/// copied out from under the lock and used without further synchronisation.
public struct RenderSettings: Equatable {
    public var filmID: String = "amber"
    /// 0…1 blend between the untouched frame and the full film look.
    public var intensity: Double = 0.8
    /// Exposure compensation in stops.
    public var ev: Double = 0
    public var iso: Int = 100
    /// Shutter speed as its denominator: 60 means 1/60s.
    public var shutterDenominator: Int = 60
    /// White balance in kelvin, 2000…8200.
    public var kelvin: Double = 5600
    public var grain = true
    public var halation = false
    public var vignette = false
    public var focusPeaking = false
    /// Named rather than a colour triple so RenderSettings stays Equatable and
    /// the value survives a round trip through UserDefaults.
    public var peakingColorName = "Amber"
    /// Either dial on its A position hands the whole exposure back to the camera,
    /// the way a Fuji body behaves with its dials on A.
    public var autoExposure = false

    public init() {}
}

// MARK: - Camera manager

public final class CameraManager: NSObject, ObservableObject {

    public enum Status: Equatable {
        case idle
        case requestingPermission
        case denied
        case noDevice
        case running
        case failed(String)

        public var isLive: Bool { self == .running }
    }

    /// Live frames. Observe this (not the manager) to redraw the preview.
    public let frames = FrameBuffer()

    /// Per-stock thumbnails for the film knob.
    public let filmPreviews = FilmPreviewBuffer()

    @Published public private(set) var status: Status = .idle

    // Session
    private var captureSession: AVCaptureSession?
    private var videoDevice: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private let cameraQueue = DispatchQueue(label: "com.latitude.camera", qos: .userInitiated)

    // RAW capture
    private var rawPhotoCaptured: ((Data?, String?) -> Void)?
    private let photoDelegate = RawPhotoCaptureDelegate()

    // Render pipeline — built once, reused for every frame. Rebuilding the
    // CIContext per frame was costing more than the filters themselves.
    private let ciContext: CIContext
    private let noiseTile: CIImage?

    // Settings shared across the main thread (writer) and camera queue (reader).
    private let settingsLock = NSLock()
    private var _settings = RenderSettings()
    private var settings: RenderSettings {
        settingsLock.lock(); defer { settingsLock.unlock() }
        return _settings
    }

    /// True once the device accepted custom exposure, so the render pipeline
    /// stops simulating ISO/shutter and only applies EV compensation.
    private var usingDeviceExposure = false

    private var lastFrameTime: CFTimeInterval = 0
    private let minFrameInterval: CFTimeInterval = 1.0 / 30.0

    // The knob only needs to keep up with the eye, not the sensor.
    private var lastPreviewTime: CFTimeInterval = 0
    private let previewInterval: CFTimeInterval = 1.0 / 4.0
    private static let previewEdge: CGFloat = 96

    override public init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            ciContext = CIContext(options: [.cacheIntermediates: false])
        }
        noiseTile = CameraManager.makeNoiseTile()
        super.init()

        loadSettings()

        cameraQueue.async { [weak self] in
            self?.initializeCamera()
        }
    }

    deinit {
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }
    }

    // MARK: - Settings

    /// Push new render settings in from the UI. Cheap and safe to call on every
    /// slider tick — the pipeline picks them up on the next frame.
    public func apply(_ new: RenderSettings) {
        settingsLock.lock()
        let exposureChanged = new.iso != _settings.iso
            || new.shutterDenominator != _settings.shutterDenominator
            || new.autoExposure != _settings.autoExposure
        _settings = new
        settingsLock.unlock()

        if exposureChanged {
            cameraQueue.async { [weak self] in
                self?.applyDeviceExposure(new)
            }
        }
        persist(new)
    }

    public var currentSettings: RenderSettings { settings }

    // MARK: - Session setup

    private func initializeCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()

        case .notDetermined:
            setStatus(.requestingPermission)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.cameraQueue.async {
                    if granted {
                        self.configureAndStart()
                    } else {
                        self.setStatus(.denied)
                    }
                }
            }

        case .denied, .restricted:
            setStatus(.denied)

        @unknown default:
            setStatus(.denied)
        }
    }

    private func configureAndStart() {
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) ?? AVCaptureDevice.default(for: .video) else {
            setStatus(.noDevice)
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                setStatus(.failed("Cannot add camera input"))
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            setStatus(.failed(error.localizedDescription))
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: cameraQueue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            setStatus(.failed("Cannot add video output"))
            return
        }
        session.addOutput(output)

        // Portrait. videoOrientation is deprecated on iOS 17; the rotation angle
        // is the supported spelling.
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        // Add photo output for RAW capture
        let photoOutput = AVCapturePhotoOutput()
        photoOutput.isHighResolutionCaptureEnabled = true

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            setStatus(.failed("Cannot add photo output"))
            return
        }
        session.addOutput(photoOutput)

        session.commitConfiguration()

        self.captureSession = session
        self.videoDevice = camera
        self.videoOutput = output
        self.photoOutput = photoOutput

        applyDeviceExposure(settings)

        session.startRunning()
        setStatus(.running)
    }

    /// Drive the real sensor where the hardware allows it, so ISO and shutter are
    /// genuine exposure changes rather than a brightness curve.
    private func applyDeviceExposure(_ s: RenderSettings) {
        guard let device = videoDevice else { return }

        if s.autoExposure {
            guard device.isExposureModeSupported(.continuousAutoExposure) else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.exposureMode = .continuousAutoExposure
                usingDeviceExposure = true
            } catch {
                usingDeviceExposure = false
            }
            return
        }

        guard device.isExposureModeSupported(.custom) else {
            usingDeviceExposure = false
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let format = device.activeFormat
            let iso = min(max(Float(s.iso), format.minISO), format.maxISO)

            let wanted = CMTime(value: 1, timescale: CMTimeScale(max(1, s.shutterDenominator)))
            var duration = wanted
            if CMTimeCompare(duration, format.minExposureDuration) < 0 {
                duration = format.minExposureDuration
            }
            if CMTimeCompare(duration, format.maxExposureDuration) > 0 {
                duration = format.maxExposureDuration
            }

            device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            usingDeviceExposure = true
        } catch {
            usingDeviceExposure = false
        }
    }

    private func setStatus(_ new: Status) {
        DispatchQueue.main.async { [weak self] in
            self?.status = new
        }
    }

    // MARK: - Still capture

    /// The current frame, already carrying the selected look.
    public func capturePhoto() -> UIImage? {
        frames.image
    }

    /// Capture RAW DNG image from the camera sensor without compression
    public func captureRaw(completion: @escaping (Data?, String?) -> Void) {
        guard let photoOutput = photoOutput else {
            completion(nil, "Photo output not available")
            return
        }

        // Create photo settings with maximum quality
        var settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality

        // Enable RAW DNG capture if available (14-bit Bayer)
        let availableRawFormats = photoOutput.availableRawPhotoPixelFormatTypes
        if !availableRawFormats.isEmpty {
            let rawFormat = availableRawFormats[0] // Use first available RAW format
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            settings.photoQualityPrioritization = .quality
        }

        // Enable maximum quality processing
        settings.isAutoStillImageStabilizationEnabled = true

        photoDelegate.captureCompletion = completion
        cameraQueue.async { [weak self] in
            self?.photoOutput?.capturePhoto(with: settings, delegate: self?.photoDelegate ?? RawPhotoCaptureDelegate())
        }
    }

    // MARK: - Persistence

    private func persist(_ s: RenderSettings) {
        let defaults = UserDefaults.standard
        defaults.set(s.iso, forKey: "LatitudeCam.ISO")
        defaults.set(s.shutterDenominator, forKey: "LatitudeCam.Shutter")
        defaults.set(s.filmID, forKey: "LatitudeCam.FilmProfile")
        defaults.set(s.kelvin, forKey: "LatitudeCam.Kelvin")
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        var s = RenderSettings()
        let iso = defaults.integer(forKey: "LatitudeCam.ISO")
        if iso > 0 { s.iso = iso }
        let shutter = defaults.integer(forKey: "LatitudeCam.Shutter")
        if shutter > 0 { s.shutterDenominator = shutter }
        if let film = defaults.string(forKey: "LatitudeCam.FilmProfile") { s.filmID = film }
        let kelvin = defaults.double(forKey: "LatitudeCam.Kelvin")
        if kelvin > 0 { s.kelvin = kelvin }

        settingsLock.lock()
        _settings = s
        settingsLock.unlock()
    }
}

// MARK: - RAW Photo Capture Delegate

class RawPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    var captureCompletion: ((Data?, String?) -> Void)?

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            DispatchQueue.main.async {
                self.captureCompletion?(nil, error.localizedDescription)
            }
            return
        }

        var imageData: Data?
        var errorMsg: String?

        // Try RAW DNG capture first (uncompressed sensor data)
        if photo.isRawPhoto, let dngData = photo.fileDataRepresentation() {
            imageData = dngData
        }
        // Fallback to HEIF with maximum quality
        else if let heifData = photo.fileDataRepresentation() {
            imageData = heifData
        } else {
            errorMsg = "Could not capture photo data"
        }

        DispatchQueue.main.async {
            self.captureCompletion?(imageData, errorMsg)
        }
    }
}

// MARK: - Frame delivery

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= minFrameInterval else { return }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let source = CIImage(cvImageBuffer: pixelBuffer)
        let rendered = render(source, with: settings)

        guard let cgImage = ciContext.createCGImage(rendered, from: source.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        DispatchQueue.main.async { [weak self] in
            self?.frames.image = uiImage
        }

        if now - lastPreviewTime >= previewInterval {
            lastPreviewTime = now
            makeFilmPreviews(from: source, settings: settings)
        }
    }

    /// One downscale, then a colour matrix per stock. Four 96pt renders at 4Hz is
    /// nothing next to the 1080p pipeline they sit alongside.
    private func makeFilmPreviews(from source: CIImage, settings s: RenderSettings) {
        let extent = source.extent
        guard extent.width > 1, extent.height > 1 else { return }

        let scale = Self.previewEdge / max(extent.width, extent.height)
        let small = source
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0
            ])

        var built: [String: UIImage] = [:]
        for film in Self.previewFilmIDs {
            var perStock = s
            perStock.filmID = film
            perStock.intensity = max(s.intensity, 0.85)
            // No grain or peaking at thumbnail size — both are invisible there and
            // only cost time.
            perStock.grain = false
            perStock.focusPeaking = false

            let rendered = render(small, with: perStock)
            if let cg = ciContext.createCGImage(rendered, from: small.extent) {
                built[film] = UIImage(cgImage: cg)
            }
        }

        guard !built.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.filmPreviews.thumbnails = built
        }
    }

    static let previewFilmIDs = ["amber", "slate", "rust", "mono"]

    public func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {}
}

// MARK: - Render pipeline
//
// Every stage is a GPU CIFilter. The per-pixel Swift transforms in FilmProfiles
// stay as the reference implementation the unit tests assert against; these
// matrices reproduce exactly the same maths at video rate.

extension CameraManager {

    func render(_ input: CIImage, with s: RenderSettings) -> CIImage {
        var image = input
        let extent = input.extent

        // 1. White balance. Claiming a source white of `kelvin` and mapping it to
        //    daylight reproduces how a camera's WB dial behaves: setting a low
        //    kelvin under daylight cools the frame.
        image = image.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: CGFloat(s.kelvin), y: 0),
            "inputTargetNeutral": CIVector(x: 6500, y: 0)
        ])

        // 2. Exposure. If the sensor took the ISO/shutter directly we only add the
        //    user's compensation; otherwise fold them in so the dials still read.
        var stops = s.ev
        if !usingDeviceExposure {
            stops += log2(Double(max(1, s.iso)) / 100.0)
            stops += log2(60.0 / Double(max(1, s.shutterDenominator)))
        }
        stops = min(max(stops, -4), 4)
        if abs(stops) > 0.001 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: stops
            ])
        }

        // 3. Film look.
        let t = CGFloat(min(max(s.intensity, 0), 1))
        let (fr, fg, fb) = CameraManager.filmVectors(s.filmID)
        image = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CameraManager.lerp(CIVector(x: 1, y: 0, z: 0, w: 0), fr, t),
            "inputGVector": CameraManager.lerp(CIVector(x: 0, y: 1, z: 0, w: 0), fg, t),
            "inputBVector": CameraManager.lerp(CIVector(x: 0, y: 0, z: 1, w: 0), fb, t)
        ])

        // 4. Halation — highlight bleed.
        if s.halation {
            image = image
                .applyingFilter("CIBloom", parameters: [
                    kCIInputRadiusKey: 12.0,
                    kCIInputIntensityKey: 0.7
                ])
                .cropped(to: extent)
        }

        // 5. Vignette.
        if s.vignette {
            image = image.applyingFilter("CIVignette", parameters: [
                kCIInputRadiusKey: 1.4,
                kCIInputIntensityKey: 1.2
            ])
        }

        // 6. Grain, scaled by film speed. Soft light rather than overlay: CoreImage
        //    works in linear light, where mid-grey is about 0.21, so overlay's
        //    shadow branch multiplies by 2·blend and turns a gentle noise into
        //    white salt across everything dark. Soft light scales with the base
        //    instead, so blacks stay black.
        if s.grain, let noise = noiseTile {
            let amplitude = Self.grainAmplitude(forISO: s.iso)
            let bias = (1 - amplitude) / 2
            image = noise
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: amplitude, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: amplitude, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: amplitude, w: 0),
                    "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1)
                ])
                .cropped(to: extent)
                .applyingFilter("CISoftLightBlendMode", parameters: [
                    kCIInputBackgroundImageKey: image
                ])
        }

        // 7. Focus peaking, drawn last since it is a shooting aid, not a look.
        if s.focusPeaking {
            let tint = Pref.peakingTint(s.peakingColorName)
            let edges = image
                .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 6.0])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: CGFloat(tint.r), y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: CGFloat(tint.g), y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: CGFloat(tint.b), y: 0, z: 0, w: 0)
                ])
            image = edges.applyingFilter("CIScreenBlendMode", parameters: [
                kCIInputBackgroundImageKey: image
            ])
        }

        return image.cropped(to: extent)
    }

    /// Matches the multipliers in FilmProfiles.swift exactly.
    static func filmVectors(_ id: String) -> (CIVector, CIVector, CIVector) {
        switch id {
        case "slate":
            return (CIVector(x: 0.8, y: 0, z: 0, w: 0),
                    CIVector(x: 0, y: 0.8, z: 0, w: 0),
                    CIVector(x: 0, y: 0, z: 1.2, w: 0))
        case "rust":
            return (CIVector(x: 1.3, y: 0, z: 0, w: 0),
                    CIVector(x: 0, y: 1.1, z: 0, w: 0),
                    CIVector(x: 0, y: 0, z: 0.6, w: 0))
        case "mono":
            let luma = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0)
            return (luma, luma, luma)
        default: // amber
            return (CIVector(x: 1.2, y: 0, z: 0, w: 0),
                    CIVector(x: 0, y: 0.9, z: 0, w: 0),
                    CIVector(x: 0, y: 0, z: 0.8, w: 0))
        }
    }

    static func lerp(_ a: CIVector, _ b: CIVector, _ t: CGFloat) -> CIVector {
        CIVector(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
            z: a.z + (b.z - a.z) * t,
            w: a.w + (b.w - a.w) * t
        )
    }

    /// Unit grey noise, 0…1. The per-frame amplitude is applied at render time so
    /// grain can follow film speed without rebuilding this.
    ///
    /// Enlarged 2.4× because CIRandomGenerator is one random value per pixel, and
    /// pixel-sized speckle reads as sensor noise. Film grain is clumps.
    ///
    /// CIRandomGenerator is already infinite in extent. An earlier version cropped
    /// it to 512pt and then tiled with an identity transform — an identity lattice
    /// places every tile at the same spot, so the grain became a single 512pt
    /// patch at the origin, which CoreImage puts in the bottom-left corner.
    static func makeNoiseTile() -> CIImage? {
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        return random
            .transformed(by: CGAffineTransform(scaleX: 2.4, y: 2.4))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": luma,
                "inputGVector": luma,
                "inputBVector": luma,
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
    }

    /// Fast film is grainy and slow film is not — the one place where tying an
    /// effect to a dial is truer than a fixed amount.
    static func grainAmplitude(forISO iso: Int) -> CGFloat {
        let lowest = 50.0, highest = 3200.0
        let clamped = min(max(Double(iso), lowest), highest)
        let fraction = log2(clamped / lowest) / log2(highest / lowest)
        return CGFloat(0.02 + 0.05 * fraction)
    }
}
