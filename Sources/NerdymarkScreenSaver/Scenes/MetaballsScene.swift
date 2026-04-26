import Cocoa
import CoreGraphics

/// Metaballs: each pixel's color depends on the sum of inverse-distance
/// contributions from N moving "balls". Above a threshold = inside the blob.
/// Soft falloff outside gives the gooey edge. Rendered to a low-res buffer
/// then upscaled like the plasma scene.
final class MetaballsScene: DemoScene {
    static let identifier = "metaballs"
    static let displayName = "Metaballs"

    static let options: [SceneOption] = [
        .slider(key: "ballCount", label: "Ball Count", min: 3, max: 12, defaultValue: 7, format: "%.0f"),
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 4, format: "%.0fx"),
        .slider(key: "speed", label: "Motion Speed", min: 0.2, max: 2.5, defaultValue: 1.0, format: "%.1fx"),
        .choice(key: "palette", label: "Palette",
                choices: ["Lava", "Cosmic", "Acid", "Mercury"],
                defaultValue: "Lava"),
    ]

    private struct Ball {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var radius: Double  // contributes to field strength
    }

    private var size: CGSize = .zero
    private let ballCount: Int
    private let scale: Int
    private var speed: Double
    private let palette: [UInt32]
    private var balls: [Ball] = []

    private var pixelBuffer: UnsafeMutablePointer<UInt32>?
    private var bufferCount = 0
    private var bWidth = 0
    private var bHeight = 0
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.ballCount = max(3, Int(settings.double("ballCount", default: 7)))
        self.scale = max(1, Int(settings.double("scale", default: 4)))
        self.speed = settings.double("speed", default: 1.0)
        self.palette = MetaballsScene.makePalette(named: settings.string("palette", default: "Lava"))
        allocate(for: size)
        spawnBalls()
    }

    deinit { pixelBuffer?.deallocate() }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        allocate(for: newSize)
    }

    func tick(dt: TimeInterval) {
        let dts = dt * speed
        for i in balls.indices {
            balls[i].x += balls[i].vx * dts
            balls[i].y += balls[i].vy * dts
            // Bounce off bounds (in low-res space).
            if balls[i].x < balls[i].radius {
                balls[i].x = balls[i].radius; balls[i].vx = abs(balls[i].vx)
            } else if balls[i].x > Double(bWidth) - balls[i].radius {
                balls[i].x = Double(bWidth) - balls[i].radius; balls[i].vx = -abs(balls[i].vx)
            }
            if balls[i].y < balls[i].radius {
                balls[i].y = balls[i].radius; balls[i].vy = abs(balls[i].vy)
            } else if balls[i].y > Double(bHeight) - balls[i].radius {
                balls[i].y = Double(bHeight) - balls[i].radius; balls[i].vy = -abs(balls[i].vy)
            }
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buffer = pixelBuffer else { return }

        // Compute the field per low-res pixel.
        // Using r^2 / d^2 sum so we avoid sqrt; the falloff is the standard
        // metaball formula (see https://en.wikipedia.org/wiki/Metaballs).
        let pal = palette
        for y in 0..<bHeight {
            let row = y * bWidth
            for x in 0..<bWidth {
                var sum = 0.0
                for ball in balls {
                    let dx = Double(x) - ball.x
                    let dy = Double(y) - ball.y
                    let d2 = dx * dx + dy * dy + 1.0
                    sum += (ball.radius * ball.radius) / d2
                }
                // Map field 0..~3 → palette index 0..255 with steep curve so
                // the blob interior pops while exterior fades quickly.
                let v = min(1.0, sum * 0.45)
                let idx = Int(v * 255.0) & 0xFF
                buffer[row + x] = pal[idx]
            }
        }

        // Upscale.
        let bytesPerRow = bWidth * 4
        let bytesTotal = bytesPerRow * bHeight
        guard let provider = CGDataProvider(
            dataInfo: nil, data: buffer, size: bytesTotal,
            releaseData: { _, _, _ in }
        ) else { return }
        guard let image = CGImage(
            width: bWidth, height: bHeight,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        ) else { return }

        ctx.interpolationQuality = .medium  // smooth blob edges, but still fast
        ctx.draw(image, in: CGRect(origin: .zero, size: targetSize))
    }

    // MARK: - Setup

    private func allocate(for newSize: CGSize) {
        pixelBuffer?.deallocate()
        bWidth = max(1, Int(newSize.width) / scale)
        bHeight = max(1, Int(newSize.height) / scale)
        bufferCount = bWidth * bHeight
        pixelBuffer = UnsafeMutablePointer<UInt32>.allocate(capacity: bufferCount)
    }

    private func spawnBalls() {
        balls = (0..<ballCount).map { _ in
            Ball(
                x: Double.random(in: 0...Double(bWidth)),
                y: Double.random(in: 0...Double(bHeight)),
                vx: Double.random(in: -20...20),
                vy: Double.random(in: -20...20),
                radius: Double.random(in: 12...28)
            )
        }
    }

    private static func makePalette(named name: String) -> [UInt32] {
        switch name {
        case "Cosmic":
            return gradient([(0,(5,0,30)),(80,(60,20,160)),(160,(180,80,220)),(220,(255,200,255)),(255,(255,255,255))])
        case "Acid":
            return gradient([(0,(0,30,0)),(100,(20,180,30)),(180,(180,255,30)),(255,(255,255,200))])
        case "Mercury":
            return gradient([(0,(10,15,30)),(120,(60,80,140)),(200,(180,200,230)),(255,(240,250,255))])
        default: // Lava
            return gradient([(0,(20,0,0)),(80,(140,15,0)),(180,(255,90,15)),(230,(255,210,80)),(255,(255,255,200))])
        }
    }

    private static func gradient(_ stops: [(Int, (UInt8, UInt8, UInt8))]) -> [UInt32] {
        var pal = [UInt32](repeating: 0, count: 256)
        let sorted = stops.sorted { $0.0 < $1.0 }
        for i in 0..<256 {
            var lower = sorted.first!
            var upper = sorted.last!
            for s in sorted {
                if s.0 <= i { lower = s }
                if s.0 >= i { upper = s; break }
            }
            let span = max(1, upper.0 - lower.0)
            let frac = Double(i - lower.0) / Double(span)
            let r = UInt32(Double(lower.1.0) + (Double(upper.1.0) - Double(lower.1.0)) * frac)
            let g = UInt32(Double(lower.1.1) + (Double(upper.1.1) - Double(lower.1.1)) * frac)
            let b = UInt32(Double(lower.1.2) + (Double(upper.1.2) - Double(lower.1.2)) * frac)
            pal[i] = (0xFF << 24) | (r << 16) | (g << 8) | b
        }
        return pal
    }
}
