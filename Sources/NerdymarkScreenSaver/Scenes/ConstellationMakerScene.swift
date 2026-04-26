import Cocoa

/// Constellation maker: drifting stars; whenever two stars get close enough
/// they're connected by a faint line. Lines fade if the stars drift apart.
/// Slowly forms and dissolves geometric patterns.
final class ConstellationMakerScene: DemoScene {
    static let identifier = "constellation_maker"
    static let displayName = "Constellation"

    static let options: [SceneOption] = [
        .slider(key: "starCount", label: "Star Count", min: 30, max: 200, defaultValue: 90, format: "%.0f"),
        .slider(key: "linkDist", label: "Link Distance", min: 60, max: 300, defaultValue: 150, format: "%.0f px"),
        .slider(key: "speed", label: "Drift Speed", min: 5, max: 80, defaultValue: 25, format: "%.0f px/s"),
        .toggle(key: "showHaze", label: "Show nebula glow", defaultValue: true),
        .choice(key: "palette", label: "Palette",
                choices: ["Classic", "Cool Blue", "Warm Amber", "Magenta"],
                defaultValue: "Classic"),
    ]

    private struct Star {
        var x: CGFloat; var y: CGFloat
        var vx: CGFloat; var vy: CGFloat
        var brightness: CGFloat
    }

    private var size: CGSize = .zero
    private let starCount: Int
    private let linkDist: CGFloat
    private let speed: CGFloat
    private let showHaze: Bool
    private let paletteName: String

    private var stars: [Star] = []
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.starCount = max(10, Int(settings.double("starCount", default: 90)))
        self.linkDist = CGFloat(settings.double("linkDist", default: 150))
        self.speed = CGFloat(settings.double("speed", default: 25))
        self.showHaze = settings.bool("showHaze", default: true)
        self.paletteName = settings.string("palette", default: "Classic")
        seedStars()
    }

    func resize(_ newSize: CGSize) {
        if newSize != size {
            size = newSize
            seedStars()
        }
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        for i in 0..<stars.count {
            stars[i].x += stars[i].vx * CGFloat(dt)
            stars[i].y += stars[i].vy * CGFloat(dt)
            // Wrap.
            if stars[i].x < 0 { stars[i].x += size.width }
            else if stars[i].x > size.width { stars[i].x -= size.width }
            if stars[i].y < 0 { stars[i].y += size.height }
            else if stars[i].y > size.height { stars[i].y -= size.height }
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        // Sky.
        let top = CGColor(red: 0.04, green: 0.04, blue: 0.12, alpha: 1)
        let bot = CGColor(red: 0.0, green: 0.0, blue: 0.04, alpha: 1)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [bot, top] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0),
                                    end: CGPoint(x: 0, y: targetSize.height), options: [])
        }

        // Optional nebula glow background.
        if showHaze {
            let hazeColor = paletteColor().copy(alpha: 0.05) ?? paletteColor()
            ctx.setFillColor(hazeColor)
            for i in stride(from: 0, to: 6, by: 1) {
                let cx = CGFloat(sin(elapsed * 0.05 + Double(i)) * 0.4 + 0.5) * targetSize.width
                let cy = CGFloat(cos(elapsed * 0.04 + Double(i) * 0.7) * 0.4 + 0.5) * targetSize.height
                let r: CGFloat = 200
                if let rg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [hazeColor, hazeColor.copy(alpha: 0)!] as CFArray,
                                        locations: [0, 1]) {
                    ctx.drawRadialGradient(rg, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                            endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
                }
            }
        }

        // Lines between close stars (alpha falls off with distance).
        let baseColor = paletteColor()
        for i in 0..<stars.count {
            for j in (i + 1)..<stars.count {
                let dx = stars[i].x - stars[j].x
                let dy = stars[i].y - stars[j].y
                let d = sqrt(dx * dx + dy * dy)
                if d < linkDist {
                    let alpha = (1 - d / linkDist) * 0.6
                    ctx.setStrokeColor(baseColor.copy(alpha: alpha) ?? baseColor)
                    ctx.setLineWidth(0.7)
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: stars[i].x, y: stars[i].y))
                    ctx.addLine(to: CGPoint(x: stars[j].x, y: stars[j].y))
                    ctx.strokePath()
                }
            }
        }

        // Stars on top.
        for s in stars {
            let twinkle = 0.7 + 0.3 * sin(elapsed * 1.5 + Double(s.x) * 0.1)
            let r: CGFloat = 1.5 + s.brightness * 1.5
            let color = baseColor.copy(alpha: s.brightness * CGFloat(twinkle)) ?? baseColor
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2))
        }
    }

    // MARK: - Helpers

    private func seedStars() {
        stars = (0..<starCount).map { _ in
            let angle = Double.random(in: 0..<(2 * .pi))
            return Star(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height),
                vx: CGFloat(cos(angle)) * speed,
                vy: CGFloat(sin(angle)) * speed,
                brightness: CGFloat.random(in: 0.4...1.0)
            )
        }
    }

    private func paletteColor() -> CGColor {
        switch paletteName {
        case "Cool Blue": return CGColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 1)
        case "Warm Amber": return CGColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1)
        case "Magenta":   return CGColor(red: 1.0, green: 0.5, blue: 0.85, alpha: 1)
        default:          return CGColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 1)
        }
    }
}
