import Cocoa

/// Aurora borealis: vertical "curtain" of glowing light strips that wave
/// horizontally with sin motion. Several layered curtains in shifting
/// greens and purples drift across a starry sky.
final class AuroraBorealisScene: DemoScene {
    static let identifier = "aurora_borealis"
    static let displayName = "Aurora Borealis"

    static let options: [SceneOption] = [
        .slider(key: "curtainCount", label: "Curtain Layers", min: 2, max: 8, defaultValue: 5, format: "%.0f"),
        .slider(key: "speed", label: "Motion Speed", min: 0.1, max: 1.5, defaultValue: 0.4, format: "%.2f"),
        .slider(key: "intensity", label: "Brightness", min: 0.3, max: 1.5, defaultValue: 0.85, format: "%.2f"),
        .toggle(key: "showStars", label: "Show stars", defaultValue: true),
        .choice(key: "palette", label: "Palette",
                choices: ["Classic Green", "Northern Purple", "Solar Magenta", "Ice Cyan"],
                defaultValue: "Classic Green"),
    ]

    private struct Curtain {
        var phase: Double
        var freq: Double
        var amp: Double
        var hueShift: Double
        var widthBias: Double  // 0..1 horizontal anchor
    }

    private var size: CGSize = .zero
    private let curtainCount: Int
    private let speed: Double
    private let intensity: Double
    private let showStars: Bool
    private let paletteName: String

    private var curtains: [Curtain] = []
    private var stars: [(x: CGFloat, y: CGFloat, br: CGFloat)] = []
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.curtainCount = max(1, Int(settings.double("curtainCount", default: 5)))
        self.speed = settings.double("speed", default: 0.4)
        self.intensity = settings.double("intensity", default: 0.85)
        self.showStars = settings.bool("showStars", default: true)
        self.paletteName = settings.string("palette", default: "Classic Green")
        seed()
    }

    func resize(_ newSize: CGSize) {
        if newSize != size {
            size = newSize
            seedStars()
        }
    }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        // Night sky.
        let top = CGColor(red: 0.02, green: 0.02, blue: 0.10, alpha: 1)
        let bot = CGColor(red: 0.0, green: 0.0, blue: 0.04, alpha: 1)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [bot, top] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0),
                                    end: CGPoint(x: 0, y: targetSize.height), options: [])
        }

        if showStars {
            for s in stars {
                let twinkle = 0.7 + 0.3 * sin(elapsed * 1.5 + Double(s.x) * 0.2)
                ctx.setFillColor(CGColor(red: s.br, green: s.br, blue: s.br, alpha: CGFloat(twinkle)))
                ctx.fill(CGRect(x: s.x, y: s.y, width: 1.5, height: 1.5))
            }
        }

        // Aurora curtains: each curtain is a series of vertical strips with
        // horizontal sin offset and vertical fade.
        ctx.setBlendMode(.plusLighter)
        let stripWidth: CGFloat = 6
        for c in curtains {
            let baseColor = curtainColor(hueShift: c.hueShift)
            let xStep: CGFloat = stripWidth
            var x: CGFloat = 0
            while x < targetSize.width {
                let xNorm = Double(x) / Double(targetSize.width) - 0.5
                // Vertical center of this strip varies with sin.
                let phaseAt = elapsed * speed + c.phase + xNorm * c.freq
                let waveY = sin(phaseAt) * c.amp
                let centerY = targetSize.height * 0.55 + CGFloat(waveY)
                // Strip height varies by anchor.
                let bias = abs(xNorm - (c.widthBias - 0.5))
                let stripH = targetSize.height * 0.45 * CGFloat(max(0, 1 - bias * 1.5))
                let alpha = CGFloat(intensity) * (1 - CGFloat(bias) * 0.6)

                let topC = baseColor.copy(alpha: 0) ?? baseColor
                let midC = baseColor.copy(alpha: alpha) ?? baseColor
                let botC = baseColor.copy(alpha: 0) ?? baseColor
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: [botC, midC, topC] as CFArray,
                                       locations: [0, 0.5, 1]) {
                    let rect = CGRect(x: x, y: centerY - stripH / 2, width: stripWidth + 1, height: stripH)
                    ctx.saveGState()
                    ctx.clip(to: rect)
                    ctx.drawLinearGradient(g,
                                           start: CGPoint(x: 0, y: rect.minY),
                                           end: CGPoint(x: 0, y: rect.maxY),
                                           options: [])
                    ctx.restoreGState()
                }
                x += xStep
            }
        }
        ctx.setBlendMode(.normal)
    }

    // MARK: - Setup

    private func seed() {
        curtains = (0..<curtainCount).map { i in
            Curtain(
                phase: Double.random(in: 0..<(2 * .pi)),
                freq: Double.random(in: 1.5...4.0),
                amp: Double.random(in: 30...100) + Double(i * 8),
                hueShift: Double.random(in: -0.05...0.05) + Double(i) * 0.04,
                widthBias: Double.random(in: 0.2...0.8)
            )
        }
        seedStars()
    }

    private func seedStars() {
        stars = (0..<200).map { _ in
            (x: CGFloat.random(in: 0...size.width),
             y: CGFloat.random(in: size.height * 0.5...size.height),
             br: CGFloat.random(in: 0.3...0.95))
        }
    }

    private func curtainColor(hueShift: Double) -> CGColor {
        switch paletteName {
        case "Northern Purple":
            return CGColor(red: CGFloat(0.4 + hueShift), green: CGFloat(0.2 + hueShift * 0.5), blue: CGFloat(0.95), alpha: 1)
        case "Solar Magenta":
            return CGColor(red: CGFloat(1.0), green: CGFloat(0.3 + hueShift), blue: CGFloat(0.8), alpha: 1)
        case "Ice Cyan":
            return CGColor(red: CGFloat(0.4 + hueShift), green: CGFloat(0.95), blue: CGFloat(1.0), alpha: 1)
        default: // Classic Green
            return CGColor(red: CGFloat(0.2 + hueShift), green: CGFloat(0.95), blue: CGFloat(0.5 + hueShift), alpha: 1)
        }
    }
}
