import Foundation
import ScreenSaver

/// Thin typed wrapper over ScreenSaverDefaults so callers don't have to
/// remember the `synchronize()` dance and bool/double NSNumber unboxing.
///
/// Why ScreenSaverDefaults instead of UserDefaults: the screensaver runs
/// inside legacyScreenSaver.appex, which has a different bundle identifier
/// than our .saver. ScreenSaverDefaults namespaces under our bundle ID so
/// the configure sheet and the running screensaver read/write the same store.
final class SettingsStore: SettingsBackend {
    static let bundleIdentifier = "com.nerdymark.screensaver"

    // Top-level keys (scene options use scene.<id>.<key> via SceneSettings).
    enum Key {
        static let selectedScene  = "selectedScene"   // String
        static let rotationSeconds = "rotationSeconds" // Double — for "Random" mode
        static let showSceneLabel = "showSceneLabel"  // Bool
    }

    private let defaults: ScreenSaverDefaults

    init(bundleIdentifier: String = SettingsStore.bundleIdentifier) {
        // Force-unwrap is fine here — the only failure mode is a totally
        // unusable framework state; the screensaver wouldn't load at all.
        self.defaults = ScreenSaverDefaults(forModuleWithName: bundleIdentifier)!
    }

    // MARK: - Typed accessors

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

    func set(_ value: Double, for key: String) {
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }

    func set(_ value: Bool, for key: String) {
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }

    func set(_ value: String, for key: String) {
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }

    // MARK: - Scene namespace helper

    func sceneSettings(for sceneIdentifier: String) -> SceneSettings {
        return SceneSettings(store: self, sceneIdentifier: sceneIdentifier)
    }
}
