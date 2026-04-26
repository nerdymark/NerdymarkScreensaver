import Cocoa

/// A spotlight that wanders around revealing a hidden message. The "hidden"
/// content is a tiled "nerdymark.com" pattern — only what the spotlight
/// touches is visible; everywhere else is dark.
final class SearchLightScene: DemoScene {
    static let identifier = "search_light"
    static let displayName = "Search Light"

    static let options: [SceneOption] = [
        .slider(key: "lightRadius", label: "Light Radius", min: 80, max: 400, defaultValue: 180, format: "%.0f px"),
        .slider(key: "speed", label: "Light Speed", min: 0.2, max: 2.0, defaultValue: 0.5, format: "%.1f"),
        .toggle(key: "glow", label: "Soft halo", defaultValue: true),
        .text(key: "message", label: "Hidden Text", defaultValue: "nerdymark.com  ★  ", placeholder: "Tiled message…"),
    ]

    private var size: CGSize = .zero
    private let lightRadius: CGFloat
    private let speed: Double
    private let glow: Bool
    private let wordmark: String
    private var elapsed: Double = 0
    private var pos: CGPoint = .zero
    private var velocity: CGPoint = .init(x: 1, y: 1)

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.lightRadius = CGFloat(settings.double("lightRadius", default: 180))
        self.speed = settings.double("speed", default: 0.5)
        self.glow = settings.bool("glow", default: true)
        let m = settings.string("message", default: "")
        self.wordmark = m.isEmpty ? "nerdymark.com  ★  " : m
        let angle = Double.random(in: 0..<(2 * Double.pi))
        velocity = CGPoint(x: cos(angle), y: sin(angle))
        pos = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) {
        elapsed += dt
        let dist = CGFloat(speed * 200 * dt)
        pos.x += velocity.x * dist
        pos.y += velocity.y * dist
        if pos.x < lightRadius { pos.x = lightRadius; velocity.x = abs(velocity.x) }
        else if pos.x > size.width - lightRadius { pos.x = size.width - lightRadius; velocity.x = -abs(velocity.x) }
        if pos.y < lightRadius { pos.y = lightRadius; velocity.y = abs(velocity.y) }
        else if pos.y > size.height - lightRadius { pos.y = size.height - lightRadius; velocity.y = -abs(velocity.y) }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        // Black base.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Render hidden content into an offscreen bitmap and clip to the
        // spotlight circle when copying it onto the screen.
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: pos.x - lightRadius, y: pos.y - lightRadius,
                                    width: lightRadius * 2, height: lightRadius * 2))
        ctx.clip()
        drawHiddenContent(ctx: ctx, targetSize: targetSize)
        ctx.restoreGState()

        // Soft halo just outside the lit circle.
        if glow {
            let highlight = CGColor(red: 1, green: 0.95, blue: 0.7, alpha: 0.25)
            let transparent = CGColor(red: 1, green: 0.95, blue: 0.7, alpha: 0)
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [highlight, transparent] as CFArray,
                                   locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: pos, startRadius: lightRadius * 0.85,
                                         endCenter: pos, endRadius: lightRadius * 1.4,
                                         options: [])
            }
        }

        // Subtle light edge.
        ctx.setStrokeColor(CGColor(red: 1, green: 0.95, blue: 0.7, alpha: 0.4))
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: CGRect(x: pos.x - lightRadius, y: pos.y - lightRadius,
                                       width: lightRadius * 2, height: lightRadius * 2))
    }

    private func drawHiddenContent(ctx: CGContext, targetSize: CGSize) {
        // Soft daylight gradient + tiled wordmark.
        let top = CGColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1)
        let bot = CGColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [top, bot] as CFArray,
                               locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: targetSize.height),
                                    end: CGPoint(x: 0, y: 0), options: [])
        }

        let font = NSFont.systemFont(ofSize: 28, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.95, alpha: 0.85),
        ]
        let str = NSAttributedString(string: wordmark, attributes: attrs)
        let lineH = str.size().height * 1.4
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        var y: CGFloat = 0
        var rowIdx = 0
        while y < targetSize.height + lineH {
            var x: CGFloat = (rowIdx % 2 == 0 ? 0 : -str.size().width / 2)
            while x < targetSize.width {
                str.draw(at: CGPoint(x: x, y: y))
                x += str.size().width
            }
            y += lineH
            rowIdx += 1
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
