import Cocoa
import ScreenSaver
import os.log

private let log = OSLog(subsystem: "com.nerdymark.screensaver", category: "screensaver")

/// Native (no WebView) screensaver. Renders a `DemoScene` per frame using
/// Core Graphics. Supports per-scene configuration via the configure sheet,
/// plus a "random" rotation mode that cycles through every registered scene.
@objc(NerdymarkScreenSaverView)
final class NerdymarkScreenSaverView: ScreenSaverView {

    private let settings = SettingsStore()
    private var configureController: ConfigureSheetController?

    // Active scene state.
    private var currentScene: DemoScene?
    private var currentSceneType: DemoScene.Type?
    private var randomScenesShuffled: [DemoScene.Type] = []
    private var randomSceneIndex: Int = 0
    private var rotationAccumulator: TimeInterval = 0
    private var lastTickTime: TimeInterval = 0

    // MARK: - Lifecycle

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func startAnimation() {
        super.startAnimation()
        os_log("startAnimation, bounds=%{public}@", log: log, type: .info, NSStringFromRect(bounds))
        loadInitialScene()
    }

    override func stopAnimation() {
        super.stopAnimation()
        currentScene = nil
        currentSceneType = nil
    }

    // MARK: - Scene selection

    private func loadInitialScene() {
        let selection = settings.string(SettingsStore.Key.selectedScene, default: SceneRegistry.defaultSelection)
        if selection == SceneRegistry.randomIdentifier {
            randomScenesShuffled = SceneRegistry.allScenes.shuffled()
            randomSceneIndex = 0
            rotationAccumulator = 0
            if let first = randomScenesShuffled.first {
                instantiate(first)
            }
        } else if let sceneType = SceneRegistry.scene(for: selection) {
            instantiate(sceneType)
        } else if let fallback = SceneRegistry.allScenes.first {
            instantiate(fallback)
        }
    }

    private func instantiate(_ sceneType: DemoScene.Type) {
        let sceneSettings = settings.sceneSettings(for: sceneType.identifier)
        currentScene = sceneType.init(size: bounds.size, settings: sceneSettings)
        currentSceneType = sceneType
        os_log("Loaded scene: %{public}@", log: log, type: .info, sceneType.displayName)
        needsDisplay = true
    }

    private func advanceRandomSceneIfNeeded(dt: TimeInterval) {
        let selection = settings.string(SettingsStore.Key.selectedScene, default: SceneRegistry.defaultSelection)
        guard selection == SceneRegistry.randomIdentifier else { return }

        rotationAccumulator += dt
        let interval = settings.double(SettingsStore.Key.rotationSeconds, default: 90)
        if rotationAccumulator >= interval {
            rotationAccumulator = 0
            randomSceneIndex = (randomSceneIndex + 1) % max(1, randomScenesShuffled.count)
            if randomScenesShuffled.indices.contains(randomSceneIndex) {
                instantiate(randomScenesShuffled[randomSceneIndex])
            }
        }
    }

    // MARK: - Animation

    override func animateOneFrame() {
        // Compute dt from real time to keep movement consistent even if the
        // animation timer slips under load.
        let now = CACurrentMediaTime()
        let dt = lastTickTime == 0 ? animationTimeInterval : min(0.1, now - lastTickTime)
        lastTickTime = now

        advanceRandomSceneIfNeeded(dt: dt)

        currentScene?.tick(dt: dt)
        needsDisplay = true
    }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = bounds.size
        currentScene?.resize(s)
        currentScene?.draw(in: ctx, size: s)

        // Optional scene-name label in the corner.
        if settings.bool(SettingsStore.Key.showSceneLabel, default: true),
           let name = currentSceneType?.displayName {
            drawSceneLabel(name, in: ctx, size: s)
        }
    }

    private func drawSceneLabel(_ text: String, in ctx: CGContext, size: CGSize) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.25),
        ]
        let str = NSAttributedString(string: text.uppercased(), attributes: attrs)
        let textSize = str.size()
        let pad: CGFloat = 18
        let rect = CGRect(x: size.width - textSize.width - pad,
                          y: pad,
                          width: textSize.width,
                          height: textSize.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Configure sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        if configureController == nil {
            configureController = ConfigureSheetController(settings: settings)
        }
        // Re-instantiate the active scene when the sheet closes so option
        // changes take effect immediately rather than next launch.
        return configureController?.window
    }
}
