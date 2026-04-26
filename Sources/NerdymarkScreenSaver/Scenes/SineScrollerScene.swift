import Cocoa

/// Sine scroller: greetz-style horizontally-scrolling text whose vertical
/// position is modulated by sin() per character. Chunk of demo-scene
/// nostalgia.
final class SineScrollerScene: DemoScene {
    static let identifier = "sine_scroller"
    static let displayName = "Sine Scroller"

    static let options: [SceneOption] = [
        .slider(key: "fontSize", label: "Font Size", min: 32, max: 120, defaultValue: 64, format: "%.0f pt"),
        .slider(key: "scrollSpeed", label: "Scroll Speed", min: 50, max: 400, defaultValue: 150, format: "%.0f px/s"),
        .slider(key: "amplitude", label: "Wave Height", min: 20, max: 200, defaultValue: 80, format: "%.0f px"),
        .slider(key: "frequency", label: "Wave Frequency", min: 0.005, max: 0.05, defaultValue: 0.018, format: "%.3f"),
        .choice(key: "color", label: "Color",
                choices: ["Cyan", "Amber", "Magenta", "Rainbow"],
                defaultValue: "Cyan"),
        .text(key: "message", label: "Message",
              defaultValue: "  GREETZ TO THE NERDYMARK CREW  ★  THIS IS A NATIVE COCOA SCREENSAVER, NOT A WEBVIEW  ★  WRITTEN IN SWIFT WITH CORE GRAPHICS  ★  NO JAVASCRIPT WAS HARMED  ★  KEEP YOUR DEMOSCENE ALIVE  ★  ",
              placeholder: "Your scroller message…"),
    ]

    private var size: CGSize = .zero
    private let fontSize: CGFloat
    private let scrollSpeed: Double
    private let amplitude: CGFloat
    private let frequency: Double
    private let colorScheme: String
    private let scrollText: String

    private var scrollOffset: Double = 0
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.fontSize = CGFloat(settings.double("fontSize", default: 64))
        self.scrollSpeed = settings.double("scrollSpeed", default: 150)
        self.amplitude = CGFloat(settings.double("amplitude", default: 80))
        self.frequency = settings.double("frequency", default: 0.018)
        self.colorScheme = settings.string("color", default: "Cyan")
        let userText = settings.string("message", default: "")
        self.scrollText = userText.isEmpty
            ? "  GREETZ TO THE NERDYMARK CREW  ★  THIS IS A NATIVE COCOA SCREENSAVER, NOT A WEBVIEW  ★  "
            : userText
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) {
        scrollOffset += dt * scrollSpeed
        elapsed += dt
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize

        // Dark gradient background.
        ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Tile the scroller text horizontally so it never runs out.
        let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font]

        // Compute total text width once, then start position.
        let fullWidth = NSAttributedString(string: scrollText, attributes: textAttrs).size().width
        let cycleOffset = scrollOffset.truncatingRemainder(dividingBy: Double(fullWidth))
        var x: CGFloat = -CGFloat(cycleOffset)
        let yCenter = targetSize.height / 2

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        while x < targetSize.width {
            // Draw character by character so each can take its own y from sin().
            var charX = x
            for (i, ch) in scrollText.enumerated() {
                let yOffset = sin((Double(charX) * frequency) + elapsed * 2.0) * Double(amplitude)
                let charY = yCenter + CGFloat(yOffset) - fontSize / 2
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(cgColor: charColor(charIndex: i)) ?? .cyan,
                ]
                let s = String(ch)
                let str = NSAttributedString(string: s, attributes: attrs)
                str.draw(at: CGPoint(x: charX, y: charY))
                charX += str.size().width
                if charX > targetSize.width { break }
            }
            x = charX
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func charColor(charIndex: Int) -> CGColor {
        switch colorScheme {
        case "Amber":
            return CGColor(red: 1, green: 0.65, blue: 0.1, alpha: 1)
        case "Magenta":
            return CGColor(red: 1, green: 0.2, blue: 0.85, alpha: 1)
        case "Rainbow":
            let hue = (Double(charIndex) * 0.05 + elapsed * 0.3).truncatingRemainder(dividingBy: 1.0)
            return NSColor(hue: CGFloat(hue), saturation: 0.9, brightness: 1.0, alpha: 1).cgColor
        default: // Cyan
            return CGColor(red: 0.3, green: 0.95, blue: 1.0, alpha: 1)
        }
    }
}
