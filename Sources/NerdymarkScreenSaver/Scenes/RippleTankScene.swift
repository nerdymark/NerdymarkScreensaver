import Cocoa

/// Ripple tank: 2D shallow-water wave equation simulated on a low-res grid.
/// Random "droplets" perturb the surface; waves propagate, reflect off
/// edges, and interfere. Rendered through a palette that maps wave height
/// to color.
final class RippleTankScene: DemoScene {
    static let identifier = "ripple_tank"
    static let displayName = "Ripple Tank"

    static let options: [SceneOption] = [
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 3, format: "%.0fx"),
        .slider(key: "damping", label: "Damping", min: 0.85, max: 0.999, defaultValue: 0.985, format: "%.3f"),
        .slider(key: "dropsPerSecond", label: "Drops / s", min: 0.2, max: 6, defaultValue: 1.2, format: "%.1f"),
        .choice(key: "palette", label: "Palette",
                choices: ["Pool Blue", "Mercury", "Lava", "Acid"],
                defaultValue: "Pool Blue"),
    ]

    private var size: CGSize = .zero
    private let pixelScale: Int
    private let damping: Float
    private let dropsPerSecond: Double
    private let paletteName: String

    private var w: Int = 0
    private var h: Int = 0
    private var bufA: [Float] = []
    private var bufB: [Float] = []
    private var pixels: UnsafeMutablePointer<UInt32>?
    private var palette: [UInt32] = []
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var elapsed: Double = 0
    private var nextDropAt: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.pixelScale = max(2, Int(settings.double("scale", default: 3)))
        self.damping = Float(settings.double("damping", default: 0.985))
        self.dropsPerSecond = settings.double("dropsPerSecond", default: 1.2)
        self.paletteName = settings.string("palette", default: "Pool Blue")
        palette = RippleTankScene.makePalette(named: paletteName)
        allocate(for: size)
    }

    deinit { pixels?.deallocate() }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        allocate(for: newSize)
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        // Inject drops.
        while elapsed >= nextDropAt {
            let cx = Int.random(in: 4..<(w - 4))
            let cy = Int.random(in: 4..<(h - 4))
            let amp: Float = Float.random(in: 600...1500)
            for dy in -2...2 {
                for dx in -2...2 {
                    if dx * dx + dy * dy <= 4 {
                        bufA[(cy + dy) * w + cx + dx] = amp
                    }
                }
            }
            nextDropAt += 1.0 / max(0.1, dropsPerSecond)
        }
        // Wave step (cheap 2D wave equation: new = (avg of 4 neighbours) - prev, damped).
        let W = w, H = h
        let damp = damping
        for y in 1..<(H - 1) {
            for x in 1..<(W - 1) {
                let i = y * W + x
                let n = (bufA[i - 1] + bufA[i + 1] + bufA[i - W] + bufA[i + W]) * 0.5 - bufB[i]
                bufB[i] = n * damp
            }
        }
        swap(&bufA, &bufB)
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = pixels else { return }
        // Map wave heights (-N..+N) to 0..255 via tanh-style soft clip.
        for i in 0..<(w * h) {
            let v = bufA[i]
            let clipped = max(-1, min(1, v / 800))
            let mapped = Int((clipped + 1) * 0.5 * 255)
            buf[i] = palette[mapped]
        }
        let bytesPerRow = w * 4
        guard let provider = CGDataProvider(dataInfo: nil, data: buf, size: bytesPerRow * h, releaseData: { _, _, _ in }),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: bytesPerRow, space: colorSpace,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(origin: .zero, size: targetSize))
    }

    // MARK: - Setup

    private func allocate(for newSize: CGSize) {
        pixels?.deallocate()
        w = max(8, Int(newSize.width) / pixelScale)
        h = max(8, Int(newSize.height) / pixelScale)
        bufA = [Float](repeating: 0, count: w * h)
        bufB = [Float](repeating: 0, count: w * h)
        pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
    }

    // MARK: - Palette

    private static func makePalette(named name: String) -> [UInt32] {
        switch name {
        case "Mercury":
            return gradient(stops: [(0,(20,20,30)),(128,(180,190,210)),(255,(255,255,255))])
        case "Lava":
            return gradient(stops: [(0,(20,0,0)),(128,(220,80,20)),(255,(255,250,180))])
        case "Acid":
            return gradient(stops: [(0,(0,30,0)),(128,(60,200,40)),(255,(220,255,180))])
        default: // Pool Blue
            return gradient(stops: [(0,(0,10,40)),(128,(40,140,200)),(255,(220,250,255))])
        }
    }

    private static func gradient(stops: [(Int, (UInt8, UInt8, UInt8))]) -> [UInt32] {
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
