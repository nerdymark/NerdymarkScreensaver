import Cocoa

/// Diamond plasma: Manhattan-distance metric (|x| + |y|) instead of
/// Euclidean. Produces angular, geometric ripples in 4-fold symmetry —
/// looks like crystal patterns rather than waves.
final class DiamondPlasmaScene: DemoScene {
    static let identifier = "diamond_plasma"
    static let displayName = "Diamond Plasma"

    static let options: [SceneOption] = [
        .slider(key: "speed", label: "Speed", min: 0.2, max: 3.0, defaultValue: 1.0, format: "%.1fx"),
        .slider(key: "scale", label: "Pixel Size", min: 2, max: 8, defaultValue: 4, format: "%.0fx"),
        .slider(key: "frequency", label: "Pattern Density", min: 4, max: 24, defaultValue: 12, format: "%.0f"),
        .choice(key: "palette", label: "Palette",
                choices: PlasmaPalette.allNames,
                defaultValue: "Acid"),
    ]

    private var size: CGSize = .zero
    private let speed: Double
    private let scale: Int
    private let frequency: Float
    private let palette: [UInt32]
    private var bitmap: PaletteBitmap
    private var time: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.speed = settings.double("speed", default: 1.0)
        self.scale = max(1, Int(settings.double("scale", default: 4)))
        self.frequency = Float(settings.double("frequency", default: 12))
        self.palette = PlasmaPalette.make(named: settings.string("palette", default: "Acid"))
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
        let t = Float(time)
        let f = frequency / Float(min(w, h))

        for y in 0..<h {
            let dy = Float(y) - cy
            let absY: Float = abs(dy)
            let row = y * w
            for x in 0..<w {
                let dx = Float(x) - cx
                let absX: Float = abs(dx)
                let manhattan: Float = absX + absY
                let s1: Float = sin(manhattan * f + t * 2.0)
                let s2: Float = sin((absX - absY) * f * 0.7 + t * 1.5)
                let s3: Float = sin(max(absX, absY) * f * 0.5 + t)
                let v: Float = s1 + s2 + s3
                let scaled: Float = (v * 42.0 + t * 25.0).truncatingRemainder(dividingBy: 256.0)
                let idx: Int = Int(scaled < 0 ? scaled + 256.0 : scaled) & 0xFF
                buf[row + x] = pal[idx]
            }
        }
        bitmap.present(in: ctx, size: targetSize, smooth: false)
    }
}
