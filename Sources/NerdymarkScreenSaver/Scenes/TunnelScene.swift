import Cocoa
import CoreGraphics

/// Classic demoscene tunnel: per-pixel angle and depth lookups feed a
/// scrolling palette texture. The lookup tables are precomputed once on
/// resize so the inner loop is just two table reads + one mod per pixel.
final class TunnelScene: DemoScene {
    static let identifier = "tunnel"
    static let displayName = "Tunnel"

    static let options: [SceneOption] = [
        .slider(key: "speed", label: "Tunnel Speed", min: 0.2, max: 4.0, defaultValue: 1.5, format: "%.1fx"),
        .slider(key: "spinSpeed", label: "Rotation", min: -2.0, max: 2.0, defaultValue: 0.4, format: "%.1f rad/s"),
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 4, format: "%.0fx"),
        .choice(key: "palette", label: "Palette",
                choices: PlasmaPalette.allNames,
                defaultValue: "Neon"),
    ]

    private var size: CGSize = .zero
    private let speed: Double
    private let spinSpeed: Double
    private let scale: Int
    private let palette: [UInt32]
    private var bitmap: PaletteBitmap

    // Per-pixel lookups: angle × tunnel-depth, shared across frames.
    private var angleTable: [UInt8] = []
    private var depthTable: [UInt8] = []
    private var time: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.speed = settings.double("speed", default: 1.5)
        self.spinSpeed = settings.double("spinSpeed", default: 0.4)
        self.scale = max(1, Int(settings.double("scale", default: 4)))
        self.palette = PlasmaPalette.make(named: settings.string("palette", default: "Neon"))
        self.bitmap = PaletteBitmap(width: max(1, Int(size.width) / scale),
                                     height: max(1, Int(size.height) / scale))
        precomputeLookups()
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        bitmap.resize(width: max(1, Int(newSize.width) / scale),
                       height: max(1, Int(newSize.height) / scale))
        precomputeLookups()
    }

    func tick(dt: TimeInterval) { time += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = bitmap.pixels else { return }
        let w = bitmap.width, h = bitmap.height
        let count = w * h
        let pal = palette

        // Both shifts are integer indices into the [0,256) palette range.
        let depthShift = Int(time * 30 * speed) & 0xFF
        let angleShift = Int(time * 30 * spinSpeed + 256) & 0xFF

        for i in 0..<count {
            let combined = (Int(angleTable[i]) + angleShift) ^ (Int(depthTable[i]) + depthShift)
            buf[i] = pal[combined & 0xFF]
        }
        bitmap.present(in: ctx, size: targetSize, smooth: false)
    }

    private func precomputeLookups() {
        let w = bitmap.width, h = bitmap.height
        let count = w * h
        angleTable = [UInt8](repeating: 0, count: count)
        depthTable = [UInt8](repeating: 0, count: count)
        let cx = Float(w) / 2
        let cy = Float(h) / 2
        let radius = Float(min(w, h)) * 0.5

        for y in 0..<h {
            let dy = Float(y) - cy
            let row = y * w
            for x in 0..<w {
                let dx = Float(x) - cx
                let dist = sqrt(dx * dx + dy * dy) + 0.0001
                let angle = atan2(dy, dx)
                // angleTable in [0, 256): map [-π, π] to [0, 256)
                let angleIdx = Int(((angle / Float.pi + 1.0) * 0.5) * 256.0) & 0xFF
                angleTable[row + x] = UInt8(angleIdx)
                // depthTable: 1/distance scaled — closer to center = higher
                // index, recedes outward.
                let depth = (radius * 32.0 / dist).truncatingRemainder(dividingBy: 256.0)
                let depthIdx = Int(depth) & 0xFF
                depthTable[row + x] = UInt8(depthIdx)
            }
        }
    }
}
