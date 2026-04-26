import Cocoa
import QuartzCore

/// Hosts a `DemoScene` inside a regular NSView so screensaver scenes can be
/// previewed in a window (and screenshotted/recorded) without going through
/// macOS's ScreenSaverEngine. Drives tick + draw at ~60Hz via a Timer.
final class DemoView: NSView {

    private(set) var currentScene: DemoScene?
    private(set) var currentSceneType: DemoScene.Type?
    private let settings = DemoSettingsStore()
    private var timer: Timer?
    private var lastTickTime: TimeInterval = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        if let first = SceneRegistry.allScenes.first {
            select(first)
        }
        startAnimation()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { timer?.invalidate() }

    func select(_ sceneType: DemoScene.Type) {
        let sceneSettings = SceneSettings(store: settings, sceneIdentifier: sceneType.identifier)
        currentScene = sceneType.init(size: bounds.size, settings: sceneSettings)
        currentSceneType = sceneType
        lastTickTime = 0
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        currentScene?.resize(newSize)
    }

    private func startAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTickTime == 0 ? (1.0 / 60.0) : min(0.1, now - lastTickTime)
        lastTickTime = now
        currentScene?.tick(dt: dt)
        needsDisplay = true
    }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        currentScene?.resize(bounds.size)
        currentScene?.draw(in: ctx, size: bounds.size)
    }

    override var isFlipped: Bool { false }
}
