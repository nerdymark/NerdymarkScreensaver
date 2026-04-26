import Cocoa

/// L-system fractal tree: a recursive tree structure draws line by line over
/// several seconds, then fades and starts a new tree with different angle/
/// branching parameters and seasonal palette.
final class LSystemTreeScene: DemoScene {
    static let identifier = "l_system_tree"
    static let displayName = "Fractal Tree"

    static let options: [SceneOption] = [
        .slider(key: "growSpeed", label: "Growth Speed", min: 5, max: 80, defaultValue: 20, format: "%.0f seg/s"),
        .slider(key: "treeLifetime", label: "Tree Lifetime", min: 10, max: 90, defaultValue: 30, format: "%.0fs"),
        .toggle(key: "showLeaves", label: "Show leaves", defaultValue: true),
        .choice(key: "palette", label: "Palette",
                choices: ["Random", "Spring", "Summer", "Autumn", "Winter"],
                defaultValue: "Random"),
    ]

    private struct Segment {
        var x1: CGFloat; var y1: CGFloat
        var x2: CGFloat; var y2: CGFloat
        var depth: Int
    }

    private var size: CGSize = .zero
    private let growSpeed: Double
    private let treeLifetime: Double
    private let showLeaves: Bool
    private let paletteSetting: String

    private var segments: [Segment] = []
    private var grownCount: Int = 0
    private var elapsed: Double = 0
    private var treeStartedAt: Double = 0
    private var trunkColor: CGColor = CGColor(red: 0.4, green: 0.25, blue: 0.1, alpha: 1)
    private var leafColor: CGColor = CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)
    private var bgTop: CGColor = CGColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1)
    private var bgBot: CGColor = CGColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1)

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.growSpeed = settings.double("growSpeed", default: 20)
        self.treeLifetime = settings.double("treeLifetime", default: 30)
        self.showLeaves = settings.bool("showLeaves", default: true)
        self.paletteSetting = settings.string("palette", default: "Random")
        startNewTree()
    }

    func resize(_ newSize: CGSize) {
        if newSize != size {
            size = newSize
            startNewTree()
        }
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        // Reveal more segments per growSpeed.
        let target = Int(Double(elapsed - treeStartedAt) * growSpeed)
        grownCount = min(segments.count, max(0, target))
        if elapsed - treeStartedAt > treeLifetime {
            startNewTree()
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize

        // Background gradient.
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [bgTop, bgBot] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: targetSize.height),
                                    end: CGPoint(x: 0, y: 0), options: [])
        }

        // Tree fade-out near end of life.
        let lifeT = (elapsed - treeStartedAt) / treeLifetime
        let alpha = lifeT < 0.85 ? 1.0 : max(0, 1.0 - (lifeT - 0.85) / 0.15)

        ctx.setLineCap(.round)
        let limit = min(grownCount, segments.count)
        for i in 0..<limit {
            let s = segments[i]
            let lineWidth = max(0.5, CGFloat(8 - s.depth))
            ctx.setStrokeColor(trunkColor.copy(alpha: CGFloat(alpha)) ?? trunkColor)
            ctx.setLineWidth(lineWidth)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: s.x1, y: s.y1))
            ctx.addLine(to: CGPoint(x: s.x2, y: s.y2))
            ctx.strokePath()
        }
        // Leaves at deeper segments' end points.
        if showLeaves {
            ctx.setFillColor(leafColor.copy(alpha: CGFloat(alpha * 0.85)) ?? leafColor)
            for i in 0..<limit {
                let s = segments[i]
                if s.depth >= 5 {
                    let r: CGFloat = 4
                    ctx.fillEllipse(in: CGRect(x: s.x2 - r, y: s.y2 - r, width: r * 2, height: r * 2))
                }
            }
        }
    }

    // MARK: - Tree generation

    private func startNewTree() {
        treeStartedAt = elapsed
        grownCount = 0
        segments.removeAll()
        applyPalette()
        let trunkLen = min(size.width, size.height) * 0.18
        // Random branch angle each tree.
        let angle = Double.random(in: 0.4...0.7)
        let lengthMul = Double.random(in: 0.62...0.78)
        grow(x: size.width / 2, y: size.height * 0.95,
             angle: -.pi / 2,   // up
             length: trunkLen,
             depth: 0,
             angleSpread: angle,
             lengthMul: lengthMul)
    }

    private func grow(x: CGFloat, y: CGFloat, angle: Double, length: CGFloat, depth: Int,
                       angleSpread: Double, lengthMul: Double) {
        if depth > 9 || length < 4 { return }
        let x2 = x + CGFloat(cos(angle)) * length
        let y2 = y + CGFloat(sin(angle)) * length
        segments.append(Segment(x1: x, y1: y, x2: x2, y2: y2, depth: depth))
        let jitter1 = Double.random(in: -0.15...0.15)
        let jitter2 = Double.random(in: -0.15...0.15)
        grow(x: x2, y: y2, angle: angle - angleSpread + jitter1,
             length: length * CGFloat(lengthMul), depth: depth + 1,
             angleSpread: angleSpread, lengthMul: lengthMul)
        grow(x: x2, y: y2, angle: angle + angleSpread + jitter2,
             length: length * CGFloat(lengthMul), depth: depth + 1,
             angleSpread: angleSpread, lengthMul: lengthMul)
        // Sometimes add a third middle branch.
        if Double.random(in: 0...1) < 0.25 {
            grow(x: x2, y: y2, angle: angle + Double.random(in: -0.1...0.1),
                 length: length * CGFloat(lengthMul) * 0.85, depth: depth + 1,
                 angleSpread: angleSpread, lengthMul: lengthMul)
        }
    }

    private func applyPalette() {
        let resolved: String
        if paletteSetting == "Random" {
            resolved = ["Spring", "Summer", "Autumn", "Winter"].randomElement()!
        } else {
            resolved = paletteSetting
        }
        switch resolved {
        case "Summer":
            trunkColor = CGColor(red: 0.35, green: 0.22, blue: 0.10, alpha: 1)
            leafColor = CGColor(red: 0.10, green: 0.65, blue: 0.20, alpha: 1)
            bgTop = CGColor(red: 0.30, green: 0.55, blue: 0.85, alpha: 1)
            bgBot = CGColor(red: 0.85, green: 0.92, blue: 0.95, alpha: 1)
        case "Autumn":
            trunkColor = CGColor(red: 0.30, green: 0.18, blue: 0.08, alpha: 1)
            leafColor = CGColor(red: 0.95, green: 0.45, blue: 0.10, alpha: 1)
            bgTop = CGColor(red: 0.60, green: 0.35, blue: 0.20, alpha: 1)
            bgBot = CGColor(red: 0.20, green: 0.10, blue: 0.06, alpha: 1)
        case "Winter":
            trunkColor = CGColor(red: 0.20, green: 0.18, blue: 0.20, alpha: 1)
            leafColor = CGColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1)
            bgTop = CGColor(red: 0.20, green: 0.25, blue: 0.40, alpha: 1)
            bgBot = CGColor(red: 0.05, green: 0.07, blue: 0.15, alpha: 1)
        default: // Spring
            trunkColor = CGColor(red: 0.40, green: 0.25, blue: 0.10, alpha: 1)
            leafColor = CGColor(red: 0.95, green: 0.65, blue: 0.85, alpha: 1)
            bgTop = CGColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1)
            bgBot = CGColor(red: 0.85, green: 0.95, blue: 0.85, alpha: 1)
        }
    }
}
