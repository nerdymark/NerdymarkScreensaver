import Cocoa

/// Bug swarm: tighter, faster boids rendered as glowing dots with motion-
/// blur trails. Like fireflies in a chaotic vortex.
final class BugSwarmScene: DemoScene {
    static let identifier = "bug_swarm"
    static let displayName = "Bug Swarm"

    static let options: [SceneOption] = [
        .slider(key: "count", label: "Bug Count", min: 50, max: 500, defaultValue: 220, format: "%.0f"),
        .slider(key: "trailLength", label: "Trail Length", min: 0.85, max: 0.99, defaultValue: 0.94, format: "%.2f"),
        .slider(key: "vision", label: "Vision Radius", min: 20, max: 100, defaultValue: 40, format: "%.0f px"),
        .choice(key: "color", label: "Glow Color",
                choices: ["Firefly", "Plasma", "Ghost Blue", "Hot Pink"],
                defaultValue: "Firefly"),
    ]

    private var size: CGSize = .zero
    private let trailLen: Double
    private let colorScheme: String
    private var sim: BoidSimulation
    private var trailLayer: CGContext?
    private var trailColorSpace = CGColorSpaceCreateDeviceRGB()

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.trailLen = settings.double("trailLength", default: 0.94)
        self.colorScheme = settings.string("color", default: "Firefly")
        let count = max(20, Int(settings.double("count", default: 220)))
        self.sim = BoidSimulation(count: count, bounds: size)
        sim.visionRadius = settings.double("vision", default: 40)
        sim.alignWeight = 0.10
        sim.cohesionWeight = 0.012
        sim.separationWeight = 0.04
        sim.maxSpeed = 130
        sim.minSpeed = 50
        recreateTrailLayer()
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size else { return }
        size = newSize
        sim.bounds = newSize
        recreateTrailLayer()
    }

    func tick(dt: TimeInterval) {
        sim.tick(dt: dt)
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let trail = trailLayer else { return }

        // Fade existing trail.
        let fadeAlpha = CGFloat(1.0 - trailLen)
        trail.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: fadeAlpha))
        trail.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        // Draw bugs into trail layer with screen blend.
        trail.setBlendMode(.screen)
        for boid in sim.boids {
            let radius: CGFloat = 1.8
            let cx = CGFloat(boid.x), cy = CGFloat(boid.y)
            trail.setFillColor(bugColor())
            trail.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
        }
        trail.setBlendMode(.normal)

        // Composite trail into the screensaver context.
        if let img = trail.makeImage() {
            ctx.draw(img, in: CGRect(origin: .zero, size: targetSize))
        }
    }

    // MARK: - Setup

    private func recreateTrailLayer() {
        let w = max(1, Int(size.width))
        let h = max(1, Int(size.height))
        trailLayer = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: trailColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        // Start opaque black.
        trailLayer?.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        trailLayer?.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }

    private func bugColor() -> CGColor {
        switch colorScheme {
        case "Plasma":
            return CGColor(red: 0.95, green: 0.45, blue: 0.95, alpha: 1)
        case "Ghost Blue":
            return CGColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
        case "Hot Pink":
            return CGColor(red: 1.0, green: 0.25, blue: 0.55, alpha: 1)
        default: // Firefly
            return CGColor(red: 1.0, green: 0.95, blue: 0.45, alpha: 1)
        }
    }
}
