import Cocoa

/// Truchet tiles: a grid of square tiles, each with a random orientation,
/// such that the inner shapes connect across edges to form continuous
/// flowing curves. We periodically flip one random tile so the pattern
/// "breathes" — visible as ripples of changing connections.
final class TruchetTilesScene: DemoScene {
    static let identifier = "truchet_tiles"
    static let displayName = "Truchet Tiles"

    static let options: [SceneOption] = [
        .slider(key: "tileSize", label: "Tile Size", min: 24, max: 120, defaultValue: 56, format: "%.0f px"),
        .slider(key: "lineWidth", label: "Line Width", min: 1, max: 10, defaultValue: 3, format: "%.0f"),
        .slider(key: "flipsPerSecond", label: "Tile Flips / s", min: 0.5, max: 30, defaultValue: 6, format: "%.0f"),
        .choice(key: "style", label: "Style",
                choices: ["Quarter Arcs", "Diagonal Lines", "Triangles"],
                defaultValue: "Quarter Arcs"),
        .choice(key: "palette", label: "Palette",
                choices: ["Mono", "Cyan-Magenta", "Sunset", "Forest"],
                defaultValue: "Cyan-Magenta"),
    ]

    private var size: CGSize = .zero
    private let tileSize: CGFloat
    private let lineWidth: CGFloat
    private let flipsPerSecond: Double
    private let style: String
    private let paletteName: String

    private var cols: Int = 0
    private var rows: Int = 0
    private var orient: [UInt8] = []   // per-tile orientation 0/1
    private var elapsed: Double = 0
    private var nextFlipAt: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.tileSize = CGFloat(settings.double("tileSize", default: 56))
        self.lineWidth = CGFloat(settings.double("lineWidth", default: 3))
        self.flipsPerSecond = settings.double("flipsPerSecond", default: 6)
        self.style = settings.string("style", default: "Quarter Arcs")
        self.paletteName = settings.string("palette", default: "Cyan-Magenta")
        rebuildGrid()
    }

    func resize(_ newSize: CGSize) {
        size = newSize
        rebuildGrid()
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        while elapsed >= nextFlipAt {
            if !orient.isEmpty {
                let i = Int.random(in: 0..<orient.count)
                orient[i] = 1 - orient[i]
            }
            nextFlipAt += 1.0 / max(0.5, flipsPerSecond)
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        let (bg, fg) = colors()
        ctx.setFillColor(bg)
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        ctx.setStrokeColor(fg)
        ctx.setFillColor(fg)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)

        for row in 0..<rows {
            for col in 0..<cols {
                let x = CGFloat(col) * tileSize
                let y = CGFloat(row) * tileSize
                let o = orient[row * cols + col]
                drawTile(ctx: ctx, originX: x, originY: y, orientation: o)
            }
        }
    }

    // MARK: - Tile drawing

    private func drawTile(ctx: CGContext, originX: CGFloat, originY: CGFloat, orientation: UInt8) {
        let s = tileSize
        switch style {
        case "Diagonal Lines":
            ctx.beginPath()
            if orientation == 0 {
                ctx.move(to: CGPoint(x: originX, y: originY))
                ctx.addLine(to: CGPoint(x: originX + s, y: originY + s))
            } else {
                ctx.move(to: CGPoint(x: originX + s, y: originY))
                ctx.addLine(to: CGPoint(x: originX, y: originY + s))
            }
            ctx.strokePath()
        case "Triangles":
            ctx.beginPath()
            if orientation == 0 {
                ctx.move(to: CGPoint(x: originX, y: originY))
                ctx.addLine(to: CGPoint(x: originX + s, y: originY))
                ctx.addLine(to: CGPoint(x: originX, y: originY + s))
            } else {
                ctx.move(to: CGPoint(x: originX + s, y: originY))
                ctx.addLine(to: CGPoint(x: originX + s, y: originY + s))
                ctx.addLine(to: CGPoint(x: originX, y: originY + s))
            }
            ctx.closePath()
            ctx.fillPath()
        default: // Quarter Arcs
            let r = s / 2
            ctx.beginPath()
            if orientation == 0 {
                ctx.addArc(center: CGPoint(x: originX, y: originY),
                           radius: r, startAngle: 0, endAngle: .pi / 2, clockwise: false)
                ctx.addArc(center: CGPoint(x: originX + s, y: originY + s),
                           radius: r, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
            } else {
                ctx.addArc(center: CGPoint(x: originX + s, y: originY),
                           radius: r, startAngle: 0.5 * .pi, endAngle: .pi, clockwise: false)
                ctx.addArc(center: CGPoint(x: originX, y: originY + s),
                           radius: r, startAngle: 1.5 * .pi, endAngle: 2 * .pi, clockwise: false)
            }
            ctx.strokePath()
        }
    }

    // MARK: - Setup

    private func rebuildGrid() {
        cols = max(1, Int(ceil(size.width / tileSize)))
        rows = max(1, Int(ceil(size.height / tileSize)))
        orient = (0..<(cols * rows)).map { _ in UInt8.random(in: 0...1) }
        nextFlipAt = elapsed + 1.0 / max(0.5, flipsPerSecond)
    }

    private func colors() -> (CGColor, CGColor) {
        switch paletteName {
        case "Mono":          return (CGColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1),
                                       CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1))
        case "Sunset":        return (CGColor(red: 0.10, green: 0.04, blue: 0.15, alpha: 1),
                                       CGColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1))
        case "Forest":        return (CGColor(red: 0.04, green: 0.10, blue: 0.06, alpha: 1),
                                       CGColor(red: 0.60, green: 0.95, blue: 0.55, alpha: 1))
        default:              return (CGColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1),
                                       CGColor(red: 0.30, green: 0.95, blue: 1.00, alpha: 1))
        }
    }
}
