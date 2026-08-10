//
//  CameraControls.swift
//  LatitudeCam
//
//  The hardware Camera Control — the capacitive button on the side of an
//  iPhone 16 or 17 — driving the same dials the plate does.
//
//  Everything here is additive and gated twice over. The button is a property
//  of a handful of recent bodies, and the API that talks to it did not exist
//  before iOS 18; on anything else this file registers nothing, publishes
//  nothing, and the on-screen dials remain exactly what they were. That is the
//  whole design constraint: an iPhone 13 running iOS 17 must not be able to
//  tell this code was compiled in.
//
//  The controls do not carry their own notion of what a stop is. Each one is
//  built from the same ladder the dial reads and writes back through the same
//  index setter, so the button and the dial cannot come to different
//  conclusions about what "one click" means.
//

import AVFoundation
import Foundation

// MARK: - What the button can drive

/// The dials offered to the hardware button, in the order they appear in it.
///
/// There are five dials on the plate and the system takes at most four
/// controls, so one has to be left off. White balance is the omission: it is
/// the least likely to change shot to shot, and the only one of the five whose
/// effect is already plain in the preview without a number to read.
public enum CameraControlDial: String, CaseIterable, Sendable {
    case shutter
    case iso
    case aperture
    case exposure

    /// What the system HUD calls it.
    var title: String {
        switch self {
        case .shutter:  return "Shutter"
        case .iso:      return "ISO"
        case .aperture: return "Aperture"
        case .exposure: return "Exposure"
        }
    }

    /// SF Symbol shown beside the title in the HUD.
    var symbol: String {
        switch self {
        case .shutter:  return "camera.shutter.button"
        case .iso:      return "camera.aperture"
        case .aperture: return "f.cursive"
        case .exposure: return "plusminus.circle"
        }
    }
}

/// What the camera needs to know to build a control, supplied by whoever owns
/// the ladders. `CameraManager` does not know what an f-stop is and should not
/// learn: this is the seam.
public struct CameraControlLadder: Sendable {
    /// How many stops the dial has.
    public let count: Int
    /// The stop the dial is on right now.
    public let selected: Int
    /// What each stop is called in the HUD.
    public let title: @Sendable (Int) -> String

    public init(count: Int, selected: Int, title: @escaping @Sendable (Int) -> String) {
        self.count = count
        self.selected = selected
        self.title = title
    }
}

// MARK: - The bridge

/// Owns the hardware controls for a session, or owns nothing at all.
///
/// Kept apart from `CameraManager` so the availability gate has a single
/// entrance. A `@available(iOS 18.0, *)` scattered through the session setup
/// is how one path ends up ungated; here there is one object, and on an
/// unsupported body it is simply never built.
@available(iOS 18.0, *)
final class CameraControlBridge: NSObject, AVCaptureSessionControlsDelegate {

    /// Called on the main queue when a control moves, with the dial and the
    /// stop it landed on.
    private let onChange: @MainActor (CameraControlDial, Int) -> Void
    /// Called on the main queue as the system HUD comes and goes, so the app
    /// can stand its own chrome down rather than talk over it.
    private let onActiveChange: @MainActor (Bool) -> Void

    /// The controls currently attached, so they can be taken off again cleanly
    /// when the session is reconfigured. Reading `session.controls` back is not
    /// enough — removing controls this object never added would take the
    /// system's own away with them.
    private var attached: [AVCaptureControl] = []

    /// The one queue every control is touched on.
    ///
    /// `AVCaptureControl` is not merely thread-*unsafe*: it asserts. Setting
    /// `selectedIndex` from the wrong queue calls `dispatch_assert_queue`,
    /// which fails hard — the app died with SIGTRAP on the first turn of any
    /// dial, because the app updates its state on the main actor and was
    /// pushing the new stop straight into the picker from there.
    ///
    /// So this is the camera's own serial queue, handed in rather than made
    /// here. Attaching already happens on it, syncing hops onto it, and the
    /// system dispatches its actions to it — one serial queue for all three,
    /// which also means `attached` needs no lock of its own.
    private let queue: DispatchQueue

    init(
        queue: DispatchQueue,
        onChange: @escaping @MainActor (CameraControlDial, Int) -> Void,
        onActiveChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.queue = queue
        self.onChange = onChange
        self.onActiveChange = onActiveChange
        super.init()
    }

    /// Attaches the dials to the session, if this body has the button.
    ///
    /// Returns whether anything was attached, so the caller can log or ignore
    /// rather than assume. Must be called inside a configuration block.
    ///
    /// - Note: `supportsControls` is the runtime half of the gate. iOS 18 on an
    ///   iPhone 15 compiles every line here and answers `false`, which is the
    ///   case that has to stay silent rather than throw.
    @discardableResult
    func attach(to session: AVCaptureSession,
                ladders: [CameraControlDial: CameraControlLadder]) -> Bool {
        detach(from: session)

        guard session.supportsControls else { return false }

        // The system publishes its own ceiling and it is not ours to guess.
        // Four today; if a later body offers more, the extra dial appears on
        // its own without a change here.
        let room = session.maxControlsCount
        guard room > 0 else { return false }

        for dial in CameraControlDial.allCases.prefix(room) {
            guard let ladder = ladders[dial], ladder.count > 1 else { continue }

            let picker = AVCaptureIndexPicker(
                dial.title,
                symbolName: dial.symbol,
                numberOfIndexes: ladder.count,
                localizedTitleTransform: { index in ladder.title(index) }
            )
            // Action queue first, then the value. The queue is what the
            // control asserts against, so it has to know about it before
            // anything is set on it.
            picker.setActionQueue(queue) { [onChange] index in
                Task { @MainActor in onChange(dial, index) }
            }
            picker.selectedIndex = min(max(ladder.selected, 0), ladder.count - 1)

            // Asked, not assumed. A control the session will not take is a
            // control that must not go in `attached`, or detaching later
            // removes something that was never added.
            guard session.canAddControl(picker) else { continue }
            session.addControl(picker)
            attached.append(picker)
        }

        guard !attached.isEmpty else { return false }
        session.setControlsDelegate(self, queue: queue)
        return true
    }

    /// Takes the dials off again. Safe to call on a session that never had any,
    /// which is what makes it safe to call unconditionally before re-attaching.
    func detach(from session: AVCaptureSession) {
        for control in attached where session.controls.contains(where: { $0 === control }) {
            session.removeControl(control)
        }
        attached.removeAll()
    }

    /// Keeps the HUD's idea of each dial in step with the app's, for the times
    /// the value moved on screen rather than under the thumb.
    ///
    /// Called from the main actor — every settings change goes through
    /// `syncCamera` — and hops to the control queue, because that is where a
    /// control may be touched. Reading `selectedIndex` counts as touching it,
    /// so the whole comparison goes across, not just the write.
    func sync(_ ladders: [CameraControlDial: CameraControlLadder]) {
        queue.async { [weak self] in
            guard let self else { return }
            for (dial, control) in zip(CameraControlDial.allCases, self.attached) {
                guard let picker = control as? AVCaptureIndexPicker,
                      let ladder = ladders[dial], ladder.count > 0 else { continue }
                let index = min(max(ladder.selected, 0), ladder.count - 1)
                if picker.selectedIndex != index { picker.selectedIndex = index }
            }
        }
    }

    // MARK: AVCaptureSessionControlsDelegate

    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        Task { @MainActor in onActiveChange(true) }
    }

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        Task { @MainActor in onActiveChange(true) }
    }

    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        Task { @MainActor in onActiveChange(false) }
    }

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        Task { @MainActor in onActiveChange(false) }
    }
}
