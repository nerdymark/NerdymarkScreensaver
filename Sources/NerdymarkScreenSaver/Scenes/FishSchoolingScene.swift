import Cocoa

/// Fish schooling: boids rendered as small triangle "fish" pointing in
/// their movement direction. Soft watery background.
final class FishSchoolingScene: DemoScene {
    static let identifier = "fish_schooling"
    static let displayName = "Fish Schooling"

    static let options: [SceneOption] = [
        .slider(key: "count", label: "Fish Count", min: 30, max: 300, defaultValue: 120, format: "%.0f"),
        .slider(key: "fishSize", label: "Fish Size", min: 4, max: 20, defaultValue: 9, format: "%.0f px"),
        .slider(key: "vision", label: "Vision Radius", min: 30, max: 120, defaultValue: 60, format: "%.0f px"),
        .choice(key: "color", label: "Fish Color",
                choices: ["Orange-Teal", "Silver", "Tropical", "Single (Cyan)"],
                defaultValue: "Orange-Teal"),
    ]

    private var size: CGSize = .zero
    private let fishSize: CGFloat
    private let colorScheme: String
    private var sim: BoidSimulation

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.fishSize = CGFloat(settings.double("fishSize", default: 9))
        self.colorScheme = settings.string("color", default: "Orange-Teal")
        let count = max(10, Int(settings.double("count", default: 120)))
        self.sim = BoidSimulation(count: count, bounds: size)
        sim.visionRadius = settings.double("vision", default: 60)
        sim.alignWeight = 0.06
        sim.cohesionWeight = 0.006
        sim.separationWeight = 0.08
        sim.maxSpeed = 95
        sim.minSpeed = 35
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size else { return }
        size = newSize
        sim.bounds = newSize
    }

    func tick(dt: TimeInterval) {
        sim.tick(dt: dt)
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        // Watery vertical gradient.
        let top = CGColor(red: 0.05, green: 0.30, blue: 0.55, alpha: 1)
        let bottom = CGColor(red: 0.0, green: 0.05, blue: 0.15, alpha: 1)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [top, bottom] as CFArray,
                               locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                    start: CGPoint(x: 0, y: targetSize.height),
                                    end: CGPoint(x: 0, y: 0),
                                    options: [])
        }

        for (i, boid) in sim.boids.enumerated() {
            drawFish(ctx: ctx, boid: boid, size: fishSize, index: i, total: sim.boids.count)
        }
    }

    private func drawFish(ctx: CGContext, boid: BoidSimulation.Boid, size: CGFloat, index: Int, total: Int) {
        let angle = atan2(boid.vy, boid.vx)
        let cx = CGFloat(boid.x)
        let cy = CGFloat(boid.y)

        // Triangle pointing in direction of motion.
        let cosA = CGFloat(cos(angle))
        let sinA = CGFloat(sin(angle))
        let nose = CGPoint(x: cx + cosA * size, y: cy + sinA * size)
        let tail1 = CGPoint(x: cx - cosA * size * 0.6 - sinA * size * 0.5,
                             y: cy - sinA * size * 0.6 + cosA * size * 0.5)
        let tail2 = CGPoint(x: cx - cosA * size * 0.6 + sinA * size * 0.5,
                             y: cy - sinA * size * 0.6 - cosA * size * 0.5)

        ctx.setFillColor(fishColor(index: index, total: total))
        ctx.beginPath()
        ctx.move(to: nose)
        ctx.addLine(to: tail1)
        ctx.addLine(to: tail2)
        ctx.closePath()
        ctx.fillPath()
    }

    private func fishColor(index: Int, total: Int) -> CGColor {
        switch colorScheme {
        case "Silver":
            let v: CGFloat = 0.8 + (CGFloat(index % 7) / 7.0) * 0.2
            return CGColor(red: v, green: v * 1.02, blue: v * 1.05, alpha: 1)
        case "Tropical":
            let hue = CGFloat(index % 8) / 8.0
            return NSColor(hue: hue, saturation: 0.9, brightness: 1.0, alpha: 1).cgColor
        case "Single (Cyan)":
            return CGColor(red: 0.2, green: 0.85, blue: 0.95, alpha: 1)
        default: // Orange-Teal
            return (index % 3 == 0)
                ? CGColor(red: 1.0, green: 0.55, blue: 0.10, alpha: 1)
                : CGColor(red: 0.0, green: 0.75, blue: 0.85, alpha: 1)
        }
    }
}
