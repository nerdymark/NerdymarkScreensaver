import Cocoa

/// Vector field flow: particles trace streamlines through a slowly-mutating
/// 2D vector field defined by sin(x*α + t)+cos(y*β+t). Particles leave
/// fading trails, recycling when they reach the screen edge.
final class VectorFieldScene: DemoScene {
    static let identifier = "vector_field"
    static let displayName = "Vector Field Flow"

    static let options: [SceneOption] = [
        .slider(key: "particleCount", label: "Particles", min: 100, max: 2000, defaultValue: 700, format: "%.0f"),
        .slider(key: "speed", label: "Flow Speed", min: 0.1, max: 3.0, defaultValue: 1.0, format: "%.1f"),
        .slider(key: "fadeRate", label: "Trail Fade", min: 0.005, max: 0.1, defaultValue: 0.02, format: "%.3f"),
        .slider(key: "fieldScale", label: "Field Scale", min: 0.001, max: 0.02, defaultValue: 0.005, format: "%.4f"),
        .choice(key: "palette", label: "Palette",
                choices: ["Sunset", "Cyan", "Spectrum", "Ember"],
                defaultValue: "Sunset"),
    ]

    private struct Particle { var x: Double; var y: Double; var hue: Double }

    private var size: CGSize = .zero
    private let particleCount: Int
    private let speed: Double
    private let fadeRate: CGFloat
    private let fieldScale: Double
    private let paletteName: String

    private var particles: [Particle] = []
    private var trailBitmap: CGContext?
    private var trailBitmapSize: CGSize = .zero
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.particleCount = max(50, Int(settings.double("particleCount", default: 700)))
        self.speed = settings.double("speed", default: 1.0)
        self.fadeRate = CGFloat(settings.double("fadeRate", default: 0.02))
        self.fieldScale = settings.double("fieldScale", default: 0.005)
        self.paletteName = settings.string("palette", default: "Sunset")
        spawnAll()
    }

    func resize(_ newSize: CGSize) {
        if newSize != size {
            size = newSize
            trailBitmap = nil
            spawnAll()
        }
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        let t = elapsed * 0.2
        let s = fieldScale
        let stepLen = 1.5 * speed
        for i in 0..<particles.count {
            var p = particles[i]
            // Vector at (x,y,t)
            let vx = sin(p.y * s * 1.3 + t) + cos((p.x + p.y) * s * 0.7 + t * 1.1)
            let vy = cos(p.x * s + t * 0.8) + sin((p.x - p.y) * s * 0.9 - t)
            p.x += vx * stepLen
            p.y += vy * stepLen
            // Recycle when out of bounds.
            if p.x < -10 || p.x > Double(size.width) + 10 || p.y < -10 || p.y > Double(size.height) + 10 {
                p = randomParticle()
            }
            particles[i] = p
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            size = targetSize
            trailBitmap = nil
            spawnAll()
        }
        ensureTrailBitmap()
        guard let trail = trailBitmap else { return }

        // Fade existing trail.
        trail.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.05, alpha: fadeRate))
        trail.fill(CGRect(origin: .zero, size: targetSize))

        // Draw particles as small dots at current position.
        for p in particles {
            let color = colorFor(hue: p.hue)
            trail.setFillColor(color)
            trail.fill(CGRect(x: p.x - 0.6, y: p.y - 0.6, width: 1.5, height: 1.5))
        }

        if let img = trail.makeImage() {
            ctx.draw(img, in: CGRect(origin: .zero, size: targetSize))
        }
    }

    // MARK: - Setup

    private func ensureTrailBitmap() {
        if trailBitmap != nil && trailBitmapSize == size { return }
        let w = Int(size.width.rounded(.up))
        let h = Int(size.height.rounded(.up))
        guard w > 0 && h > 0 else { return }
        let cs = CGColorSpaceCreateDeviceRGB()
        let bi = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let bmp = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: cs, bitmapInfo: bi) else { return }
        bmp.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1))
        bmp.fill(CGRect(x: 0, y: 0, width: w, height: h))
        trailBitmap = bmp
        trailBitmapSize = size
    }

    private func spawnAll() {
        particles = (0..<particleCount).map { _ in randomParticle() }
    }

    private func randomParticle() -> Particle {
        Particle(
            x: Double.random(in: 0...Double(size.width)),
            y: Double.random(in: 0...Double(size.height)),
            hue: Double.random(in: 0..<1)
        )
    }

    private func colorFor(hue: Double) -> CGColor {
        switch paletteName {
        case "Cyan":
            return CGColor(red: 0.2, green: 0.8 + CGFloat(hue) * 0.2, blue: 1.0, alpha: 1)
        case "Spectrum":
            return NSColor(hue: CGFloat(hue), saturation: 0.85, brightness: 1.0, alpha: 1).cgColor
        case "Ember":
            return CGColor(red: 1.0, green: 0.3 + CGFloat(hue) * 0.6, blue: 0.05, alpha: 1)
        default: // Sunset
            return CGColor(red: 1.0, green: 0.5 + CGFloat(hue) * 0.3, blue: 0.4 - CGFloat(hue) * 0.3, alpha: 1)
        }
    }
}
