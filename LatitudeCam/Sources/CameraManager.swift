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
import ImageIO
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
    public var filmID: String = "neutral"
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
    public var autoExposure = true
    public var autoFocus = true
    /// 0 is as close as the lens goes, 1 is infinity. Only read when focus is manual.
    public var lensPosition: Double = 1.0
    /// MATRIX · SPOT · LOCK.
    public var metering = "MATRIX"
    /// Normalised sensor coordinates the meter and the lens work from, moved by
    /// tapping the viewfinder.
    public var pointOfInterest = CGPoint(x: 0.5, y: 0.5)
    /// Device zoom factor for the selected lens.
    public var zoomFactor: Double = 1
    /// Depth-separated capture. Off by default: it costs resolution on every
    /// body that offers it, so it has to be asked for.
    public var portrait = false
    /// Background blur as an aperture, because that is what it imitates. Smaller
    /// number, shallower depth of field.
    public var aperture: Double = 2.8

    public init() {}
}

// MARK: - Camera manager

public final class CameraManager: NSObject, ObservableObject {

    /// The user chooses whether RAW means the camera's Bayer DNG or Apple's
    /// computational ProRAW variant. They are deliberately separate choices.
    public enum RawCaptureSource: String {
        case sensor = "Sensor RAW"
        case appleProRAW = "Apple ProRAW"
    }

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
    /// The virtual multi-camera device drives the normal viewfinder. A RAW
    /// capture briefly substitutes its primary physical sensor, then restores it.
    private var previewCamera: AVCaptureDevice?
    private var restoresPreviewAfterRawCapture = false
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    /// Apple's capture rotation is based on the physical camera and gravity,
    /// unlike the SwiftUI control angle, which is only presentation state.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private let cameraQueue = DispatchQueue(label: "com.latitude.camera", qos: .userInitiated)

    // Still capture. One delegate per capture, retained here for its lifetime —
    // AVFoundation holds only a weak reference and continuous shooting overlaps.
    private let delegateLock = NSLock()
    private var activeCaptures: [Int64: StillCaptureDelegate] = [:]
    /// Developing a full-resolution still belongs neither on the frame queue nor
    /// on AVFoundation's callback queue — both stall something the user can feel.
    private let developQueue = DispatchQueue(label: "com.latitude.develop", qos: .userInitiated)

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

    /// Drives the render-side mirror. Read on the camera queue, written there too.
    private(set) var isFrontCamera = false

    /// True where the hardware can hand back a matte. Published so the control
    /// can hide itself on a body that cannot do it rather than fail on tap.
    @Published public private(set) var supportsPortrait = false
    private var portraitOn = false

    /// True once the device accepted custom exposure, so the render pipeline
    /// stops simulating ISO/shutter and only applies EV compensation.
    private var usingDeviceExposure = false

    private var lastFrameTime: CFTimeInterval = 0
    private let minFrameInterval: CFTimeInterval = 1.0 / 30.0


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
            || new.metering != _settings.metering
        let focusChanged = new.autoFocus != _settings.autoFocus
            || new.lensPosition != _settings.lensPosition
            || new.metering != _settings.metering
            || new.pointOfInterest != _settings.pointOfInterest
        let zoomChanged = new.zoomFactor != _settings.zoomFactor
        _settings = new
        settingsLock.unlock()

        if zoomChanged {
            cameraQueue.async { [weak self] in self?.applyZoom(CGFloat(new.zoomFactor)) }
        }

        if exposureChanged || focusChanged {
            cameraQueue.async { [weak self] in
                // Point of interest before exposure mode: a lock must freeze the
                // reading taken at the new point, not the old one.
                if focusChanged { self?.applyDeviceFocus(new) }
                if exposureChanged { self?.applyDeviceExposure(new) }
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

    /// One selectable field of view.
    public struct Lens: Equatable, Identifiable {
        public let id: String
        public let label: String
        /// Device zoom factor, not the number on the button. On a virtual device
        /// 1.0 is the widest constituent lens, so the 1× everyone knows sits
        /// wherever the ultra-wide hands over.
        public let zoom: CGFloat
    }

    /// What this camera can actually offer. Published so the selector shows the
    /// lenses the device has rather than a fixed set it might not.
    @Published public private(set) var lenses: [Lens] = []

    /// The zoom the hardware will accept. A pinch has to clamp to this or
    /// videoZoomFactor throws, and the range differs per camera and per lens.
    @Published public private(set) var zoomRange: ClosedRange<CGFloat> = 1...1

    /// Called with the wide lens's factor once the hardware has been read.
    ///
    /// On a virtual device zoom 1.0 is the *ultra-wide*, so an app that starts at
    /// 1 opens at 0.5× while its selector says 1×. The camera reports where wide
    /// actually is and the UI follows.
    public var onLensesReady: ((CGFloat) -> Void)?

    static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // The virtual device represents the lenses actually fitted to this iPhone
        // and exposes its hand-over factors for the model-aware lens selector.
        let types: [AVCaptureDevice.DeviceType] = position == .front
            ? [.builtInTrueDepthCamera, .builtInWideAngleCamera]
            : [.builtInTripleCamera, .builtInDualWideCamera,
               .builtInDualCamera, .builtInWideAngleCamera]

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: position
        )
        for type in types {
            if let device = discovery.devices.first(where: { $0.deviceType == type }) {
                return device
            }
        }
        return discovery.devices.first
    }

    /// Bayer RAW formats are advertised by the physical imaging sensor rather
    /// than every virtual multi-camera device. This is intentionally separate
    /// from `camera(at:)`: the latter must remain the live multi-lens viewfinder.
    static func rawCamera(
        at position: AVCaptureDevice.Position,
        lensID: String
    ) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType]
        if position == .front {
            types = [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        } else {
            // 2x is a crop from the wide sensor. Ultra-wide and telephoto have
            // distinct sensors, so RAW must target them directly rather than
            // silently falling back to wide.
            switch lensID {
            case "ultra": types = [.builtInUltraWideCamera]
            case "wide", "2x": types = [.builtInWideAngleCamera]
            case "tele": types = [.builtInTelephotoCamera]
            default: return nil
            }
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: position
        )
        for type in types {
            if let device = discovery.devices.first(where: { $0.deviceType == type }) {
                return device
            }
        }
        return discovery.devices.first
    }

    /// Reads the lens ladder off the device instead of assuming one. A 17 Pro Max
    /// and an SE disagree about what exists, and guessing produces buttons that
    /// select nothing.
    private func lensOptions(for device: AVCaptureDevice) -> [Lens] {
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = device.maxAvailableVideoZoomFactor

        if device.position == .front {
            // One physical lens, so the wide selfie is the sensor's full field and
            // the standard one is a crop of it — which is how the phone's own
            // camera does it too.
            var options = [Lens(id: "wide", label: "WIDE", zoom: minZoom)]
            let cropped = min(minZoom * 1.4, maxZoom)
            if cropped > minZoom + 0.05 {
                options.append(Lens(id: "std", label: "STD", zoom: cropped))
            }
            return options
        }

        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors
            .map { CGFloat(truncating: $0) }
            .sorted()
        let base = switchOvers.first ?? 1

        var options: [Lens] = []
        if base > 1.05 {
            options.append(Lens(id: "ultra", label: "0.5×", zoom: max(minZoom, 1)))
        }
        options.append(Lens(id: "wide", label: "1×", zoom: base))
        if maxZoom >= base * 2 {
            options.append(Lens(id: "2x", label: "2×", zoom: base * 2))
        }
        // Anything past the second switch-over is the telephoto, whose factor
        // differs by model — 3× on some bodies, 5× on others.
        if switchOvers.count > 1 {
            let tele = switchOvers[1]
            options.append(Lens(
                id: "tele",
                label: String(format: "%g×", (tele / base).rounded()),
                zoom: tele
            ))
        }
        return options
    }

    private func publishLenses(for device: AVCaptureDevice) {
        let options = lensOptions(for: device)
        let low = device.minAvailableVideoZoomFactor
        // Past about eight times the wide lens it is upscaling, not zooming, and
        // offering it invites a pinch that only makes the picture worse.
        let base = options.first { $0.id == "wide" }?.zoom ?? 1
        let high = min(device.maxAvailableVideoZoomFactor, base * 8)
        DispatchQueue.main.async { [weak self] in
            self?.lenses = options
            self?.zoomRange = low...max(low, high)
            self?.onLensesReady?(base)
        }
    }

    /// Lens changes are a zoom on the virtual device, which is why they do not
    /// interrupt the preview the way swapping inputs does.
    private func applyZoom(_ factor: CGFloat) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.videoZoomFactor = min(
                max(factor, device.minAvailableVideoZoomFactor),
                device.maxAvailableVideoZoomFactor
            )
        } catch {
            // Left wherever it was; the selector will show the stale value, which
            // is better than a silent mismatch between button and lens.
        }
    }

    /// Changes the session's video input while preserving its outputs. It runs
    /// exclusively on `cameraQueue`, before a RAW shutter request or after its
    /// delegate completes, so the preview never exposes a stale input.
    private func replaceVideoInput(with device: AVCaptureDevice) -> Bool {
        guard let session = captureSession,
              let newInput = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        session.beginConfiguration()
        let previousInputs = session.inputs
        previousInputs.forEach(session.removeInput)

        guard session.canAddInput(newInput) else {
            previousInputs.forEach { if session.canAddInput($0) { session.addInput($0) } }
            session.commitConfiguration()
            return false
        }
        session.addInput(newInput)

        if let photoOutput {
            configurePhotoOutput(photoOutput, for: device)
        }
        let front = device.position == .front
        orient(videoOutput?.connection(with: .video), front: front)
        orient(photoOutput?.connection(with: .video), front: front)
        if #available(iOS 17.0, *) {
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                device: device,
                previewLayer: nil
            )
        }
        session.commitConfiguration()

        if let photoOutput {
            configurePhotoOutput(photoOutput, for: device)
        }
        videoDevice = device
        isFrontCamera = front
        applyDeviceFocus(settings)
        applyDeviceExposure(settings)
        return true
    }

    /// Uses the selected physical sensor for a DNG while retaining the virtual
    /// device for every normal preview and lens selection.
    private func activateRawCaptureCameraIfNeeded(
        forLensID lensID: String,
        captureZoomFactor: CGFloat
    ) -> Bool {
        guard let current = videoDevice,
              current.position == .back,
              let rawCamera = Self.rawCamera(at: .back, lensID: lensID) else {
            return false
        }
        // A physical lens selected in the viewfinder can already be the capture
        // input. An unknown or missing lens is unavailable, never an invitation
        // to substitute the 1x wide camera.
        guard rawCamera.uniqueID != current.uniqueID else {
            applyZoom(captureZoomFactor)
            return true
        }

        guard replaceVideoInput(with: rawCamera) else { return false }
        // The 2x option is a crop from the physical wide sensor. Input swapping
        // resets its zoom to 1x, so set the crop before the photo settings and
        // shutter are configured.
        applyZoom(captureZoomFactor)
        previewCamera = current
        restoresPreviewAfterRawCapture = true
        return true
    }

    private func restorePreviewCameraIfNeeded() {
        guard restoresPreviewAfterRawCapture,
              let previewCamera else { return }
        guard replaceVideoInput(with: previewCamera) else { return }

        // Replacing a camera input also resets the virtual device's zoom. Restore
        // the framed focal length rather than leaving the viewfinder at 1x.
        applyZoom(CGFloat(settings.zoomFactor))
        self.previewCamera = previewCamera
        restoresPreviewAfterRawCapture = false
        publishLenses(for: previewCamera)
    }

    /// Everything about the photo output that depends on which camera is attached.
    /// Re-run after a switch: the two sensors advertise different photo sizes and
    /// different raw support, and a `maxPhotoDimensions` left over from the other
    /// one is rejected outright.
    private func configurePhotoOutput(_ output: AVCapturePhotoOutput, for device: AVCaptureDevice) {
        // Must be raised before any capture asks for .quality. A per-capture
        // photoQualityPrioritization above this ceiling is not clamped —
        // AVFoundation raises NSInvalidArgumentException, which crashed the shutter.
        output.maxPhotoQualityPrioritization = .quality

        // This is also refreshed after the session starts. Some physical cameras
        // do not advertise their ProRAW formats until their output connection is
        // live, so setting it only during session construction leaves RAW empty.
        output.isAppleProRAWEnabled = output.isAppleProRAWSupported
        // These modes trade image quality and/or settling time for shutter speed.
        // Latitude's still mode deliberately takes the opposite trade-off.
        output.isZeroShutterLagEnabled = false
        output.isResponsiveCaptureEnabled = false
        output.isFastCapturePrioritizationEnabled = false

        if #available(iOS 16.0, *),
           let largest = largestPhotoDimensions(in: device.activeFormat.supportedMaxPhotoDimensions) {
            output.maxPhotoDimensions = largest
        }

        // Delivery is only switched on while portrait is, because enabling it
        // narrows the format the device will run and costs resolution on every
        // frame — not just the ones you wanted separated.
        let canMatte = output.isPortraitEffectsMatteDeliverySupported
        output.isDepthDataDeliveryEnabled = portraitOn && output.isDepthDataDeliverySupported
        output.isPortraitEffectsMatteDeliveryEnabled = portraitOn && canMatte

        DispatchQueue.main.async { [weak self] in self?.supportsPortrait = canMatte }
    }

    /// Reconfigures the photo output for depth. A mode switch, so a brief
    /// reconfiguration is the honest cost — unlike a lens change, which is a zoom.
    public func setPortrait(_ on: Bool, completion: @escaping (Bool) -> Void) {
        cameraQueue.async { [weak self] in
            guard let self,
                  let session = self.captureSession,
                  let output = self.photoOutput,
                  let device = self.videoDevice else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            guard output.isPortraitEffectsMatteDeliverySupported else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            session.beginConfiguration()
            self.portraitOn = on
            self.configurePhotoOutput(output, for: device)
            session.commitConfiguration()

            DispatchQueue.main.async { completion(on) }
        }
    }

    /// Portrait, and never mirrored on the connection.
    ///
    /// Connection mirroring is applied in the connection's own coordinate space,
    /// which already carries the 90° portrait rotation — so asking for a
    /// left-right mirror there produced a vertical flip, and the selfie preview
    /// came out upside down. The mirror is done in the render pipeline instead,
    /// where the axes are the ones on screen.
    private func orient(_ connection: AVCaptureConnection?, front: Bool) {
        guard let connection else { return }

        // Back is 90 and known good. Front is 0 — the buffer arrives portrait-upright
        // already, so rotating it at all was the mistake.
        //
        // Found by bracketing on device rather than by reasoning, over four tries:
        // 90 turned it one way, 270 turned it the other, and since those differ by
        // half a circle the answer had to lie between them. 180 was inverted, which
        // left 0.
        //
        // The fallback chain matters as much as the value. The original code set
        // the angle only `if isVideoRotationAngleSupported`, with no else, so a
        // refused angle meant no rotation at all and a sideways frame with nothing
        // to indicate why.
        for angle in [front ? 0.0 : 90.0, 90.0, 270.0, 0.0]
        where connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
            break
        }

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    /// Flips the frame about its own vertical centre for the front camera. An
    /// unmirrored selfie preview reads as someone else's face.
    func mirroredForFrontCamera(_ image: CIImage) -> CIImage {
        guard isFrontCamera else { return image }
        let extent = image.extent
        let flip = CGAffineTransform(translationX: extent.midX, y: 0)
            .scaledBy(x: -1, y: 1)
            .translatedBy(x: -extent.midX, y: 0)
        return image.transformed(by: flip)
    }

    /// Swap between the front and back cameras, reporting the position actually in
    /// use — the caller's UI must not claim a switch that did not happen.
    public func flipCamera(completion: @escaping (AVCaptureDevice.Position) -> Void) {
        cameraQueue.async { [weak self] in
            guard let self,
                  let session = self.captureSession,
                  let current = self.videoDevice else { return }

            let target: AVCaptureDevice.Position = current.position == .front ? .back : .front
            guard let next = Self.camera(at: target),
                  let newInput = try? AVCaptureDeviceInput(device: next) else {
                DispatchQueue.main.async { completion(current.position) }
                return
            }

            session.beginConfiguration()
            let previous = session.inputs
            previous.forEach(session.removeInput)

            guard session.canAddInput(newInput) else {
                // Put the old camera back. A session left with no input is a dead
                // viewfinder, which is worse than a flip that refused.
                previous.forEach { if session.canAddInput($0) { session.addInput($0) } }
                session.commitConfiguration()
                DispatchQueue.main.async { completion(current.position) }
                return
            }
            session.addInput(newInput)

            if let photoOutput = self.photoOutput {
                self.configurePhotoOutput(photoOutput, for: next)
            }
            // Connections are rebuilt with the input, so rotation and mirroring
            // have to be set again on both outputs.
            let front = target == .front
            self.orient(self.videoOutput?.connection(with: .video), front: front)
            self.orient(self.photoOutput?.connection(with: .video), front: front)

            if #available(iOS 17.0, *) {
                self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                    device: next,
                    previewLayer: nil
                )
            }

            session.commitConfiguration()

            // Re-read capabilities from the live connection. This is where a
            // physical camera publishes the RAW/ProRAW formats after a switch.
            if let photoOutput = self.photoOutput {
                self.configurePhotoOutput(photoOutput, for: next)
            }

            self.videoDevice = next
            self.previewCamera = next
            self.restoresPreviewAfterRawCapture = false
            self.isFrontCamera = target == .front
            self.publishLenses(for: next)
            self.applyDeviceFocus(self.settings)
            self.applyDeviceExposure(self.settings)
            DispatchQueue.main.async { completion(target) }
        }
    }

    private func configureAndStart() {
        guard let camera = Self.camera(at: .back) ?? AVCaptureDevice.default(for: .video) else {
            setStatus(.noDevice)
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        // .photo, not .hd1920x1080. The preset caps the *photo* output as well as
        // the video one — under 1080p every still came back 2MP, which is what
        // made saved files 250KB no matter what the JPEG quality was set to.
        session.sessionPreset = .photo

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

        // Full-resolution stills, taken from the sensor rather than lifted out of
        // the preview stream.
        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            setStatus(.failed("Cannot add photo output"))
            return
        }
        session.addOutput(photoOutput)
        configurePhotoOutput(photoOutput, for: camera)

        if #available(iOS 17.0, *) {
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                device: camera,
                previewLayer: nil
            )
        }

        orient(output.connection(with: .video), front: false)
        orient(photoOutput.connection(with: .video), front: false)

        session.commitConfiguration()

        self.captureSession = session
        self.videoDevice = camera
        self.previewCamera = camera
        self.videoOutput = output
        self.photoOutput = photoOutput

        publishLenses(for: camera)
        applyDeviceFocus(settings)
        applyDeviceExposure(settings)

        session.startRunning()
        // ProRAW capability is connection-dependent on physical devices. Refresh
        // after startRunning so availableRawPhotoPixelFormatTypes is populated.
        configurePhotoOutput(photoOutput, for: camera)
        setStatus(.running)
    }

    /// Focus, and where the meter reads from.
    ///
    /// iOS has no selectable metering pattern — what it has is a point the sensor
    /// meters around. So Matrix reads from the centre, Spot reads from wherever
    /// the viewfinder was last tapped, and Lock freezes what is already set.
    private func applyDeviceFocus(_ s: RenderSettings) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = s.pointOfInterest
            }
            if s.autoFocus {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                } else if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
            } else if device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(
                    lensPosition: Float(min(max(s.lensPosition, 0), 1)), completionHandler: nil
                )
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest =
                    s.metering == "SPOT" ? s.pointOfInterest : CGPoint(x: 0.5, y: 0.5)
            }
        } catch {
            // A device that refuses configuration keeps whatever it had; the
            // pipeline is unaffected either way.
        }
    }

    /// Drive the real sensor where the hardware allows it, so ISO and shutter are
    /// genuine exposure changes rather than a brightness curve.
    private func applyDeviceExposure(_ s: RenderSettings) {
        guard let device = videoDevice else { return }

        // Lock outranks both auto and manual: it holds the reading already taken,
        // which is the whole point of an AE lock.
        if s.metering == "LOCK" {
            guard device.isExposureModeSupported(.locked) else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.exposureMode = .locked
                usingDeviceExposure = true
            } catch {
                usingDeviceExposure = false
            }
            return
        }

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

    /// One sensor capture. `raw` is DNG straight off the sensor with no look
    /// applied; `image` is the same frame at full resolution developed through the
    /// film pipeline, so the two are the negative and the print of one exposure.
    public struct CapturedStill {
        public var raw: Data?
        public var image: UIImage?
        public var pixelWidth: Int = 0
        public var pixelHeight: Int = 0
        /// Set when RAW was asked for and the hardware would not give it.
        public var rawUnavailable = false
    }

    /// True when this device can hand back a DNG. The viewfinder greys the RAW
    /// options out otherwise rather than promising a file that never arrives.
    public var supportsRAW: Bool {
        !(photoOutput?.availableRawPhotoPixelFormatTypes.isEmpty ?? true)
    }

    /// A standard Bayer DNG is the closest AVFoundation exposes to the sensor
    /// data. It avoids the ProRAW capture path, while still retaining normal DNG
    /// calibration metadata required by a RAW editor.
    public var supportsSensorRAW: Bool {
        Self.rawPixelFormat(for: .sensor, in: photoOutput?.availableRawPhotoPixelFormatTypes ?? []) != nil
    }

    public var supportsAppleProRAW: Bool {
        Self.rawPixelFormat(for: .appleProRAW, in: photoOutput?.availableRawPhotoPixelFormatTypes ?? []) != nil
    }

    static func rawPixelFormat(
        for source: RawCaptureSource,
        in formats: [OSType]
    ) -> OSType? {
        switch source {
        case .sensor:
            return formats.first(where: { !AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) })
        case .appleProRAW:
            return formats.first(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat)
        }
    }

    /// The RAW sensor mosaic must remain untouched. Put its orientation in DNG
    /// metadata, which every RAW-aware reader uses, rather than rasterizing it.
    static func exifOrientation(forCaptureRotation degrees: Double) -> UInt32 {
        let normalized = Int(degrees.rounded()) % 360
        switch normalized {
        case 90, -270: return CGImagePropertyOrientation.right.rawValue
        case -90, 270: return CGImagePropertyOrientation.left.rawValue
        case 180, -180: return CGImagePropertyOrientation.down.rawValue
        default: return CGImagePropertyOrientation.up.rawValue
        }
    }

    /// Applies Apple's device- and gravity-aware angle to the photo connection
    /// immediately before the shutter. AVCapturePhotoOutput writes that angle as
    /// orientation metadata that Photos honours for both JPEG and DNG assets.
    private func configureCaptureRotation(
        for output: AVCapturePhotoOutput,
        fallbackDegrees: Double
    ) -> Double {
        let angle: Double
        if #available(iOS 17.0, *), let rotationCoordinator {
            angle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
        } else {
            angle = fallbackDegrees
        }

        guard let connection = output.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else {
            return fallbackDegrees
        }
        connection.videoRotationAngle = angle
        return angle
    }

    /// Full-resolution still from `AVCapturePhotoOutput`.
    ///
    /// The preview stream is 2MP and is only ever a viewfinder; everything saved
    /// comes from here instead.
    public func captureStill(
        wantsRAW: Bool,
        wantsProcessed: Bool,
        targetMegapixels: Int?,
        rawCaptureSource: RawCaptureSource,
        captureLensID: String,
        captureZoomFactor: CGFloat,
        rotationDegrees: Double,
        completion: @escaping (CapturedStill) -> Void
    ) {
        guard let photoOutput else {
            DispatchQueue.main.async { completion(CapturedStill()) }
            return
        }

        // Copied out before `settings` below shadows the name with the capture's
        // own settings object.
        let current = self.settings

        // A Bayer DNG from this device is valid only at the physical wide
        // sensor's native field. Guard at the capture boundary as well as in the
        // UI: AVFoundation throws an Objective-C exception for a zoomed RAW
        // request, which cannot be caught safely in Swift.
        if wantsRAW, rawCaptureSource == .sensor, captureLensID != "wide" {
            DispatchQueue.main.async { completion(CapturedStill(rawUnavailable: true)) }
            return
        }

        if wantsRAW {
            let activated = cameraQueue.sync { [weak self] in
                self?.activateRawCaptureCameraIfNeeded(
                    forLensID: captureLensID,
                    captureZoomFactor: captureZoomFactor
                ) ?? false
            }
            guard activated else {
                DispatchQueue.main.async { completion(CapturedStill(rawUnavailable: true)) }
                return
            }
        }

        let rawFormats = photoOutput.availableRawPhotoPixelFormatTypes
        let rawType = Self.rawPixelFormat(for: rawCaptureSource, in: rawFormats)
        guard !wantsRAW || rawType != nil else {
            if wantsRAW {
                cameraQueue.async { [weak self] in self?.restorePreviewCameraIfNeeded() }
            }
            DispatchQueue.main.async {
                completion(CapturedStill(rawUnavailable: true))
            }
            return
        }
        let takingRAW = wantsRAW
        let takingProcessed = wantsProcessed

        let settings: AVCapturePhotoSettings
        if takingRAW, let rawType {
            if takingProcessed {
                settings = AVCapturePhotoSettings(
                    rawPixelFormatType: rawType,
                    processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc]
                )
            } else {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawType)
            }
        } else {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }

        // AVCapturePhotoSettings rejects photo-quality prioritization for some
        // RAW formats with an Objective-C exception. A DNG is already the sensor
        // sample, so leave RAW settings at the hardware's native delivery mode;
        // JPEG/HEIF captures retain the explicit maximum-quality priority.
        if !takingRAW {
            settings.photoQualityPrioritization = .quality
        }

        if current.portrait, photoOutput.isPortraitEffectsMatteDeliveryEnabled {
            settings.isPortraitEffectsMatteDeliveryEnabled = true
            settings.embedsPortraitEffectsMatteInPhoto = true
        }

        // RAW formats define their own supported native dimensions. Asking a
        // Bayer DNG to use a processed-photo dimension can be rejected by the
        // camera, so only override dimensions for processed captures.
        if !takingRAW,
           #available(iOS 16.0, *), let dimensions = photoDimensions(targetMegapixels) {
            settings.maxPhotoDimensions = dimensions
        }

        let captureRotation = configureCaptureRotation(
            for: photoOutput,
            fallbackDegrees: rotationDegrees
        )

        // Focus peaking is a viewfinder aid, not part of the photograph — its edge
        // highlights have no business in a saved frame, and a CIEdges pass over a
        // 48MP image is not cheap either.
        var renderSettings = self.settings
        renderSettings.focusPeaking = false

        let wantsPortrait = current.portrait
        let aperture = current.aperture

        let rawOrientation = Self.exifOrientation(forCaptureRotation: captureRotation)
        let delegate = StillCaptureDelegate(id: settings.uniqueID, rawOrientation: rawOrientation) { [weak self] raw, processed, matte in
            guard let self else { return }
            // Get off AVFoundation's callback queue before developing anything.
            // Holding it stalls the next capture, which is exactly what responsive
            // capture is there to avoid.
            self.developQueue.async {
                var result = CapturedStill()
                result.raw = raw
                result.rawUnavailable = wantsRAW && raw == nil

                // Develop the full-resolution frame through the same pipeline the
                // viewfinder uses, so the saved photo matches what was framed.
                // CIImage(data:) does not apply EXIF orientation on its own — the
                // connection above rotates the buffer correctly, but without this
                // option that rotation is written to the file and then silently
                // dropped right here, which is why both earlier rotation fixes
                // never changed anything: neither ever reached this line.
                // RAW Only still needs a full-resolution review image, but the
                // DNG itself remains untouched and is never replaced by this render.
                let reviewData = processed ?? raw
                if let reviewData,
                   let decoded = CIImage(data: reviewData, options: [.applyOrientationProperty: true]) {
                    var source = self.mirroredForFrontCamera(decoded)
                    if wantsPortrait, let matte {
                        source = self.separate(source, matte: matte, aperture: aperture)
                    }
                    let rendered = self.render(source, with: renderSettings)
                    if let cg = self.ciContext.createCGImage(rendered, from: source.extent) {
                        result.image = UIImage(cgImage: cg)
                        result.pixelWidth = cg.width
                        result.pixelHeight = cg.height
                    }
                }

                self.finishCapture(id: settings.uniqueID)
                DispatchQueue.main.async { completion(result) }
            }
        }

        // Held until the capture completes: AVFoundation keeps only a weak
        // reference, and rapid shutter taps overlap.
        delegateLock.lock()
        activeCaptures[settings.uniqueID] = delegate
        delegateLock.unlock()

        // Called straight from the caller's queue. cameraQueue is the video
        // delegate's queue and is busy thirty times a second — hopping onto it put
        // the shutter behind whichever preview frame was mid-render.
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    /// Blurs the background and lays the subject back over it through the matte.
    ///
    /// The matte arrives at its own resolution — smaller than the photo — so it is
    /// scaled to the frame before it is used. Blending against a mask of a
    /// different size silently misaligns the cut-out, which reads as a halo
    /// nobody can attribute to anything.
    private func separate(_ image: CIImage, matte: CIImage, aperture: Double) -> CIImage {
        let extent = image.extent
        let mask = matte.transformed(by: CGAffineTransform(
            scaleX: extent.width / matte.extent.width,
            y: extent.height / matte.extent.height
        ))

        // f/1.4 is the most blur, f/16 nearly none — the number reads the way it
        // does on a lens, so the control means what a photographer expects.
        let radius = max(0, (16 - aperture) / 15) * 26

        let background = image
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)

        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ])
    }

    private func finishCapture(id: Int64) {
        delegateLock.lock()
        activeCaptures[id] = nil
        let hasNoActiveCaptures = activeCaptures.isEmpty
        delegateLock.unlock()

        if hasNoActiveCaptures {
            cameraQueue.async { [weak self] in self?.restorePreviewCameraIfNeeded() }
        }
    }

    /// The supported photo size closest to the requested megapixel count. Nil
    /// target means the sensor's largest.
    @available(iOS 16.0, *)
    private func photoDimensions(_ targetMegapixels: Int?) -> CMVideoDimensions? {
        guard let supported = videoDevice?.activeFormat.supportedMaxPhotoDimensions,
              !supported.isEmpty else { return nil }
        guard let targetMegapixels else { return largestPhotoDimensions(in: supported) }

        let target = targetMegapixels * 1_000_000
        return supported.min {
            abs(Int($0.width) * Int($0.height) - target)
                < abs(Int($1.width) * Int($1.height) - target)
        }
    }

    @available(iOS 16.0, *)
    private func largestPhotoDimensions(in dimensions: [CMVideoDimensions]) -> CMVideoDimensions? {
        dimensions.max {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
    }

    // MARK: - Persistence

    private func persist(_ s: RenderSettings) {
        let defaults = UserDefaults.standard
        defaults.set(s.iso, forKey: "LatitudeCam.ISO")
        defaults.set(s.shutterDenominator, forKey: "LatitudeCam.Shutter")
        defaults.set(s.filmID, forKey: "LatitudeCam.FilmProfile")
        defaults.set(s.kelvin, forKey: "LatitudeCam.Kelvin")
        defaults.set(s.autoExposure, forKey: "LatitudeCam.AutoExposure")
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
        // Absent on a first run, where the default of auto is what we want.
        if let auto = defaults.object(forKey: "LatitudeCam.AutoExposure") as? Bool {
            s.autoExposure = auto
        }

        settingsLock.lock()
        _settings = s
        settingsLock.unlock()
    }
}

// MARK: - Still capture delegate
//
// A RAW + processed capture calls didFinishProcessingPhoto twice — once per
// photo. Both halves are collected here and handed over together in
// didFinishCaptureFor, which fires exactly once whether one arrived or two.

final class StillCaptureDelegate: NSObject,
    AVCapturePhotoCaptureDelegate,
    AVCapturePhotoFileDataRepresentationCustomizer {
    private let id: Int64
    private let rawOrientation: UInt32
    private let completion: (_ raw: Data?, _ processed: Data?, _ matte: CIImage?) -> Void

    private var rawData: Data?
    private var processedData: Data?
    private var matte: CIImage?

    init(
        id: Int64,
        rawOrientation: UInt32,
        completion: @escaping (Data?, Data?, CIImage?) -> Void
    ) {
        self.id = id
        self.rawOrientation = rawOrientation
        self.completion = completion
        super.init()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil else { return }
        if let matte = photo.portraitEffectsMatte {
            self.matte = CIImage(cvImageBuffer: matte.mattingImage)
        }
        if photo.isRawPhoto {
            rawData = photo.fileDataRepresentation(with: self) ?? photo.fileDataRepresentation()
        } else {
            processedData = photo.fileDataRepresentation()
        }
    }

    func replacementMetadata(for photo: AVCapturePhoto) -> [String: Any]? {
        guard photo.isRawPhoto else { return nil }
        var metadata = photo.metadata
        metadata[kCGImagePropertyOrientation as String] = rawOrientation
        var tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFOrientation as String] = rawOrientation
        metadata[kCGImagePropertyTIFFDictionary as String] = tiff
        return metadata
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        completion(rawData, processedData, matte)
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

        let source = mirroredForFrontCamera(CIImage(cvImageBuffer: pixelBuffer))
        let rendered = render(source, with: settings)

        guard let cgImage = ciContext.createCGImage(rendered, from: source.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        DispatchQueue.main.async { [weak self] in
            self?.frames.image = uiImage
        }

    }

    // makeFilmPreviews lived here: five 96pt renders every quarter second, feeding
    // a film knob that no longer exists. Dead work on the frame path is worse than
    // dead code anywhere else — it competed with the preview for the GPU on every
    // fourth frame and nothing was looking at the result.

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
        let curve = CameraManager.filmCurve(s.filmID)
        let lift = CGFloat(curve?.lift ?? 0) * t

        image = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CameraManager.lerp(CIVector(x: 1, y: 0, z: 0, w: 0), fr, t),
            "inputGVector": CameraManager.lerp(CIVector(x: 0, y: 1, z: 0, w: 0), fg, t),
            "inputBVector": CameraManager.lerp(CIVector(x: 0, y: 0, z: 1, w: 0), fb, t),
            // The bias column lifts the blacks in the same pass rather than
            // costing another filter.
            "inputBiasVector": CIVector(x: lift, y: lift, z: lift * 1.1, w: 0)
        ])

        // Curve follows intensity to 1.0, so a stock dialled to zero is inert in
        // tone as well as in colour.
        if let curve {
            let power = 1 + (curve.gamma - 1) * Double(t)
            if abs(power - 1) > 0.001 {
                image = image.applyingFilter("CIGammaAdjust", parameters: [
                    "inputPower": power
                ])
            }
        }

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
        case "neutral":
            // Identity. Intensity has nothing to blend towards, so the stock is
            // inert at any setting — which is the point of it.
            return (CIVector(x: 1, y: 0, z: 0, w: 0),
                    CIVector(x: 0, y: 1, z: 0, w: 0),
                    CIVector(x: 0, y: 0, z: 1, w: 0))

        // --- Reversal. Off-diagonal terms are negative: pulling a little of the
        // other channels out of each is what separates hues, where a pure gain
        // only brightens them.
        case "vermilion":
            return (CIVector(x: 1.34, y: -0.16, z: -0.10, w: 0),
                    CIVector(x: -0.12, y: 1.26, z: -0.08, w: 0),
                    CIVector(x: -0.08, y: -0.14, z: 1.14, w: 0))
        case "meridian":
            return (CIVector(x: 1.12, y: -0.06, z: -0.04, w: 0),
                    CIVector(x: -0.04, y: 1.10, z: -0.04, w: 0),
                    CIVector(x: -0.04, y: -0.06, z: 1.12, w: 0))
        case "porcelain":
            // Positive off-diagonals instead: the channels bleed slightly into
            // each other, which is what keeps skin from going waxy under
            // saturation.
            return (CIVector(x: 1.06, y: 0.04, z: 0.00, w: 0),
                    CIVector(x: 0.02, y: 1.02, z: 0.02, w: 0),
                    CIVector(x: 0.00, y: 0.02, z: 1.04, w: 0))

        // --- Print
        case "harbour":
            return (CIVector(x: 0.92, y: 0.04, z: 0.02, w: 0),
                    CIVector(x: 0.02, y: 0.98, z: 0.04, w: 0),
                    CIVector(x: 0.04, y: 0.08, z: 1.14, w: 0))
        case "ledger":
            return (CIVector(x: 0.86, y: 0.08, z: 0.04, w: 0),
                    CIVector(x: 0.06, y: 0.86, z: 0.06, w: 0),
                    CIVector(x: 0.04, y: 0.08, z: 0.88, w: 0))

        // --- Monochrome. Green-weighted rather than luma-weighted, which is what
        // a panchromatic emulsion does: skin lightens, red fabric darkens, and
        // foliage separates from sky instead of merging with it.
        case "ash":
            let pan = CIVector(x: 0.24, y: 0.68, z: 0.08, w: 0)
            return (pan, pan, pan)
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

    /// The stock's tone curve, as a power and a black lift.
    ///
    /// The matrix moves hue and saturation; the curve is what makes a reversal
    /// stock feel like one and a cine stock feel gradeable. Nil for the four
    /// original stocks, whose per-pixel implementations in FilmProfiles are the
    /// ground truth the matrix tests pin against — giving them a curve here would
    /// make the two disagree without either being wrong.
    static func filmCurve(_ id: String) -> (gamma: Double, lift: Double)? {
        switch id {
        case "vermilion": return (0.89, 0)
        case "meridian":  return (0.95, 0)
        case "porcelain": return (1.05, 0)
        case "harbour":   return (1.05, 0)
        // The only stock with its blacks off zero: built to be graded afterwards
        // rather than looked at straight.
        case "ledger":    return (1.13, 0.045)
        case "ash":       return (1.05, 0)
        default:          return nil
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
