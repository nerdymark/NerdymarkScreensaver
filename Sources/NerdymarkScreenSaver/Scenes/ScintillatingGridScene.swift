import Cocoa

/// Hermann/scintillating-grid optical illusion: a black field with a grid
/// of light bars; phantom dark dots appear at the intersections in your
/// peripheral vision. We add a slow drift to keep it dynamic.
final class ScintillatingGridScene: DemoScene {
    static let identifier = "scintillating_grid"
    static let displayName = "Scintillating Grid"

    static let options: [SceneOption] = [
        .slider(key: "cellSize", label: "Cell Size", min: 30, max: 120, defaultValue: 60, format: "%.0f px"),
        .slider(key: "barThickness", label: "Bar Thickness", min: 4, max: 30, defaultValue: 14, format: "%.0f px"),
        .slider(key: "intersectionSize", label: "Intersection Dot", min: 2, max: 18, defaultValue: 8, format: "%.0f px"),
        .slider(key: "driftSpeed", label: "Drift Speed", min: 0, max: 60, defaultValue: 12, format: "%.0f px/s"),
        .choice(key: "tint", label: "Tint",
                choices: ["Classic Gray", "Cyan", "Amber", "Magenta"],
                defaultValue: "Classic Gray"),
    ]

    private var size: CGSize = .zero
    private let cellSize: CGFloat
    private let barThickness: CGFloat
    private let intersectionSize: CGFloat
    private let driftSpeed: Double
    private let tint: String
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.cellSize = CGFloat(settings.double("cellSize", default: 60))
        self.barThickness = CGFloat(settings.double("barThickness", default: 14))
        self.intersectionSize = CGFloat(settings.double("intersectionSize", default: 8))
        self.driftSpeed = settings.double("driftSpeed", default: 12)
        self.tint = settings.string("tint", default: "Classic Gray")
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        // Black background.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let driftX = sin(elapsed * 0.2) * driftSpeed
        let driftY = cos(elapsed * 0.17) * driftSpeed

        let barColor = barTint()
        ctx.setFillColor(barColor)

        // Vertical bars at every cellSize column, with horizontal drift.
        var x: CGFloat = (CGFloat(driftX).truncatingRemainder(dividingBy: cellSize))
        while x < targetSize.width {
            ctx.fill(CGRect(x: x - barThickness / 2, y: 0,
                             width: barThickness, height: targetSize.height))
            x += cellSize
        }
        // Horizontal bars.
        var y: CGFloat = (CGFloat(driftY).truncatingRemainder(dividingBy: cellSize))
        while y < targetSize.height {
            ctx.fill(CGRect(x: 0, y: y - barThickness / 2,
                             width: targetSize.width, height: barThickness))
            y += cellSize
        }

        // White dots at intersections — your visual cortex turns them dark in
        // peripheral vision (the actual illusion).
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        var ix: CGFloat = (CGFloat(driftX).truncatingRemainder(dividingBy: cellSize))
        while ix < targetSize.width {
            var iy: CGFloat = (CGFloat(driftY).truncatingRemainder(dividingBy: cellSize))
            while iy < targetSize.height {
                let r = intersectionSize / 2
                ctx.fillEllipse(in: CGRect(x: ix - r, y: iy - r, width: intersectionSize, height: intersectionSize))
                iy += cellSize
            }
            ix += cellSize
        }
    }

    private func barTint() -> CGColor {
        switch tint {
        case "Cyan":    return CGColor(red: 0.3, green: 0.85, blue: 0.95, alpha: 1)
        case "Amber":   return CGColor(red: 0.95, green: 0.6, blue: 0.1,  alpha: 1)
        case "Magenta": return CGColor(red: 0.85, green: 0.2, blue: 0.85, alpha: 1)
        default:        return CGColor(red: 0.55, green: 0.55, blue: 0.6,  alpha: 1)
        }
    }
}
