import Cocoa

/// Bubbles rising in water. Each bubble has a sin-wave horizontal wobble
/// and a slight size variation; they pop (small flash) at the top.
final class BubblesScene: DemoScene {
    static let identifier = "bubbles"
    static let displayName = "Bubbles"

    static let options: [SceneOption] = [
        .slider(key: "count", label: "Bubble Count", min: 20, max: 300, defaultValue: 80, format: "%.0f"),
        .slider(key: "speed", label: "Rise Speed", min: 0.3, max: 3.0, defaultValue: 1.0, format: "%.1fx"),
        .slider(key: "wobble", label: "Wobble", min: 0, max: 60, defaultValue: 24, format: "%.0f px"),
        .choice(key: "tint", label: "Tint",
                choices: ["Aqua", "Sunset", "Forest", "Cosmic"],
                defaultValue: "Aqua"),
    ]

    private struct Bubble {
        var x: Double
        var y: Double
        var radius: Double
        var phase: Double
        var phaseSpeed: Double
        var hueOffset: Double
        var popping: Bool
        var popUntil: TimeInterval
    }

    private var size: CGSize = .zero
    private var bubbles: [Bubble] = []
    private let count: Int
    private let speed: Double
    private let wobble: Double
    private let tint: String
    private var elapsed: TimeInterval = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.count = max(10, Int(settings.double("count", default: 80)))
        self.speed = settings.double("speed", default: 1.0)
        self.wobble = settings.double("wobble", default: 24)
        self.tint = settings.string("tint", default: "Aqua")
        spawn()
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) {
        elapsed += dt
        for i in bubbles.indices {
            if bubbles[i].popping {
                if elapsed > bubbles[i].popUntil {
                    respawn(at: i, fromBottom: true)
                }
                continue
            }
            // Rise and wobble.
            let depthFactor = 1.0 + bubbles[i].radius * 0.05  // bigger bubbles rise faster
            bubbles[i].y -= dt * 60.0 * speed * depthFactor
            bubbles[i].phase += dt * bubbles[i].phaseSpeed

            // Pop when reaching surface.
            if bubbles[i].y < bubbles[i].radius * 1.5 {
                bubbles[i].popping = true
                bubbles[i].popUntil = elapsed + 0.18
            }
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            size = targetSize
        }

        // Underwater gradient background.
        let (top, bottom) = backgroundColors()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [top, bottom] as CFArray,
                                      locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                    start: CGPoint(x: 0, y: targetSize.height),
                                    end: CGPoint(x: 0, y: 0),
                                    options: [])
        }

        for bubble in bubbles {
            let drawX = bubble.x + sin(bubble.phase) * wobble
            let r = bubble.radius
            let center = CGPoint(x: drawX, y: bubble.y)

            if bubble.popping {
                // Brief expanding ring.
                let progress = max(0, min(1, (bubble.popUntil - elapsed) / 0.18))
                let popR = r * (1.0 + (1.0 - progress) * 1.5)
                let alpha = progress
                ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: CGRect(x: center.x - popR, y: center.y - popR, width: popR * 2, height: popR * 2))
                continue
            }

            // Bubble body — slightly translucent fill + bright highlight.
            let bodyColor = bubbleColor(hueOffset: bubble.hueOffset, alpha: 0.55)
            ctx.setFillColor(bodyColor)
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

            // Highlight (top-left small white circle).
            let hlR = r * 0.30
            let hl = CGRect(x: center.x - r * 0.45, y: center.y + r * 0.35, width: hlR * 2, height: hlR * 2)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.6))
            ctx.fillEllipse(in: hl)

            // Outline.
            let outline = CGColor(red: 1, green: 1, blue: 1, alpha: 0.35)
            ctx.setStrokeColor(outline)
            ctx.setLineWidth(1.0)
            ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
    }

    // MARK: - Setup

    private func spawn() {
        bubbles = (0..<count).map { _ in
            makeBubble(yOverride: Double.random(in: 0...Double(size.height)))
        }
    }

    private func respawn(at i: Int, fromBottom: Bool) {
        bubbles[i] = makeBubble(yOverride: fromBottom ? Double(size.height) + 20 : Double.random(in: 0...Double(size.height)))
    }

    private func makeBubble(yOverride: Double) -> Bubble {
        return Bubble(
            x: Double.random(in: 20...Double(size.width) - 20),
            y: yOverride,
            radius: Double.random(in: 4...18),
            phase: Double.random(in: 0..<(2.0 * .pi)),
            phaseSpeed: Double.random(in: 0.6...2.4),
            hueOffset: Double.random(in: -0.05...0.05),
            popping: false,
            popUntil: 0
        )
    }

    // MARK: - Colors

    private func backgroundColors() -> (CGColor, CGColor) {
        switch tint {
        case "Sunset":
            return (CGColor(red: 0.5, green: 0.18, blue: 0.4, alpha: 1),
                    CGColor(red: 0.10, green: 0.05, blue: 0.25, alpha: 1))
        case "Forest":
            return (CGColor(red: 0.10, green: 0.30, blue: 0.20, alpha: 1),
                    CGColor(red: 0.02, green: 0.08, blue: 0.05, alpha: 1))
        case "Cosmic":
            return (CGColor(red: 0.30, green: 0.10, blue: 0.50, alpha: 1),
                    CGColor(red: 0.02, green: 0.0, blue: 0.10, alpha: 1))
        default: // Aqua
            return (CGColor(red: 0.10, green: 0.40, blue: 0.55, alpha: 1),
                    CGColor(red: 0.02, green: 0.06, blue: 0.12, alpha: 1))
        }
    }

    private func bubbleColor(hueOffset: Double, alpha: CGFloat) -> CGColor {
        let baseHue: CGFloat
        switch tint {
        case "Sunset":  baseHue = 0.92
        case "Forest":  baseHue = 0.35
        case "Cosmic":  baseHue = 0.78
        default:        baseHue = 0.55
        }
        let h = (baseHue + CGFloat(hueOffset)).truncatingRemainder(dividingBy: 1.0)
        return NSColor(hue: h, saturation: 0.5, brightness: 1.0, alpha: alpha).cgColor
    }
}
