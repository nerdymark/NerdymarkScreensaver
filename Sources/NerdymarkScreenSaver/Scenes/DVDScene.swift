import Cocoa

/// The bouncing DVD logo, but it's the nerdymark wordmark. Color cycles
/// every wall-bounce. Yes, we keep score on perfect-corner hits — drawn
/// briefly when achieved.
final class DVDScene: DemoScene {
    static let identifier = "dvd"
    static let displayName = "Bouncing Logo"

    static let options: [SceneOption] = [
        .slider(key: "speed", label: "Speed", min: 50, max: 600, defaultValue: 200, format: "%.0f px/s"),
        .slider(key: "size", label: "Logo Size", min: 36, max: 200, defaultValue: 84, format: "%.0f pt"),
        .toggle(key: "showCornerCount", label: "Show corner-hit counter", defaultValue: true),
        .text(key: "text", label: "Wordmark", defaultValue: "nerdymark", placeholder: "Any text…"),
    ]

    private var size: CGSize = .zero
    private var speed: Double
    private var fontSize: CGFloat
    private var showCornerCount: Bool
    private let wordmark: String

    private var pos: CGPoint = .zero
    private var velocity: CGPoint = .init(x: 1, y: 1)   // unit-ish
    private var hue: Double = 0
    private var cornerHits: Int = 0
    private var cornerFlashUntil: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var textSize: CGSize = .zero

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.speed = settings.double("speed", default: 200)
        self.fontSize = CGFloat(settings.double("size", default: 84))
        self.showCornerCount = settings.bool("showCornerCount", default: true)
        self.wordmark = settings.string("text", default: "nerdymark")
        randomizeStart()
    }

    func resize(_ newSize: CGSize) {
        size = newSize
        clampInside()
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        let dist = speed * dt
        pos.x += velocity.x * dist
        pos.y += velocity.y * dist

        var bouncedX = false
        var bouncedY = false

        // Recompute text bounds (fontSize stable, but hue irrelevant to size).
        if textSize == .zero {
            textSize = measureText()
        }

        if pos.x <= 0 {
            pos.x = 0
            velocity.x = abs(velocity.x)
            bouncedX = true
        } else if pos.x + textSize.width >= size.width {
            pos.x = size.width - textSize.width
            velocity.x = -abs(velocity.x)
            bouncedX = true
        }

        if pos.y <= 0 {
            pos.y = 0
            velocity.y = abs(velocity.y)
            bouncedY = true
        } else if pos.y + textSize.height >= size.height {
            pos.y = size.height - textSize.height
            velocity.y = -abs(velocity.y)
            bouncedY = true
        }

        if bouncedX || bouncedY {
            hue = (hue + 0.13).truncatingRemainder(dividingBy: 1.0)
        }
        if bouncedX && bouncedY {
            cornerHits += 1
            cornerFlashUntil = elapsed + 1.5
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let color = NSColor(hue: CGFloat(hue), saturation: 0.9, brightness: 1.0, alpha: 1.0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: color,
        ]
        let str = NSAttributedString(string: wordmark, attributes: attrs)
        textSize = str.size()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(at: pos)

        // Corner-hit counter.
        if showCornerCount {
            let counterText = "Corner hits: \(cornerHits)"
            let counterAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
            ]
            NSAttributedString(string: counterText, attributes: counterAttrs)
                .draw(at: CGPoint(x: 14, y: 14))
        }

        // "PERFECT" flash on corner hit.
        if elapsed < cornerFlashUntil {
            let alpha = max(0, (cornerFlashUntil - elapsed) / 1.5)
            let flashAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 60, weight: .black),
                .foregroundColor: NSColor.yellow.withAlphaComponent(CGFloat(alpha)),
            ]
            let flash = NSAttributedString(string: "★ PERFECT ★", attributes: flashAttrs)
            let s = flash.size()
            flash.draw(at: CGPoint(x: (targetSize.width - s.width) / 2, y: (targetSize.height - s.height) / 2))
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Helpers

    private func randomizeStart() {
        let angle = Double.random(in: (.pi / 6)...(.pi / 3)) * (Bool.random() ? 1 : -1)
        let dirX = Bool.random() ? 1.0 : -1.0
        velocity = CGPoint(x: cos(angle) * dirX, y: sin(angle))
        let len = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        velocity.x /= len
        velocity.y /= len
        pos = CGPoint(x: size.width * 0.3, y: size.height * 0.3)
        hue = Double.random(in: 0..<1)
        cornerHits = 0
        textSize = .zero
    }

    private func clampInside() {
        if textSize == .zero { textSize = measureText() }
        pos.x = max(0, min(size.width - textSize.width, pos.x))
        pos.y = max(0, min(size.height - textSize.height, pos.y))
    }

    private func measureText() -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        ]
        return NSAttributedString(string: wordmark, attributes: attrs).size()
    }
}
