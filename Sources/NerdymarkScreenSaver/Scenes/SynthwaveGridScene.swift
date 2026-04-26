import Cocoa

/// Synthwave grid: a perspective floor of glowing magenta/cyan grid lines
/// scrolls toward the viewer; a magenta-orange retrowave sun sits on the
/// horizon with horizontal cutout bars; pink-to-purple sky gradient above.
final class SynthwaveGridScene: DemoScene {
    static let identifier = "synthwave_grid"
    static let displayName = "Synthwave Grid"

    static let options: [SceneOption] = [
        .slider(key: "scrollSpeed", label: "Scroll Speed", min: 0.2, max: 4.0, defaultValue: 1.0, format: "%.1f"),
        .slider(key: "horizonY", label: "Horizon Position", min: 0.3, max: 0.7, defaultValue: 0.5, format: "%.2f"),
        .slider(key: "sunSize", label: "Sun Size", min: 100, max: 400, defaultValue: 220, format: "%.0f px"),
        .toggle(key: "mountains", label: "Show distant mountains", defaultValue: true),
    ]

    private var size: CGSize = .zero
    private let scrollSpeed: Double
    private let horizonFrac: CGFloat
    private let sunSize: CGFloat
    private let mountains: Bool
    private var elapsed: Double = 0
    private var mountainHeights: [CGFloat] = []

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.scrollSpeed = settings.double("scrollSpeed", default: 1.0)
        self.horizonFrac = CGFloat(settings.double("horizonY", default: 0.5))
        self.sunSize = CGFloat(settings.double("sunSize", default: 220))
        self.mountains = settings.bool("mountains", default: true)
        seedMountains()
    }

    func resize(_ newSize: CGSize) {
        // resize() is called every frame by the screensaver host, so an
        // unconditional re-seed regenerates the mountains every frame
        // ("flapping"). Only re-seed when the size actually changes.
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        seedMountains()
    }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        let horizonY = targetSize.height * horizonFrac

        // Sky gradient (top is pink, fades to deep purple at horizon).
        let skyTop = CGColor(red: 1.0, green: 0.4, blue: 0.7, alpha: 1)
        let skyMid = CGColor(red: 0.4, green: 0.1, blue: 0.5, alpha: 1)
        let skyBot = CGColor(red: 0.10, green: 0.0, blue: 0.30, alpha: 1)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [skyBot, skyMid, skyTop] as CFArray,
                               locations: [0, 0.4, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: targetSize.height),
                                    end: CGPoint(x: 0, y: horizonY), options: [])
        }

        // Sun.
        let sunCenter = CGPoint(x: targetSize.width / 2, y: horizonY)
        drawSun(ctx: ctx, at: sunCenter)

        // Mountains.
        if mountains { drawMountains(ctx: ctx, horizonY: horizonY) }

        // Floor (black below horizon).
        ctx.setFillColor(CGColor(red: 0.02, green: 0.0, blue: 0.05, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: targetSize.width, height: horizonY))

        // Perspective grid floor.
        drawGrid(ctx: ctx, horizonY: horizonY)
    }

    // MARK: - Drawing

    private func drawSun(ctx: CGContext, at center: CGPoint) {
        let radius = sunSize / 2
        // Vertical-stripe gradient effect: hot orange top, magenta bottom.
        let top = CGColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1)
        let mid = CGColor(red: 1.0, green: 0.40, blue: 0.40, alpha: 1)
        let bot = CGColor(red: 0.85, green: 0.05, blue: 0.50, alpha: 1)
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2))
        ctx.clip()
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [bot, mid, top] as CFArray,
                               locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: center.x, y: center.y - radius),
                                   end: CGPoint(x: center.x, y: center.y + radius),
                                   options: [])
        }
        // Horizontal cutout bars across lower half.
        ctx.setBlendMode(.destinationOut)
        let barCount = 6
        for i in 0..<barCount {
            let frac = CGFloat(i) / CGFloat(barCount)
            let y = center.y - radius * 0.5 + frac * radius * 0.6
            let h = (1 - frac) * 6 + 1
            ctx.fill(CGRect(x: center.x - radius - 5, y: y, width: radius * 2 + 10, height: h))
        }
        ctx.restoreGState()
    }

    private func drawMountains(ctx: CGContext, horizonY: CGFloat) {
        ctx.setFillColor(CGColor(red: 0.10, green: 0.05, blue: 0.20, alpha: 1))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: horizonY))
        let len = mountainHeights.count
        for x in 0..<Int(size.width) {
            let i = x % len
            let h = mountainHeights[i]
            ctx.addLine(to: CGPoint(x: CGFloat(x), y: horizonY + h))
        }
        ctx.addLine(to: CGPoint(x: size.width, y: horizonY))
        ctx.closePath()
        ctx.fillPath()
    }

    private func drawGrid(ctx: CGContext, horizonY: CGFloat) {
        ctx.setStrokeColor(CGColor(red: 1.0, green: 0.2, blue: 0.85, alpha: 0.9))
        ctx.setLineWidth(1.5)
        // Horizontal lines: spaced denser near the horizon. We draw lines at
        // perspective z values, the screen y is horizon - depthDist/(depth+1).
        let spacing = 0.15
        let scrollOffset = (elapsed * scrollSpeed * spacing).truncatingRemainder(dividingBy: spacing)
        var depth = -scrollOffset + spacing
        while depth < 6 {
            let yBelow = horizonY - (horizonY * (1 / (1 + depth)))
            let y = horizonY - yBelow
            if y > 0 && y < horizonY {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: size.width, y: y))
                ctx.strokePath()
            }
            depth += spacing
        }
        // Vertical converging lines.
        ctx.setStrokeColor(CGColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 0.85))
        let cx = size.width / 2
        let lanes = 16
        for i in -lanes...lanes {
            let xBottom = cx + CGFloat(i) * (size.width * 0.07)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx, y: horizonY))
            ctx.addLine(to: CGPoint(x: xBottom, y: 0))
            ctx.strokePath()
        }
    }

    // MARK: - Setup

    private func seedMountains() {
        let len = max(200, Int(size.width))
        var arr = [CGFloat](repeating: 0, count: len)
        for o in 0..<3 {
            let amp = CGFloat(40 / (o + 1))
            let freq = 0.008 * Double(o + 1) * 1.7
            let phase = Double.random(in: 0..<(2 * .pi))
            for i in 0..<len {
                arr[i] += CGFloat(sin(Double(i) * freq + phase)) * amp
            }
        }
        mountainHeights = arr
    }
}
