import Cocoa

/// Amiga "copper bars": horizontal stripes of vertically-graded color that
/// move up and down with sine waves. Multiple bars overlap with screen
/// blending. The Copper coprocessor of the Amiga 500 could change palette
/// per scanline, allowing this effect on hardware that "couldn't" do
/// gradients.
final class CopperBarsScene: DemoScene {
    static let identifier = "copper_bars"
    static let displayName = "Copper Bars"

    static let options: [SceneOption] = [
        .slider(key: "barCount", label: "Bar Count", min: 3, max: 12, defaultValue: 6, format: "%.0f"),
        .slider(key: "barHeight", label: "Bar Height", min: 30, max: 120, defaultValue: 60, format: "%.0f px"),
        .slider(key: "speed", label: "Sine Speed", min: 0.2, max: 3, defaultValue: 1.0, format: "%.1fx"),
        .toggle(key: "showStarfield", label: "Add starfield behind", defaultValue: true),
    ]

    private struct Bar {
        var hue: Double
        var phaseOffset: Double
        var freq: Double
    }
    private struct BgStar { var x: Double; var y: Double; var brightness: Double }

    private var size: CGSize = .zero
    private let barCount: Int
    private let barHeight: CGFloat
    private let speed: Double
    private let showStars: Bool
    private var bars: [Bar] = []
    private var stars: [BgStar] = []
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.barCount = max(2, Int(settings.double("barCount", default: 6)))
        self.barHeight = CGFloat(settings.double("barHeight", default: 60))
        self.speed = settings.double("speed", default: 1.0)
        self.showStars = settings.bool("showStarfield", default: true)

        bars = (0..<barCount).map { i in
            Bar(
                hue: Double(i) / Double(barCount),
                phaseOffset: Double.random(in: 0..<(2.0 * Double.pi)),
                freq: Double.random(in: 0.4...1.4)
            )
        }
        stars = (0..<200).map { _ in
            BgStar(x: Double.random(in: 0...Double(size.width)),
                    y: Double.random(in: 0...Double(size.height)),
                    brightness: Double.random(in: 0.2...0.9))
        }
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize

        // Black + faint static starfield base (the "space" that copper bars
        // famously got drawn over).
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0.02, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        if showStars {
            for s in stars {
                let alpha = s.brightness * (0.5 + 0.5 * sin(elapsed * 2 + s.x * 0.01))
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
                ctx.fill(CGRect(x: s.x, y: s.y, width: 1.5, height: 1.5))
            }
        }

        // Draw each bar at its current y position with a vertical gradient.
        ctx.setBlendMode(.screen)   // bars blend additively
        for bar in bars {
            let yCenter = (sin(elapsed * speed * bar.freq + bar.phaseOffset) * 0.4 + 0.5) * Double(targetSize.height)
            let topY = CGFloat(yCenter) - barHeight / 2
            drawBar(ctx: ctx, top: topY, hue: bar.hue, width: targetSize.width)
        }
        ctx.setBlendMode(.normal)
    }

    private func drawBar(ctx: CGContext, top: CGFloat, hue: Double, width: CGFloat) {
        // Vertical gradient: dark at edges, bright at middle, then dark again.
        let highlightColor = NSColor(hue: CGFloat(hue), saturation: 0.85, brightness: 1.0, alpha: 1).cgColor
        let darkColor = NSColor(hue: CGFloat(hue), saturation: 0.85, brightness: 0.0, alpha: 1).cgColor

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [darkColor, highlightColor, darkColor] as CFArray,
            locations: [0.0, 0.5, 1.0]
        ) else { return }

        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: top, width: width, height: barHeight))
        ctx.drawLinearGradient(gradient,
                                start: CGPoint(x: 0, y: top),
                                end: CGPoint(x: 0, y: top + barHeight),
                                options: [])
        ctx.restoreGState()
    }
}
