import Foundation

/// SettingsBackend implementation for the windowed demo app. Uses a regular
/// UserDefaults suite (no ScreenSaverDefaults / ScreenSaver framework needed),
/// so it can be linked into a plain .app target without dragging in the
/// screensaver-specific ScreenSaver.framework.
final class DemoSettingsStore: SettingsBackend {
    private let defaults: UserDefaults

    init(suiteName: String = "com.nerdymark.screensaver.demo") {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func double(_ key: String, default fallback: Double) -> Double {
        if defaults.object(forKey: key) == nil { return fallback }
        return defaults.double(forKey: key)
    }

    func bool(_ key: String, default fallback: Bool) -> Bool {
        if defaults.object(forKey: key) == nil { return fallback }
        return defaults.bool(forKey: key)
    }

    func string(_ key: String, default fallback: String) -> String {
        return defaults.string(forKey: key) ?? fallback
    }
}
