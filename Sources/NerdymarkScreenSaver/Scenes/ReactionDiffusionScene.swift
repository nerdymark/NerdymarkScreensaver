import Cocoa

/// Reaction-Diffusion (Gray-Scott model). Two chemicals A & B diffuse and
/// react: A + 2B -> 3B (reaction), plus feed/kill that maintains them.
/// Different (feed, kill) values produce spots, stripes, mazes, holes —
/// emergent Turing patterns. We tick the simulation many sub-steps per
/// frame for visible motion, render through a palette.
final class ReactionDiffusionScene: DemoScene {
    static let identifier = "reaction_diffusion"
    static let displayName = "Reaction-Diffusion"

    static let options: [SceneOption] = [
        .slider(key: "scale", label: "Cell Size", min: 2, max: 8, defaultValue: 3, format: "%.0fx"),
        .slider(key: "speed", label: "Sim Speed", min: 1, max: 20, defaultValue: 8, format: "%.0f steps/frame"),
        .choice(key: "preset", label: "Pattern",
                choices: ["Spots", "Stripes", "Maze", "Coral", "Holes"],
                defaultValue: "Coral"),
        .choice(key: "palette", label: "Palette",
                choices: ["Mono", "Cyan", "Sunset", "Toxic"],
                defaultValue: "Cyan"),
    ]

    private var size: CGSize = .zero
    private let cellScale: Int
    private let speed: Int
    private let preset: String
    private let paletteName: String

    private var w: Int = 0
    private var h: Int = 0
    private var a: [Float] = []
    private var b: [Float] = []
    private var aNext: [Float] = []
    private var bNext: [Float] = []
    private var pixels: UnsafeMutablePointer<UInt32>?
    private var palette: [UInt32] = []
    private let dA: Float = 1.0
    private let dB: Float = 0.5
    private var feed: Float = 0.055
    private var kill: Float = 0.062
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.cellScale = max(2, Int(settings.double("scale", default: 3)))
        self.speed = max(1, Int(settings.double("speed", default: 8)))
        self.preset = settings.string("preset", default: "Coral")
        self.paletteName = settings.string("palette", default: "Cyan")
        switch preset {
        case "Spots":   feed = 0.0367; kill = 0.0649
        case "Stripes": feed = 0.022;  kill = 0.051
        case "Maze":    feed = 0.029;  kill = 0.057
        case "Holes":   feed = 0.039;  kill = 0.058
        default:        feed = 0.0545; kill = 0.062  // Coral
        }
        palette = ReactionDiffusionScene.makePalette(named: paletteName)
        allocate(for: size)
    }

    deinit { pixels?.deallocate() }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        allocate(for: newSize)
    }

    func tick(dt: TimeInterval) {
        for _ in 0..<speed { step() }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = pixels else { return }
        // Map B chemical concentration to palette.
        for i in 0..<(w * h) {
            let v = max(0, min(1, b[i]))
            buf[i] = palette[Int(v * 255)]
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

    // MARK: - Simulation

    private func step() {
        let W = w, H = h
        let f = feed, k = kill
        for y in 1..<(H - 1) {
            for x in 1..<(W - 1) {
                let i = y * W + x
                let aa = a[i]
                let bb = b[i]
                let lapA = a[i - 1] + a[i + 1] + a[i - W] + a[i + W] - 4 * aa
                let lapB = b[i - 1] + b[i + 1] + b[i - W] + b[i + W] - 4 * bb
                let abb = aa * bb * bb
                aNext[i] = aa + dA * lapA - abb + f * (1 - aa)
                bNext[i] = bb + dB * lapB + abb - (k + f) * bb
            }
        }
        swap(&a, &aNext)
        swap(&b, &bNext)
    }

    // MARK: - Buffers

    private func allocate(for newSize: CGSize) {
        pixels?.deallocate()
        w = max(8, Int(newSize.width) / cellScale)
        h = max(8, Int(newSize.height) / cellScale)
        a = [Float](repeating: 1.0, count: w * h)
        b = [Float](repeating: 0.0, count: w * h)
        aNext = a
        bNext = b
        pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
        // Seed several B blobs.
        for _ in 0..<10 {
            let cx = Int.random(in: 5..<(w - 5))
            let cy = Int.random(in: 5..<(h - 5))
            for dy in -3...3 {
                for dx in -3...3 {
                    let i = (cy + dy) * w + (cx + dx)
                    if i >= 0 && i < a.count { b[i] = 1.0 }
                }
            }
        }
    }

    // MARK: - Palette

    private static func makePalette(named name: String) -> [UInt32] {
        switch name {
        case "Sunset":
            return gradient(stops: [(0,(0,0,0)),(80,(60,10,30)),(170,(220,80,40)),(220,(255,200,60)),(255,(255,255,210))])
        case "Toxic":
            return gradient(stops: [(0,(0,0,0)),(80,(0,40,5)),(170,(40,200,40)),(255,(220,255,180))])
        case "Mono":
            return gradient(stops: [(0,(0,0,0)),(255,(255,255,255))])
        default: // Cyan
            return gradient(stops: [(0,(0,0,0)),(80,(0,40,80)),(170,(20,140,210)),(255,(220,255,255))])
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
