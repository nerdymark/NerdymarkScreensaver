import Cocoa

/// Multi-depth horizontal parallax scroll. Three "mountain layers" + a star
/// layer scroll at different speeds to create depth, plus a foreground
/// silhouette in front.
final class ParallaxScrollerScene: DemoScene {
    static let identifier = "parallax_scroller"
    static let displayName = "Parallax Scroller"

    static let options: [SceneOption] = [
        .slider(key: "speed", label: "Scroll Speed", min: 10, max: 200, defaultValue: 60, format: "%.0f px/s"),
        .choice(key: "scene", label: "Scene",
                choices: ["Mountains at Dusk", "City Skyline", "Vapor Synthwave"],
                defaultValue: "Vapor Synthwave"),
    ]

    private struct Layer {
        var heights: [CGFloat]   // sample-per-x silhouette
        var color: CGColor
        var parallax: CGFloat    // speed multiplier
        var yOffset: CGFloat     // vertical position
    }

    private var size: CGSize = .zero
    private let speed: Double
    private let sceneName: String
    private var layers: [Layer] = []
    private var starOffset: CGFloat = 0
    private var stars: [(x: CGFloat, y: CGFloat, brightness: CGFloat)] = []
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.speed = settings.double("speed", default: 60)
        self.sceneName = settings.string("scene", default: "Vapor Synthwave")
        rebuild()
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        rebuild()
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        starOffset += CGFloat(speed * dt * 0.05)
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        // Sky.
        let (top, bottom) = skyColors()
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [top, bottom] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: targetSize.height),
                                    end: CGPoint(x: 0, y: 0), options: [])
        }
        // Stars.
        for (sx, sy, br) in stars {
            let twinkle = 0.7 + 0.3 * sin(elapsed * 2 + Double(sx) * 0.3)
            ctx.setFillColor(CGColor(red: br, green: br, blue: br, alpha: CGFloat(twinkle)))
            ctx.fill(CGRect(x: sx, y: sy, width: 1.5, height: 1.5))
        }

        // Layers (back to front).
        for layer in layers {
            let offset = CGFloat(elapsed) * CGFloat(speed) * layer.parallax
            drawLayer(ctx: ctx, layer: layer, offset: offset, size: targetSize)
        }
    }

    // MARK: - Drawing

    private func drawLayer(ctx: CGContext, layer: Layer, offset: CGFloat, size: CGSize) {
        ctx.setFillColor(layer.color)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: 0))
        let len = layer.heights.count
        for px in 0..<Int(size.width) + 1 {
            let sampleIdx = Int((CGFloat(px) + offset).truncatingRemainder(dividingBy: CGFloat(len)))
            let safeIdx = (sampleIdx % len + len) % len
            let h = layer.heights[safeIdx] + layer.yOffset
            ctx.addLine(to: CGPoint(x: CGFloat(px), y: h))
        }
        ctx.addLine(to: CGPoint(x: size.width, y: 0))
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: - Setup

    private func rebuild() {
        let w = Int(size.width)
        // Make heights array longer than screen so it loops smoothly.
        let heightLen = max(w * 3, 800)

        let baseY = size.height * 0.45
        layers = [
            // Far mountains
            Layer(
                heights: noiseHeights(length: heightLen, octaves: 3, baseAmp: 60, scale: 0.005),
                color: layerColor(depth: 0),
                parallax: 0.15,
                yOffset: baseY
            ),
            // Mid mountains
            Layer(
                heights: noiseHeights(length: heightLen, octaves: 4, baseAmp: 110, scale: 0.012),
                color: layerColor(depth: 1),
                parallax: 0.4,
                yOffset: baseY * 0.55
            ),
            // Near mountains
            Layer(
                heights: noiseHeights(length: heightLen, octaves: 4, baseAmp: 160, scale: 0.022),
                color: layerColor(depth: 2),
                parallax: 0.85,
                yOffset: baseY * 0.25
            ),
        ]
        // Stars.
        stars = (0..<200).map { _ in
            (x: CGFloat.random(in: 0...size.width),
             y: CGFloat.random(in: size.height * 0.45...size.height),
             brightness: CGFloat.random(in: 0.3...0.95))
        }
    }

    /// Sum-of-sines pseudo-noise — cheap, deterministic-per-rebuild,
    /// produces nice mountain silhouettes.
    private func noiseHeights(length: Int, octaves: Int, baseAmp: CGFloat, scale: Double) -> [CGFloat] {
        var heights = [CGFloat](repeating: 0, count: length)
        for o in 0..<octaves {
            let amp = baseAmp / CGFloat(o + 1)
            let freq = scale * Double(o + 1) * 1.7
            let phase = Double.random(in: 0..<(2 * Double.pi))
            for i in 0..<length {
                heights[i] += CGFloat(sin(Double(i) * freq + phase)) * amp
            }
        }
        return heights
    }

    private func skyColors() -> (CGColor, CGColor) {
        switch sceneName {
        case "City Skyline":
            return (CGColor(red: 0.5, green: 0.30, blue: 0.20, alpha: 1),
                    CGColor(red: 0.10, green: 0.05, blue: 0.15, alpha: 1))
        case "Mountains at Dusk":
            return (CGColor(red: 0.85, green: 0.45, blue: 0.30, alpha: 1),
                    CGColor(red: 0.10, green: 0.10, blue: 0.30, alpha: 1))
        default:  // Vapor Synthwave
            return (CGColor(red: 1.0, green: 0.40, blue: 0.65, alpha: 1),
                    CGColor(red: 0.10, green: 0.0, blue: 0.40, alpha: 1))
        }
    }

    private func layerColor(depth: Int) -> CGColor {
        switch sceneName {
        case "City Skyline":
            let d = CGFloat(depth)
            return CGColor(red: 0.10 + d * 0.05, green: 0.05 + d * 0.04, blue: 0.10 + d * 0.06, alpha: 1)
        case "Mountains at Dusk":
            let d = CGFloat(depth)
            return CGColor(red: 0.30 - d * 0.08, green: 0.18 - d * 0.05, blue: 0.30 - d * 0.06, alpha: 1)
        default:  // Vapor
            let d = CGFloat(depth)
            return CGColor(red: 0.55 - d * 0.15, green: 0.0 + d * 0.1, blue: 0.65 - d * 0.05, alpha: 1)
        }
    }
}
