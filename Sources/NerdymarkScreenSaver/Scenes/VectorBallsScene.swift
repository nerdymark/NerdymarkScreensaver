import Cocoa

/// Old-school "vector balls" — a 3D lattice of shaded spheres rotating in
/// space. Each ball is depth-sorted (painter's algorithm) and rendered as a
/// radial gradient circle for a fake-3D shaded look.
final class VectorBallsScene: DemoScene {
    static let identifier = "vector_balls"
    static let displayName = "Vector Balls"

    static let options: [SceneOption] = [
        .slider(key: "gridSize", label: "Lattice Size", min: 3, max: 7, defaultValue: 5, format: "%.0f"),
        .slider(key: "spinSpeed", label: "Spin Speed", min: 0.1, max: 2.0, defaultValue: 0.6, format: "%.1f rad/s"),
        .slider(key: "ballSize", label: "Ball Size", min: 8, max: 40, defaultValue: 18, format: "%.0f px"),
        .choice(key: "color", label: "Color",
                choices: ["Chrome", "Cyan", "Magenta", "Amber", "Rainbow"],
                defaultValue: "Chrome"),
    ]

    private struct Ball {
        var x: Double
        var y: Double
        var z: Double
        var hue: Double
    }

    private var size: CGSize = .zero
    private let gridSize: Int
    private let spinSpeed: Double
    private let ballSize: CGFloat
    private let colorScheme: String
    private var balls: [Ball] = []
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.gridSize = max(3, min(7, Int(settings.double("gridSize", default: 5))))
        self.spinSpeed = settings.double("spinSpeed", default: 0.6)
        self.ballSize = CGFloat(settings.double("ballSize", default: 18))
        self.colorScheme = settings.string("color", default: "Chrome")
        buildLattice()
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        ctx.setFillColor(CGColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Rotate around X and Y, project, sort, draw.
        let angX = elapsed * spinSpeed
        let angY = elapsed * spinSpeed * 0.7
        let cosX = cos(angX), sinX = sin(angX)
        let cosY = cos(angY), sinY = sin(angY)

        struct Projected { var x: Double; var y: Double; var z: Double; var hue: Double }
        var projected: [Projected] = []
        projected.reserveCapacity(balls.count)
        for b in balls {
            // Rotate Y axis.
            let x1 = b.x * cosY - b.z * sinY
            let z1 = b.x * sinY + b.z * cosY
            // Rotate X axis.
            let y2 = b.y * cosX - z1 * sinX
            let z2 = b.y * sinX + z1 * cosX
            projected.append(Projected(x: x1, y: y2, z: z2, hue: b.hue))
        }
        // Sort back-to-front (z increases away from viewer in our coords).
        projected.sort { $0.z > $1.z }

        let cx = Double(targetSize.width) / 2
        let cy = Double(targetSize.height) / 2
        let focal = Double(min(targetSize.width, targetSize.height)) * 0.6

        for p in projected {
            let invZ = 1.0 / max(0.5, p.z + 6.0)   // push grid forward
            let sx = cx + p.x * focal * invZ
            let sy = cy + p.y * focal * invZ
            let scaleFactor = focal * invZ * 0.05  // ball radius in screen px
            let r = max(2.0, Double(ballSize) * scaleFactor)
            drawBall(ctx: ctx, center: CGPoint(x: sx, y: sy), radius: CGFloat(r), depth: p.z, hue: p.hue)
        }
    }

    // MARK: - Ball rendering

    private func drawBall(ctx: CGContext, center: CGPoint, radius: CGFloat, depth: Double, hue: Double) {
        // Brightness depends on depth (closer = brighter) and on radial distance
        // from highlight center.
        let brightness = max(0.3, min(1.0, 1.0 - (depth + 6.0) / 14.0))
        let baseColor = colorForBall(hue: hue, brightness: CGFloat(brightness))
        let highlight = NSColor(white: 1.0, alpha: 1.0).cgColor
        let shadow = NSColor(white: 0.05, alpha: 1.0).cgColor

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [highlight, baseColor, shadow] as CFArray,
            locations: [0.0, 0.55, 1.0]
        ) else { return }

        let highlightCenter = CGPoint(x: center.x - radius * 0.3, y: center.y + radius * 0.3)
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ctx.clip()
        ctx.drawRadialGradient(gradient,
                                startCenter: highlightCenter, startRadius: 0,
                                endCenter: center, endRadius: radius,
                                options: [])
        ctx.restoreGState()
    }

    private func colorForBall(hue: Double, brightness: CGFloat) -> CGColor {
        switch colorScheme {
        case "Cyan":    return CGColor(red: brightness * 0.2, green: brightness, blue: brightness, alpha: 1)
        case "Magenta": return CGColor(red: brightness, green: brightness * 0.2, blue: brightness * 0.85, alpha: 1)
        case "Amber":   return CGColor(red: brightness, green: brightness * 0.6, blue: brightness * 0.1, alpha: 1)
        case "Rainbow": return NSColor(hue: CGFloat(hue), saturation: 0.9, brightness: brightness, alpha: 1).cgColor
        default:        return CGColor(red: brightness, green: brightness * 0.95, blue: brightness * 0.85, alpha: 1) // Chrome
        }
    }

    // MARK: - Lattice setup

    private func buildLattice() {
        balls.removeAll()
        let n = gridSize
        let half = Double(n - 1) / 2.0
        for i in 0..<n {
            for j in 0..<n {
                for k in 0..<n {
                    let x = (Double(i) - half) * 1.6
                    let y = (Double(j) - half) * 1.6
                    let z = (Double(k) - half) * 1.6
                    let hue = (Double(i + j + k) / Double(n * 3)).truncatingRemainder(dividingBy: 1.0)
                    balls.append(Ball(x: x, y: y, z: z, hue: hue))
                }
            }
        }
    }
}
