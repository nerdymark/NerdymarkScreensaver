import Cocoa

/// Spiral plasma: instead of summing sines of (x, y), sum sines of polar
/// coordinates (radius, angle). The resulting palette index swirls outward
/// from screen center.
final class SpiralPlasmaScene: DemoScene {
    static let identifier = "spiral_plasma"
    static let displayName = "Spiral Plasma"

    static let options: [SceneOption] = [
        .slider(key: "speed", label: "Speed", min: 0.2, max: 3.0, defaultValue: 1.0, format: "%.1fx"),
        .slider(key: "armCount", label: "Arms", min: 2, max: 14, defaultValue: 5, format: "%.0f"),
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 4, format: "%.0fx"),
        .choice(key: "palette", label: "Palette",
                choices: PlasmaPalette.allNames,
                defaultValue: "Cosmic"),
    ]

    private var size: CGSize = .zero
    private let speed: Double
    private let armCount: Double
    private let scale: Int
    private let palette: [UInt32]
    private var bitmap: PaletteBitmap
    private var time: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.speed = settings.double("speed", default: 1.0)
        self.armCount = settings.double("armCount", default: 5)
        self.scale = max(1, Int(settings.double("scale", default: 4)))
        self.palette = PlasmaPalette.make(named: settings.string("palette", default: "Cosmic"))
        self.bitmap = PaletteBitmap(width: max(1, Int(size.width) / scale),
                                     height: max(1, Int(size.height) / scale))
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        bitmap.resize(width: max(1, Int(newSize.width) / scale),
                       height: max(1, Int(newSize.height) / scale))
    }

    func tick(dt: TimeInterval) { time += dt * speed }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        guard let buf = bitmap.pixels else { return }
        let w = bitmap.width, h = bitmap.height
        let cx = Float(w) / 2, cy = Float(h) / 2
        let pal = palette
        let arms = Float(armCount)
        let t = Float(time)
        let invMaxR = 1.0 / sqrt(cx * cx + cy * cy)

        for y in 0..<h {
            let dy = Float(y) - cy
            let row = y * w
            for x in 0..<w {
                let dx = Float(x) - cx
                let r = sqrt(dx * dx + dy * dy) * invMaxR  // 0..~1
                let theta = atan2(dy, dx)
                let v = sin(theta * arms + t * 1.2)
                      + sin(r * 18.0 - t * 2.0)
                      + sin(theta * arms - r * 12.0 + t)
                let idx = Int((v * 42.0 + t * 30.0).truncatingRemainder(dividingBy: 256.0))
                let safeIdx = (idx + 256) & 0xFF
                buf[row + x] = pal[safeIdx]
            }
        }
        bitmap.present(in: ctx, size: targetSize, smooth: false)
    }
}
