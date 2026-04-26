import Cocoa

/// Diffusion-Limited Aggregation: random walkers wander until they touch
/// the existing cluster, then stick. Grows snowflake/coral/dendrite shapes
/// over time. We seed at center and reset every ~60s when grown out.
final class DLASnowflakeScene: DemoScene {
    static let identifier = "dla_snowflake"
    static let displayName = "Snowflake (DLA)"

    static let options: [SceneOption] = [
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 3, format: "%.0fx"),
        .slider(key: "walkers", label: "Walker Count", min: 100, max: 3000, defaultValue: 1200, format: "%.0f"),
        .slider(key: "stickProb", label: "Stickiness", min: 0.2, max: 1.0, defaultValue: 0.95, format: "%.2f"),
        .choice(key: "palette", label: "Palette",
                choices: ["Ice", "Ember", "Magenta", "Mono"],
                defaultValue: "Ice"),
    ]

    private struct Walker { var x: Int; var y: Int }

    private var size: CGSize = .zero
    private let pixelScale: Int
    private let walkerCount: Int
    private let stickProb: Double
    private let paletteName: String

    private var w: Int = 0
    private var h: Int = 0
    private var grid: [UInt8] = []   // 0 = empty, >0 = stuck (age in tens)
    private var walkers: [Walker] = []
    private var pixels: UnsafeMutablePointer<UInt32>?
    private var palette: [UInt32] = []
    private var growthAge: Int = 0
    private var elapsed: Double = 0
    private var lastReset: Double = 0
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.pixelScale = max(2, Int(settings.double("scale", default: 3)))
        self.walkerCount = max(50, Int(settings.double("walkers", default: 1200)))
        self.stickProb = settings.double("stickProb", default: 0.95)
        self.paletteName = settings.string("palette", default: "Ice")
        palette = DLASnowflakeScene.makePalette(named: paletteName)
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
        // Reset when nothing reachable or after ~60s of growth.
        if elapsed - lastReset > 60 {
            allocate(for: size)
            lastReset = elapsed
        }
        // Move every walker; stuck walkers respawn as fresh at edge.
        for i in 0..<walkers.count {
            var wk = walkers[i]
            // 4-neighbour random walk
            switch Int.random(in: 0..<4) {
            case 0: wk.x += 1
            case 1: wk.x -= 1
            case 2: wk.y += 1
            default: wk.y -= 1
            }
            if wk.x < 1 || wk.x >= w - 1 || wk.y < 1 || wk.y >= h - 1 {
                wk = spawnWalker()
            }
            // If a neighbour is stuck, we may stick.
            let idx = wk.y * w + wk.x
            if isAdjacentStuck(idx: idx) && Double.random(in: 0...1) < stickProb {
                growthAge = min(255, growthAge + 1)
                grid[idx] = UInt8(min(255, growthAge / 4 + 1))
                wk = spawnWalker()
            }
            walkers[i] = wk
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = pixels else { return }
        for i in 0..<(w * h) {
            buf[i] = grid[i] == 0 ? 0xFF000000 : palette[Int(grid[i])]
        }
        let bytesPerRow = w * 4
        guard let provider = CGDataProvider(dataInfo: nil, data: buf, size: bytesPerRow * h, releaseData: { _, _, _ in }),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: bytesPerRow, space: colorSpace,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(origin: .zero, size: targetSize))
    }

    // MARK: - Sim

    private func isAdjacentStuck(idx: Int) -> Bool {
        return grid[idx - 1] != 0 || grid[idx + 1] != 0 || grid[idx - w] != 0 || grid[idx + w] != 0
    }

    private func spawnWalker() -> Walker {
        // Spawn on a random edge.
        switch Int.random(in: 0..<4) {
        case 0: return Walker(x: Int.random(in: 1..<(w - 1)), y: 1)
        case 1: return Walker(x: Int.random(in: 1..<(w - 1)), y: h - 2)
        case 2: return Walker(x: 1, y: Int.random(in: 1..<(h - 1)))
        default: return Walker(x: w - 2, y: Int.random(in: 1..<(h - 1)))
        }
    }

    private func allocate(for newSize: CGSize) {
        pixels?.deallocate()
        w = max(20, Int(newSize.width) / pixelScale)
        h = max(20, Int(newSize.height) / pixelScale)
        grid = [UInt8](repeating: 0, count: w * h)
        // Seed center.
        grid[(h / 2) * w + (w / 2)] = 1
        walkers = (0..<walkerCount).map { _ in spawnWalker() }
        pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
        growthAge = 0
    }

    // MARK: - Palette

    private static func makePalette(named name: String) -> [UInt32] {
        switch name {
        case "Ember":
            return gradient(stops: [(0,(0,0,0)),(40,(80,0,0)),(140,(220,80,20)),(220,(255,200,80)),(255,(255,255,220))])
        case "Magenta":
            return gradient(stops: [(0,(0,0,0)),(40,(60,0,40)),(140,(180,40,160)),(220,(240,140,220)),(255,(255,230,255))])
        case "Mono":
            return gradient(stops: [(0,(0,0,0)),(255,(255,255,255))])
        default: // Ice
            return gradient(stops: [(0,(0,0,0)),(40,(10,30,90)),(140,(80,180,230)),(220,(190,235,255)),(255,(255,255,255))])
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
