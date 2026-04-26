import Cocoa

/// Two intertwined sine-wave strands with rungs connecting them — the
/// classic DNA double helix. The whole structure scrolls vertically and
/// rotates in 3D so you see different facings.
final class DNAHelixScene: DemoScene {
    static let identifier = "dna"
    static let displayName = "DNA Helix"

    static let options: [SceneOption] = [
        .slider(key: "rungSpacing", label: "Rung Spacing", min: 16, max: 60, defaultValue: 28, format: "%.0f px"),
        .slider(key: "amplitude", label: "Helix Width", min: 60, max: 280, defaultValue: 180, format: "%.0f px"),
        .slider(key: "scrollSpeed", label: "Scroll Speed", min: 0, max: 200, defaultValue: 60, format: "%.0f px/s"),
        .slider(key: "rotateSpeed", label: "Rotation", min: 0, max: 4, defaultValue: 1.5, format: "%.1f rad/s"),
        .choice(key: "tint", label: "Color Scheme",
                choices: ["Bio (A/T/G/C)", "Cyan", "Magenta", "Rainbow"],
                defaultValue: "Bio (A/T/G/C)"),
    ]

    private var size: CGSize = .zero
    private let rungSpacing: CGFloat
    private let amplitude: CGFloat
    private let scrollSpeed: Double
    private let rotateSpeed: Double
    private let tint: String

    private var scrollOffset: CGFloat = 0
    private var rotation: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.rungSpacing = CGFloat(settings.double("rungSpacing", default: 28))
        self.amplitude = CGFloat(settings.double("amplitude", default: 180))
        self.scrollSpeed = settings.double("scrollSpeed", default: 60)
        self.rotateSpeed = settings.double("rotateSpeed", default: 1.5)
        self.tint = settings.string("tint", default: "Bio (A/T/G/C)")
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) {
        scrollOffset += CGFloat(scrollSpeed * dt)
        if scrollOffset > rungSpacing * 4 { scrollOffset -= rungSpacing * 4 }
        rotation += rotateSpeed * dt
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        ctx.setFillColor(CGColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let cx = targetSize.width / 2
        let totalHeight = targetSize.height
        let rungs = Int(totalHeight / rungSpacing) + 4

        // Each rung is at a different "depth" along the helix axis. The
        // helix angle progresses with the rung index, plus the rotation
        // offset that grows over time. We project (depth, angle) to 2D by
        // taking sin/cos of angle for x-offset.
        struct Bead {
            var pos: CGPoint
            var depth: Double      // -1 (back) ... +1 (front)
            var color: CGColor
        }
        struct RungData {
            var left: Bead
            var right: Bead
        }

        var rungData: [RungData] = []
        for i in -2..<rungs {
            let baseY = CGFloat(i) * rungSpacing - scrollOffset.truncatingRemainder(dividingBy: rungSpacing)
            let actualY = totalHeight - baseY  // top to bottom
            if actualY < -rungSpacing || actualY > totalHeight + rungSpacing { continue }
            let angle = Double(i) * 0.6 + rotation
            let leftXOffset = sin(angle) * Double(amplitude)
            let rightXOffset = sin(angle + .pi) * Double(amplitude)
            let leftDepth = cos(angle)
            let rightDepth = cos(angle + .pi)
            let (lc, rc) = pairColor(rungIndex: i)
            rungData.append(RungData(
                left: Bead(pos: CGPoint(x: cx + CGFloat(leftXOffset), y: actualY),
                           depth: leftDepth,
                           color: lc),
                right: Bead(pos: CGPoint(x: cx + CGFloat(rightXOffset), y: actualY),
                            depth: rightDepth,
                            color: rc)
            ))
        }

        // Draw rungs (lines between left & right beads), color-faded by avg depth.
        for r in rungData {
            let avgDepth = (r.left.depth + r.right.depth) / 2
            let alpha = CGFloat((avgDepth + 1.0) / 2.0 * 0.6 + 0.2)
            ctx.setStrokeColor(CGColor(red: 0.8, green: 0.85, blue: 0.95, alpha: alpha))
            ctx.setLineWidth(1.5)
            ctx.beginPath()
            ctx.move(to: r.left.pos)
            ctx.addLine(to: r.right.pos)
            ctx.strokePath()
        }

        // Connecting strands (line through all left beads, then all right).
        // Drawn after rungs so beads sit on top.
        ctx.setLineWidth(2.0)
        ctx.setLineCap(.round)
        ctx.beginPath()
        for (i, r) in rungData.enumerated() {
            if i == 0 { ctx.move(to: r.left.pos) } else { ctx.addLine(to: r.left.pos) }
        }
        ctx.setStrokeColor(CGColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 0.7))
        ctx.strokePath()

        ctx.beginPath()
        for (i, r) in rungData.enumerated() {
            if i == 0 { ctx.move(to: r.right.pos) } else { ctx.addLine(to: r.right.pos) }
        }
        ctx.setStrokeColor(CGColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 0.7))
        ctx.strokePath()

        // Beads. Front-facing beads draw bigger.
        for r in rungData {
            for bead in [r.left, r.right] {
                let scale = CGFloat((bead.depth + 1.0) / 2.0 * 0.6 + 0.4)
                let radius = 6.0 * scale
                ctx.setFillColor(bead.color)
                ctx.fillEllipse(in: CGRect(x: bead.pos.x - radius, y: bead.pos.y - radius,
                                            width: radius * 2, height: radius * 2))
            }
        }
    }

    private func pairColor(rungIndex: Int) -> (CGColor, CGColor) {
        switch tint {
        case "Cyan":
            return (CGColor(red: 0.2, green: 0.95, blue: 1.0, alpha: 1),
                    CGColor(red: 0.0, green: 0.6, blue: 0.95, alpha: 1))
        case "Magenta":
            return (CGColor(red: 1.0, green: 0.3, blue: 0.7, alpha: 1),
                    CGColor(red: 0.6, green: 0.1, blue: 0.85, alpha: 1))
        case "Rainbow":
            let h1 = (Double(rungIndex) * 0.07).truncatingRemainder(dividingBy: 1.0)
            let h2 = (h1 + 0.3).truncatingRemainder(dividingBy: 1.0)
            return (NSColor(hue: CGFloat(h1), saturation: 0.85, brightness: 1.0, alpha: 1).cgColor,
                    NSColor(hue: CGFloat(h2), saturation: 0.85, brightness: 1.0, alpha: 1).cgColor)
        default:
            // Adenine-Thymine / Guanine-Cytosine pairs.
            let pair = (rungIndex % 2 == 0)
                ? (CGColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1),  // A
                   CGColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)) // T
                : (CGColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1),  // G
                   CGColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1))  // C
            return pair
        }
    }
}
