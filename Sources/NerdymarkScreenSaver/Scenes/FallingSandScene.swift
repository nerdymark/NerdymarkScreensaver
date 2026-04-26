import Cocoa

/// Falling sand: cellular pixel physics. Sand falls down (and diagonally
/// when blocked), water flows horizontally when blocked below. Periodic
/// "showers" drop new sand of cycling colors. Resets when buried.
final class FallingSandScene: DemoScene {
    static let identifier = "falling_sand"
    static let displayName = "Falling Sand"

    static let options: [SceneOption] = [
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 4, format: "%.0fx"),
        .slider(key: "spawnRate", label: "Spawn Rate", min: 1, max: 20, defaultValue: 8, format: "%.0f cols"),
        .toggle(key: "rainbow", label: "Cycle colors", defaultValue: true),
    ]

    private static let EMPTY: UInt8 = 0
    private static let SAND_BASE: UInt8 = 16  // sand colors 16+ (one per palette index)

    private var size: CGSize = .zero
    private let pixelScale: Int
    private let spawnRate: Int
    private let rainbow: Bool

    private var w: Int = 0
    private var h: Int = 0
    private var grid: [UInt8] = []
    private var pixels: UnsafeMutablePointer<UInt32>?
    private var palette: [UInt32] = []
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var elapsed: Double = 0
    private var hueShift: Double = 0
    private var resetCheck: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.pixelScale = max(2, Int(settings.double("scale", default: 4)))
        self.spawnRate = max(1, Int(settings.double("spawnRate", default: 8)))
        self.rainbow = settings.bool("rainbow", default: true)
        rebuildPalette()
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
        hueShift += dt * 0.05
        // Reset when more than ~85% full.
        resetCheck += dt
        if resetCheck > 2 {
            resetCheck = 0
            let filled = grid.lazy.filter { $0 != FallingSandScene.EMPTY }.count
            if Double(filled) / Double(grid.count) > 0.85 {
                allocate(for: size)
                return
            }
        }
        // Physics step: scan bottom-up to make sand fall properly.
        for y in stride(from: h - 2, through: 0, by: -1) {
            // Alternate scan direction to remove asymmetry artifacts.
            let leftToRight = (y & 1) == 0
            let xRange = leftToRight ? Array(0..<w) : (0..<w).reversed().map { $0 }
            for x in xRange {
                let i = y * w + x
                let v = grid[i]
                if v == FallingSandScene.EMPTY { continue }
                let below = (y + 1) * w + x
                if grid[below] == FallingSandScene.EMPTY {
                    grid[below] = v; grid[i] = FallingSandScene.EMPTY
                } else {
                    let dir = Bool.random() ? -1 : 1
                    let sideX = x + dir
                    if sideX >= 0 && sideX < w && grid[(y + 1) * w + sideX] == FallingSandScene.EMPTY {
                        grid[(y + 1) * w + sideX] = v; grid[i] = FallingSandScene.EMPTY
                    } else {
                        let otherX = x - dir
                        if otherX >= 0 && otherX < w && grid[(y + 1) * w + otherX] == FallingSandScene.EMPTY {
                            grid[(y + 1) * w + otherX] = v; grid[i] = FallingSandScene.EMPTY
                        }
                    }
                }
            }
        }
        // Drop new sand from random columns near top.
        let baseHue = (rainbow ? hueShift : 0).truncatingRemainder(dividingBy: 1.0)
        for _ in 0..<spawnRate {
            let x = Int.random(in: 1..<(w - 1))
            let band = Int(baseHue * 16) % 16
            let v = FallingSandScene.SAND_BASE + UInt8(band)
            grid[1 * w + x] = v
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = pixels else { return }
        for i in 0..<(w * h) {
            buf[i] = palette[Int(grid[i])]
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

    // MARK: - Setup

    private func allocate(for newSize: CGSize) {
        pixels?.deallocate()
        w = max(20, Int(newSize.width) / pixelScale)
        h = max(20, Int(newSize.height) / pixelScale)
        grid = [UInt8](repeating: 0, count: w * h)
        pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
    }

    private func rebuildPalette() {
        var p = [UInt32](repeating: 0xFF000000, count: 256)
        // Sand colors: 16 hues full saturation
        for i in 0..<16 {
            let hue = Double(i) / 16
            let c = NSColor(hue: CGFloat(hue), saturation: 0.85, brightness: 0.95, alpha: 1)
            let r = UInt32(c.redComponent * 255)
            let g = UInt32(c.greenComponent * 255)
            let b = UInt32(c.blueComponent * 255)
            p[Int(FallingSandScene.SAND_BASE) + i] = (0xFF << 24) | (r << 16) | (g << 8) | b
        }
        palette = p
    }
}
