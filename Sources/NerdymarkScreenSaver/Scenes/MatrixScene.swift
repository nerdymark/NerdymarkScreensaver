import Cocoa

/// "The Matrix" rain. Columns of falling glyphs with a bright leading head
/// fading into a tail. Glyphs occasionally mutate so the tails shimmer.
final class MatrixScene: DemoScene {
    static let identifier = "matrix"
    static let displayName = "The Matrix"

    static let options: [SceneOption] = [
        .slider(key: "fontSize", label: "Font Size", min: 10, max: 32, defaultValue: 16, format: "%.0f pt"),
        .slider(key: "fallSpeed", label: "Fall Speed", min: 0.3, max: 3.0, defaultValue: 1.0, format: "%.1fx"),
        .slider(key: "density", label: "Density", min: 0.3, max: 1.0, defaultValue: 0.9, format: "%.0f%%"),
        .choice(key: "tint", label: "Tint",
                choices: ["Green", "Amber", "Cyan", "Magenta"],
                defaultValue: "Green"),
    ]

    private struct Column {
        var glyphs: [String]    // visible glyphs from top of column to head
        var headRow: Int        // current head row position
        var speed: Double       // rows per second
        var nextStepAt: TimeInterval
    }

    private var size: CGSize = .zero
    private var fontSize: CGFloat
    private var fallSpeed: Double
    private var density: Double
    private var tint: String
    private var elapsed: TimeInterval = 0

    private var columns: [Column] = []
    private var cellWidth: CGFloat = 0
    private var cellHeight: CGFloat = 0
    private var rows: Int = 0

    // Half-width katakana + ascii — readable but feels Matrix-y.
    private static let glyphPool: [String] = {
        var arr: [String] = []
        // Katakana (half-width range)
        for code in 0xFF66...0xFF9D { if let scalar = Unicode.Scalar(code) { arr.append(String(scalar)) } }
        // ASCII digits and a few symbols
        arr += "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ@$#%&*+-=:".map { String($0) }
        return arr
    }()

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.fontSize = CGFloat(settings.double("fontSize", default: 16))
        self.fallSpeed = settings.double("fallSpeed", default: 1.0)
        self.density = settings.double("density", default: 0.9)
        self.tint = settings.string("tint", default: "Green")
        rebuild()
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        rebuild()
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        for i in columns.indices {
            // Step the column head when its timer expires.
            while elapsed >= columns[i].nextStepAt {
                columns[i].headRow += 1
                let interval = 1.0 / (columns[i].speed * fallSpeed)
                columns[i].nextStepAt += interval

                // Append a fresh glyph at the head.
                columns[i].glyphs.append(MatrixScene.glyphPool.randomElement()!)

                // Mutate a random earlier glyph occasionally for shimmer.
                if columns[i].glyphs.count > 4, Double.random(in: 0...1) < 0.15 {
                    let idx = Int.random(in: 0..<columns[i].glyphs.count)
                    columns[i].glyphs[idx] = MatrixScene.glyphPool.randomElement()!
                }

                // Reset column when fully off-screen.
                if columns[i].headRow > rows + columns[i].glyphs.count {
                    resetColumn(at: i)
                }
            }
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        // Solid black background — no trail blending needed since glyph fade
        // is computed analytically from row distance to the head.
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        for (i, col) in columns.enumerated() {
            let xPos = CGFloat(i) * cellWidth
            let head = col.headRow
            let trailLen = col.glyphs.count
            // Draw from the oldest visible to head so head ends up on top.
            for j in 0..<trailLen {
                let row = head - (trailLen - 1 - j)
                if row < 0 || row >= rows { continue }
                let glyph = col.glyphs[j]
                let isHead = (j == trailLen - 1)
                let distFromHead = trailLen - 1 - j
                // Brightness drops roughly exponentially down the tail.
                let alpha: CGFloat
                if isHead {
                    alpha = 1.0
                } else {
                    alpha = max(0, 0.85 * pow(0.92, CGFloat(distFromHead)))
                }
                let color: CGColor
                if isHead {
                    // Head pop = nearly-white tinted.
                    color = headColor()
                } else {
                    color = bodyColor(alpha: alpha)
                }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(cgColor: color) ?? .green,
                ]
                // Y from top: macOS coordinate is flipped, but we drew background
                // already — use NSGraphicsContext for text since CTLine handling
                // for emoji/CJK is finicky.
                let yPos = targetSize.height - CGFloat(row + 1) * cellHeight
                let str = NSAttributedString(string: glyph, attributes: attrs)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                str.draw(at: CGPoint(x: xPos + 1, y: yPos))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    // MARK: - Build

    private func rebuild() {
        cellWidth = fontSize * 0.65    // monospaced approx width
        cellHeight = fontSize * 1.1
        let cols = max(1, Int(ceil(size.width / cellWidth)))
        rows = max(1, Int(ceil(size.height / cellHeight)))
        columns = (0..<cols).map { _ in makeColumn() }
    }

    private func makeColumn() -> Column {
        let trailLen = Int.random(in: 6...22)
        let glyphs = (0..<trailLen).map { _ in MatrixScene.glyphPool.randomElement()! }
        let speed = Double.random(in: 4...18)   // rows per second
        let startRow = Int.random(in: -rows...0)
        return Column(glyphs: glyphs, headRow: startRow, speed: speed, nextStepAt: elapsed + 1.0 / (speed * fallSpeed))
    }

    private func resetColumn(at i: Int) {
        // Skip a fraction of resets so the screen has empty columns sometimes
        // (matches the original rain look — uneven density).
        if Double.random(in: 0...1) > density {
            // Long delay before respawn.
            columns[i].headRow = -rows * 2
            columns[i].glyphs = [MatrixScene.glyphPool.randomElement()!]
            columns[i].speed = Double.random(in: 4...18)
            columns[i].nextStepAt = elapsed + Double.random(in: 1.0...4.0)
            return
        }
        columns[i] = makeColumn()
    }

    // MARK: - Colors

    private func headColor() -> CGColor {
        switch tint {
        case "Amber":   return CGColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
        case "Cyan":    return CGColor(red: 0.85, green: 1, blue: 1, alpha: 1)
        case "Magenta": return CGColor(red: 1, green: 0.85, blue: 1, alpha: 1)
        default:        return CGColor(red: 0.85, green: 1, blue: 0.85, alpha: 1)
        }
    }

    private func bodyColor(alpha: CGFloat) -> CGColor {
        switch tint {
        case "Amber":   return CGColor(red: 1.0, green: 0.65, blue: 0.05, alpha: alpha)
        case "Cyan":    return CGColor(red: 0.10, green: 0.95, blue: 1.0,  alpha: alpha)
        case "Magenta": return CGColor(red: 1.0, green: 0.20, blue: 0.95,  alpha: alpha)
        default:        return CGColor(red: 0.10, green: 1.0,  blue: 0.30, alpha: alpha)
        }
    }
}
