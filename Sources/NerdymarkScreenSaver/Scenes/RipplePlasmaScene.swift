import Cocoa

/// Ripple plasma: each frame computes per-pixel value as the sum of
/// `sin(distance to drop point + t)` for several "drop" points that
/// drift around. Wave fronts emanate from each, interfering. The drops
/// occasionally fade out and respawn at random spots so the pattern stays
/// fresh.
final class RipplePlasmaScene: DemoScene {
    static let identifier = "ripple_plasma"
    static let displayName = "Ripple Plasma"

    static let options: [SceneOption] = [
        .slider(key: "speed", label: "Speed", min: 0.2, max: 3.0, defaultValue: 1.0, format: "%.1fx"),
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 4, format: "%.0fx"),
        .slider(key: "dropCount", label: "Wave Sources", min: 2, max: 8, defaultValue: 4, format: "%.0f"),
        .choice(key: "palette", label: "Palette",
                choices: PlasmaPalette.allNames,
                defaultValue: "Ocean"),
    ]

    private struct Drop {
        var x: Float
        var y: Float
        var vx: Float
        var vy: Float
        var phase: Float
    }

    private var size: CGSize = .zero
    private let speed: Double
    private let scale: Int
    private let dropCount: Int
    private let palette: [UInt32]
    private var bitmap: PaletteBitmap
    private var drops: [Drop] = []
    private var time: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.speed = settings.double("speed", default: 1.0)
        self.scale = max(1, Int(settings.double("scale", default: 4)))
        self.dropCount = max(2, Int(settings.double("dropCount", default: 4)))
        self.palette = PlasmaPalette.make(named: settings.string("palette", default: "Ocean"))
        self.bitmap = PaletteBitmap(width: max(1, Int(size.width) / scale),
                                     height: max(1, Int(size.height) / scale))
        spawnDrops()
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        bitmap.resize(width: max(1, Int(newSize.width) / scale),
                       height: max(1, Int(newSize.height) / scale))
        spawnDrops()
    }

    func tick(dt: TimeInterval) {
        time += dt * speed
        let f = Float(dt * speed)
        for i in drops.indices {
            drops[i].x += drops[i].vx * f
            drops[i].y += drops[i].vy * f
            drops[i].phase += f * 2.0
            if drops[i].x < 0 || drops[i].x > Float(bitmap.width) {
                drops[i].vx = -drops[i].vx
            }
            if drops[i].y < 0 || drops[i].y > Float(bitmap.height) {
                drops[i].vy = -drops[i].vy
            }
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = bitmap.pixels else { return }
        let w = bitmap.width, h = bitmap.height
        let pal = palette
        let t = Float(time)

        // Snapshot drop positions to avoid struct-array indirection per pixel.
        let snapshot = drops

        for y in 0..<h {
            let yf = Float(y)
            let row = y * w
            for x in 0..<w {
                let xf = Float(x)
                var sum: Float = 0
                for d in snapshot {
                    let dx = xf - d.x
                    let dy = yf - d.y
                    let dist = sqrt(dx * dx + dy * dy)
                    sum += sin(dist * 0.18 - t * 3.0 + d.phase)
                }
                let scaled = (sum * 32.0 + t * 18.0).truncatingRemainder(dividingBy: 256.0)
                let idx = Int(scaled < 0 ? scaled + 256.0 : scaled) & 0xFF
                buf[row + x] = pal[idx]
            }
        }
        bitmap.present(in: ctx, size: targetSize, smooth: false)
    }

    private func spawnDrops() {
        drops = (0..<dropCount).map { _ in
            Drop(
                x: Float.random(in: 0...Float(bitmap.width)),
                y: Float.random(in: 0...Float(bitmap.height)),
                vx: Float.random(in: -8...8),
                vy: Float.random(in: -8...8),
                phase: Float.random(in: 0..<(2.0 * Float.pi))
            )
        }
    }
}
