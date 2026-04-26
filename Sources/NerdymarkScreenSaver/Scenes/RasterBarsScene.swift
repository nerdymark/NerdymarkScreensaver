import Cocoa

/// Raster bars: full-width horizontal palette stripes that scroll vertically
/// and through palette colors. Simpler than copper bars — solid bars not
/// gradients — but with palette cycling that gives the "candy stripe"
/// effect synonymous with C64 demos.
final class RasterBarsScene: DemoScene {
    static let identifier = "raster_bars"
    static let displayName = "Raster Bars"

    static let options: [SceneOption] = [
        .slider(key: "barHeight", label: "Bar Height", min: 4, max: 40, defaultValue: 14, format: "%.0f px"),
        .slider(key: "scrollSpeed", label: "Scroll Speed", min: 0, max: 200, defaultValue: 60, format: "%.0f px/s"),
        .slider(key: "cycleSpeed", label: "Color Cycle", min: 0, max: 4, defaultValue: 1.0, format: "%.1fx"),
        .choice(key: "palette", label: "Palette",
                choices: ["Spectrum", "Sunset", "Vapor", "Mono"],
                defaultValue: "Spectrum"),
    ]

    private var size: CGSize = .zero
    private let barHeight: CGFloat
    private let scrollSpeed: Double
    private let cycleSpeed: Double
    private let paletteName: String
    private let palette: [CGColor]
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.barHeight = CGFloat(settings.double("barHeight", default: 14))
        self.scrollSpeed = settings.double("scrollSpeed", default: 60)
        self.cycleSpeed = settings.double("cycleSpeed", default: 1.0)
        self.paletteName = settings.string("palette", default: "Spectrum")
        self.palette = RasterBarsScene.makePalette(named: paletteName)
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let scrollOffset = CGFloat(elapsed * scrollSpeed)
        let colorOffset = Int(elapsed * 30 * cycleSpeed)
        let palCount = palette.count

        var y: CGFloat = -scrollOffset.truncatingRemainder(dividingBy: barHeight)
        var idx = 0
        while y < targetSize.height {
            let palIdx = (idx + colorOffset) % palCount
            ctx.setFillColor(palette[(palIdx + palCount) % palCount])
            ctx.fill(CGRect(x: 0, y: y, width: targetSize.width, height: barHeight))
            y += barHeight
            idx += 1
        }
    }

    private static func makePalette(named name: String) -> [CGColor] {
        switch name {
        case "Sunset":
            return interp([(0xff, 0x6b, 0x35), (0xff, 0xa5, 0x00), (0xff, 0xee, 0x00),
                           (0xff, 0x40, 0x80), (0x80, 0x00, 0xa0)], steps: 64)
        case "Vapor":
            return interp([(0xff, 0x71, 0xce), (0x05, 0xff, 0xa1), (0x01, 0xcd, 0xfe),
                           (0xb2, 0x8d, 0xff), (0xff, 0x71, 0xce)], steps: 64)
        case "Mono":
            return (0..<32).map { i in
                let v = CGFloat(i) / 32.0
                return CGColor(red: v, green: v, blue: v * 1.05, alpha: 1)
            } + (0..<32).map { i in
                let v = CGFloat(31 - i) / 32.0
                return CGColor(red: v, green: v, blue: v * 1.05, alpha: 1)
            }
        default: // Spectrum
            return (0..<64).map { i in
                NSColor(hue: CGFloat(i) / 64.0, saturation: 0.95, brightness: 1.0, alpha: 1).cgColor
            }
        }
    }

    private static func interp(_ stops: [(Int, Int, Int)], steps: Int) -> [CGColor] {
        var out: [CGColor] = []
        let perSeg = steps / max(1, stops.count - 1)
        for seg in 0..<(stops.count - 1) {
            let a = stops[seg], b = stops[seg + 1]
            for s in 0..<perSeg {
                let t = Double(s) / Double(perSeg)
                let r = CGFloat(Double(a.0) * (1 - t) + Double(b.0) * t) / 255.0
                let g = CGFloat(Double(a.1) * (1 - t) + Double(b.1) * t) / 255.0
                let bl = CGFloat(Double(a.2) * (1 - t) + Double(b.2) * t) / 255.0
                out.append(CGColor(red: r, green: g, blue: bl, alpha: 1))
            }
        }
        return out
    }
}
