import Cocoa

/// Declarative description of a tunable knob a scene exposes to the user.
/// Each option becomes a row in the configure sheet's per-scene panel and is
/// persisted to ScreenSaverDefaults under the scene's identifier.
enum SceneOption {
    case slider(key: String, label: String, min: Double, max: Double, defaultValue: Double, format: String)
    case toggle(key: String, label: String, defaultValue: Bool)
    case choice(key: String, label: String, choices: [String], defaultValue: String)
    case text(key: String, label: String, defaultValue: String, placeholder: String)

    var key: String {
        switch self {
        case .slider(let k, _, _, _, _, _): return k
        case .toggle(let k, _, _):          return k
        case .choice(let k, _, _, _):       return k
        case .text(let k, _, _, _):         return k
        }
    }

    var label: String {
        switch self {
        case .slider(_, let l, _, _, _, _): return l
        case .toggle(_, let l, _):          return l
        case .choice(_, let l, _, _):       return l
        case .text(_, let l, _, _):         return l
        }
    }
}

/// Read-only settings backend. Implemented by `SettingsStore` (real, uses
/// ScreenSaverDefaults) in the .saver target and `DemoSettingsStore` (uses
/// UserDefaults) in the windowed demo app target. Lets `SceneSettings` work
/// without depending on the ScreenSaver framework directly.
protocol SettingsBackend: AnyObject {
    func double(_ key: String, default fallback: Double) -> Double
    func bool(_ key: String, default fallback: Bool) -> Bool
    func string(_ key: String, default fallback: String) -> String
}

/// Read-only typed view onto a single scene's settings, namespaced under its
/// identifier so two scenes can use the same option key without colliding.
struct SceneSettings {
    let store: SettingsBackend
    let sceneIdentifier: String

    private func ns(_ key: String) -> String {
        return "scene.\(sceneIdentifier).\(key)"
    }

    func double(_ key: String, default fallback: Double) -> Double {
        return store.double(ns(key), default: fallback)
    }
    func bool(_ key: String, default fallback: Bool) -> Bool {
        return store.bool(ns(key), default: fallback)
    }
    func string(_ key: String, default fallback: String) -> String {
        return store.string(ns(key), default: fallback)
    }
}

/// A single drawable scene. Implementations should be cheap to instantiate
/// (init = setup, not work) and resilient to resize / tick after init order.
///
/// Add new scenes by:
///   1. Implementing this protocol on a new file in Scenes/
///   2. Registering the type in SceneRegistry.allScenes
/// That's all — the configure sheet, persistence, and rotator pick it up
/// automatically.
protocol DemoScene: AnyObject {
    /// Stable identifier used in defaults keys. Don't change after release.
    static var identifier: String { get }

    /// User-facing name shown in the picker.
    static var displayName: String { get }

    /// Knobs surfaced in the configure sheet (and persisted).
    /// Return [] for a scene with no user-tunable options.
    static var options: [SceneOption] { get }

    init(size: CGSize, settings: SceneSettings)

    /// Called when the screen / window resizes. Recreate any size-dependent
    /// buffers here.
    func resize(_ size: CGSize)

    /// Advance scene state by `dt` seconds. Called from animateOneFrame.
    func tick(dt: TimeInterval)

    /// Render the current state into the supplied context (already clipped
    /// and translated to the view's bounds). Avoid expensive allocations here.
    func draw(in context: CGContext, size: CGSize)
}
