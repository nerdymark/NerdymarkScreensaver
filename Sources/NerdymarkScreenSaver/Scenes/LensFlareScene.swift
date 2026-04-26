import Cocoa

/// Lens flare: a moving "sun" with a chain of scaled-down hexagonal flare
/// disks running through the opposite-corner direction. Calmer than most
/// scenes — slow drift, slow rotation, classic camera-lens vibe.
final class LensFlareScene: DemoScene {
    static let identifier = "lens_flare"
    static let displayName = "Lens Flare"

    static let options: [SceneOption] = [
        .slider(key: "sunSize", label: "Sun Size", min: 40, max: 200, defaultValue: 90, format: "%.0f px"),
        .slider(key: "speed", label: "Drift Speed", min: 0.05, max: 1.0, defaultValue: 0.2, format: "%.2f"),
        .slider(key: "discCount", label: "Flare Discs", min: 4, max: 14, defaultValue: 8, format: "%.0f"),
        .choice(key: "tint", label: "Tint",
                choices: ["Warm", "Cool", "Magenta", "Lime"],
                defaultValue: "Warm"),
    ]

    private var size: CGSize = .zero
    private let sunSize: CGFloat
    private let speed: Double
    private let discCount: Int
    private let tint: String
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.sunSize = CGFloat(settings.double("sunSize", default: 90))
        self.speed = settings.double("speed", default: 0.2)
        self.discCount = max(2, Int(settings.double("discCount", default: 8)))
        self.tint = settings.string("tint", default: "Warm")
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        // Dark gradient background (think: dim room, sun outside window).
        let top = CGColor(red: 0.06, green: 0.04, blue: 0.10, alpha: 1)
        let bot = CGColor(red: 0.0, green: 0.0, blue: 0.02, alpha: 1)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [top, bot] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: targetSize.height),
                                    end: CGPoint(x: 0, y: 0), options: [])
        }

        let sunPos = sunPosition(in: targetSize)
        let center = CGPoint(x: targetSize.width / 2, y: targetSize.height / 2)
        let dx = center.x - sunPos.x
        let dy = center.y - sunPos.y

        // The "sun" itself — bright radial highlight.
        drawRadial(ctx: ctx, center: sunPos, radius: sunSize * 1.3, color: tintColor(brightness: 1.0))
        ctx.setBlendMode(.screen)

        // Flare discs along the sun → opposite-corner line.
        for i in 0..<discCount {
            let t = Double(i) / Double(discCount)
            let pos = CGPoint(x: sunPos.x + CGFloat(t * 2.0) * dx,
                               y: sunPos.y + CGFloat(t * 2.0) * dy)
            let r = sunSize * (0.15 + CGFloat(sin(elapsed * 0.5 + Double(i))) * 0.1 + CGFloat(t) * 0.2)
            let alpha = CGFloat(0.5 - t * 0.4)
            let baseColor = tintColor(brightness: alpha)
            drawHexFlare(ctx: ctx, center: pos, radius: r, color: baseColor)
        }
        ctx.setBlendMode(.normal)
    }

    // MARK: - Helpers

    private func sunPosition(in s: CGSize) -> CGPoint {
        // Slow circular drift around the upper-right area.
        let cx = s.width * 0.7 + sin(elapsed * speed) * s.width * 0.18
        let cy = s.height * 0.8 + cos(elapsed * speed * 1.3) * s.height * 0.1
        return CGPoint(x: cx, y: cy)
    }

    private func tintColor(brightness: CGFloat) -> CGColor {
        switch tint {
        case "Cool":    return CGColor(red: brightness * 0.5, green: brightness * 0.85, blue: brightness, alpha: 1)
        case "Magenta": return CGColor(red: brightness, green: brightness * 0.4, blue: brightness * 0.95, alpha: 1)
        case "Lime":    return CGColor(red: brightness * 0.7, green: brightness, blue: brightness * 0.3, alpha: 1)
        default:        return CGColor(red: brightness, green: brightness * 0.85, blue: brightness * 0.55, alpha: 1)
        }
    }

    private func drawRadial(ctx: CGContext, center: CGPoint, radius: CGFloat, color: CGColor) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [color, color.copy(alpha: 0)!] as CFArray,
                                  locations: [0, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                                 endCenter: center, endRadius: radius, options: [])
    }

    private func drawHexFlare(ctx: CGContext, center: CGPoint, radius: CGFloat, color: CGColor) {
        // Hexagonal aperture shape (6 sides) for the iris look.
        let sides = 6
        ctx.beginPath()
        for i in 0..<sides {
            let angle = Double(i) * (2 * Double.pi / Double(sides)) + Double.pi / 6
            let x = center.x + CGFloat(cos(angle)) * radius
            let y = center.y + CGFloat(sin(angle)) * radius
            if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) }
            else      { ctx.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.closePath()
        ctx.setFillColor(color)
        ctx.fillPath()
    }
}
