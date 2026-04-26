import Cocoa

/// Classic starfield: stars sit on a 3D ray, advance toward the camera, get
/// projected to 2D each frame. When `z` reaches the near plane, recycle to
/// far plane with new random direction.
final class StarfieldScene: DemoScene {
    static let identifier = "starfield"
    static let displayName = "Starfield"

    static let options: [SceneOption] = [
        .slider(key: "starCount", label: "Stars", min: 50, max: 1500, defaultValue: 500, format: "%.0f"),
        .slider(key: "speed", label: "Warp Speed", min: 0.2, max: 5.0, defaultValue: 1.0, format: "%.1fx"),
        .toggle(key: "streaks", label: "Motion blur streaks", defaultValue: true),
        .choice(key: "palette", label: "Star Color",
                choices: ["White", "Cyan", "Warm", "Rainbow"],
                defaultValue: "White"),
    ]

    private struct Star {
        var x: Double
        var y: Double
        var z: Double      // 1 = near, 0 = far behind camera (won't happen)
        var prevSx: Double // last screen x (for streak)
        var prevSy: Double // last screen y
    }

    private var size: CGSize = .zero
    private var stars: [Star] = []
    private var speed: Double
    private var drawStreaks: Bool
    private let palette: String
    private let starCount: Int

    private static let zMax: Double = 32.0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.speed = settings.double("speed", default: 1.0)
        self.drawStreaks = settings.bool("streaks", default: true)
        self.palette = settings.string("palette", default: "White")
        self.starCount = max(20, Int(settings.double("starCount", default: 500)))
        respawnAll()
    }

    func resize(_ newSize: CGSize) {
        size = newSize
    }

    func tick(dt: TimeInterval) {
        let v = dt * 6.0 * speed
        for i in stars.indices {
            // Save previous screen pos for streaks.
            let (psx, psy) = project(stars[i])
            stars[i].prevSx = psx
            stars[i].prevSy = psy

            stars[i].z -= v
            if stars[i].z <= 0.05 {
                stars[i] = makeStar()
            }
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        for star in stars {
            let (sx, sy) = project(star)
            // Brightness scales with proximity (smaller z = closer = brighter).
            let brightness = max(0.1, min(1.0, 1.0 - star.z / StarfieldScene.zMax))
            let radius = max(0.5, brightness * 2.5)
            let color = colorFor(star: star, brightness: brightness)
            ctx.setStrokeColor(color)
            ctx.setFillColor(color)

            if drawStreaks && star.prevSx != 0 && star.prevSy != 0 {
                ctx.setLineWidth(radius * 0.8)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: star.prevSx, y: star.prevSy))
                ctx.addLine(to: CGPoint(x: sx, y: sy))
                ctx.strokePath()
            }
            ctx.fillEllipse(in: CGRect(x: sx - radius, y: sy - radius, width: radius * 2, height: radius * 2))
        }
    }

    // MARK: - Helpers

    private func project(_ s: Star) -> (Double, Double) {
        let cx = Double(size.width) / 2
        let cy = Double(size.height) / 2
        // Standard pinhole projection: scale = focal / z.
        let focal = Double(min(size.width, size.height)) * 0.6
        let invZ = 1.0 / max(0.05, s.z)
        let sx = cx + s.x * focal * invZ
        let sy = cy + s.y * focal * invZ
        return (sx, sy)
    }

    private func makeStar() -> Star {
        // Spawn at far plane with random angle and offset.
        let angle = Double.random(in: 0..<(2.0 * .pi))
        let r = Double.random(in: 0.05...1.0)   // distance from center axis
        return Star(
            x: cos(angle) * r,
            y: sin(angle) * r,
            z: StarfieldScene.zMax,
            prevSx: 0, prevSy: 0
        )
    }

    private func respawnAll() {
        stars = (0..<starCount).map { _ in
            var s = makeStar()
            // Distribute initial Z so we don't all start at the far plane.
            s.z = Double.random(in: 0.5...StarfieldScene.zMax)
            return s
        }
    }

    private func colorFor(star: Star, brightness: Double) -> CGColor {
        switch palette {
        case "Cyan":
            return CGColor(red: brightness * 0.6, green: brightness, blue: brightness, alpha: 1)
        case "Warm":
            return CGColor(red: brightness, green: brightness * 0.85, blue: brightness * 0.6, alpha: 1)
        case "Rainbow":
            // Hue from x angle so each star keeps a stable color.
            let hue = (atan2(star.y, star.x) / (2.0 * .pi) + 1.0).truncatingRemainder(dividingBy: 1.0)
            return NSColor(hue: CGFloat(hue), saturation: 0.7, brightness: CGFloat(brightness), alpha: 1).cgColor
        default:
            return CGColor(red: brightness, green: brightness, blue: brightness, alpha: 1)
        }
    }
}
