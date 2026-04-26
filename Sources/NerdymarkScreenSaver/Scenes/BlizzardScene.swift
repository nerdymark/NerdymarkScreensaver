import Cocoa

/// Falling snow with three depth layers so closer flakes move faster and
/// appear larger — gives the scene a 3D feel without any actual 3D math.
final class BlizzardScene: DemoScene {
    static let identifier = "blizzard"
    static let displayName = "Blizzard"

    static let options: [SceneOption] = [
        .slider(key: "flakeCount", label: "Flake Count", min: 100, max: 2000, defaultValue: 600, format: "%.0f"),
        .slider(key: "windStrength", label: "Wind Drift", min: 0, max: 100, defaultValue: 25, format: "%.0f px/s"),
        .slider(key: "fallSpeed", label: "Fall Speed", min: 0.3, max: 3.0, defaultValue: 1.0, format: "%.1fx"),
        .toggle(key: "varyWind", label: "Wind gusts", defaultValue: true),
    ]

    private struct Flake {
        var x: Double
        var y: Double
        var depth: Int   // 0=back, 1=mid, 2=front
        var phase: Double  // for wind oscillation
    }

    private var size: CGSize = .zero
    private var flakes: [Flake] = []
    private let flakeCount: Int
    private var windStrength: Double
    private var fallSpeed: Double
    private let varyWind: Bool
    private var elapsed: TimeInterval = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.flakeCount = max(50, Int(settings.double("flakeCount", default: 600)))
        self.windStrength = settings.double("windStrength", default: 25)
        self.fallSpeed = settings.double("fallSpeed", default: 1.0)
        self.varyWind = settings.bool("varyWind", default: true)
        spawn()
    }

    func resize(_ newSize: CGSize) {
        size = newSize
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        let gust = varyWind ? sin(elapsed * 0.3) * windStrength : windStrength
        for i in flakes.indices {
            let depthMul = 0.4 + Double(flakes[i].depth) * 0.4   // 0.4, 0.8, 1.2
            flakes[i].y += dt * 90.0 * depthMul * fallSpeed
            flakes[i].phase += dt * (0.8 + Double(flakes[i].depth) * 0.2)
            flakes[i].x += dt * (gust * depthMul + sin(flakes[i].phase) * 8.0)

            // Wrap when fallen below screen.
            if flakes[i].y > Double(size.height) + 8 {
                flakes[i].y = -8
                flakes[i].x = Double.random(in: -20...Double(size.width) + 20)
            }
            // Horizontal wrap so flakes don't bunch up at one edge.
            if flakes[i].x > Double(size.width) + 20 {
                flakes[i].x = -20
            } else if flakes[i].x < -20 {
                flakes[i].x = Double(size.width) + 20
            }
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            size = targetSize
        }
        // Dark blue night sky.
        let bgColors = [
            CGColor(red: 0.02, green: 0.04, blue: 0.10, alpha: 1),
            CGColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1),
        ]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: bgColors as CFArray,
                                      locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                    start: CGPoint(x: 0, y: targetSize.height),
                                    end: CGPoint(x: 0, y: 0),
                                    options: [])
        }

        for flake in flakes {
            let radius: CGFloat
            let alpha: CGFloat
            switch flake.depth {
            case 0: radius = 1.0; alpha = 0.4
            case 1: radius = 1.8; alpha = 0.7
            default: radius = 2.8; alpha = 1.0
            }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
            ctx.fillEllipse(in: CGRect(x: flake.x - Double(radius), y: flake.y - Double(radius),
                                        width: Double(radius * 2), height: Double(radius * 2)))
        }
    }

    private func spawn() {
        flakes = (0..<flakeCount).map { i in
            Flake(
                x: Double.random(in: 0...Double(size.width)),
                y: Double.random(in: 0...Double(size.height)),
                depth: i % 3,
                phase: Double.random(in: 0..<(2.0 * .pi))
            )
        }
    }
}
