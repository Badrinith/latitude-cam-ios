//
//  Haptics.swift
//  LatitudeCam
//
//  One vocabulary of touch for the whole camera. The mapping is borrowed from
//  the mechanics it stands in for: rings and ladders click, switches snap, the
//  shutter thumps. Using the same generator for all of them would flatten that
//  distinction and the controls would stop feeling like different objects.
//

import UIKit

@MainActor
enum Haptics {

    /// How hard the whole system hits. The step from Subtle to Standard is a
    /// change of generator, not just amplitude — `selectionChanged()` has no
    /// intensity control and tops out far softer than a rigid impact, which is
    /// why a "louder" detent has to be a different mechanism.
    enum Strength: String, CaseIterable {
        case subtle = "Subtle"
        case standard = "Standard"
        case strong = "Strong"

        var level: CGFloat {
            switch self {
            case .subtle:   return 0.55
            case .standard: return 0.85
            case .strong:   return 1.0
            }
        }
    }

    /// Users who find continuous feedback tiring can switch the whole system off
    /// from Settings; there is no OS-level control for this.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Pref.haptics) as? Bool ?? true
    }

    static var strength: Strength {
        Strength(rawValue: Pref.string(Pref.hapticStrength, default: Strength.strong.rawValue))
            ?? .strong
    }

    private static let selection = UISelectionFeedbackGenerator()
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notice = UINotificationFeedbackGenerator()

    /// Call as a gesture begins. Without it the first click of a drag arrives
    /// late enough to feel disconnected from the finger.
    static func prepare() {
        guard isEnabled else { return }
        selection.prepare()
        rigid.prepare()
        heavy.prepare()
    }

    /// A ring or ladder passing a stop.
    static func detent() {
        guard isEnabled else { return }
        switch strength {
        case .subtle:
            selection.selectionChanged()
        case .standard, .strong:
            rigid.impactOccurred(intensity: strength.level)
        }
    }

    /// A switch flipping — focus peaking, ProRAW, a look toggle.
    static func toggle() {
        guard isEnabled else { return }
        rigid.impactOccurred(intensity: strength.level * 0.9)
    }

    /// Chrome that moves you somewhere rather than changing a value.
    static func tap() {
        guard isEnabled else { return }
        switch strength {
        case .subtle:            soft.impactOccurred(intensity: strength.level)
        case .standard, .strong: light.impactOccurred(intensity: strength.level)
        }
    }

    /// The shutter actuating. Always the heaviest thing in the app so it is
    /// unmistakable without looking; at full strength a second, lighter beat
    /// follows it the way a mirror returns after the exposure.
    static func shutter() {
        guard isEnabled else { return }
        heavy.impactOccurred(intensity: max(0.8, strength.level))

        guard strength == .strong else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(55))
            light.impactOccurred(intensity: 0.7)
        }
    }

    static func success() {
        guard isEnabled else { return }
        notice.notificationOccurred(.success)
    }

    /// The shutter was pressed but there was nothing to record.
    static func blocked() {
        guard isEnabled else { return }
        notice.notificationOccurred(.warning)
    }
}
