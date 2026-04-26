import Cocoa

/// C64-style multi-effect composite: blue letterbox borders, color-cycling
/// raster strip in the borders, big sine-scroll in the middle, and a
/// stationary nerdymark "logo" up top. Pays homage to the genre.
final class C64DemosceneScene: DemoScene {
    static let identifier = "c64_demoscene"
    static let displayName = "C64 Demoscene"

    static let options: [SceneOption] = [
        .slider(key: "scrollSpeed", label: "Scroll Speed", min: 50, max: 400, defaultValue: 180, format: "%.0f px/s"),
        .slider(key: "borderHeight", label: "Border Height", min: 40, max: 200, defaultValue: 100, format: "%.0f px"),
        .toggle(key: "showRasterBars", label: "Show raster bars", defaultValue: true),
        .text(key: "title", label: "Title", defaultValue: "♪ NERDYMARK PRESENTS ♪", placeholder: "Top title…"),
        .text(key: "message", label: "Scroll Text",
              defaultValue: "  WELCOME TO THE C64 ZONE  ★  THIS DEMO RUNS NATIVE IN COCOA  ★  GREETZ TO ALL ON THE OLD SCENE  ★  KEEP THE BREADBIN ALIVE  ★  WE STILL LOVE YOU PETSCII  ★  ",
              placeholder: "Scroller message…"),
    ]

    private var size: CGSize = .zero
    private let scrollSpeed: Double
    private let borderHeight: CGFloat
    private let showRasterBars: Bool
    private let title: String
    private let scrollText: String
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.scrollSpeed = settings.double("scrollSpeed", default: 180)
        self.borderHeight = CGFloat(settings.double("borderHeight", default: 100))
        self.showRasterBars = settings.bool("showRasterBars", default: true)
        let t = settings.string("title", default: "")
        self.title = t.isEmpty ? "♪ NERDYMARK PRESENTS ♪" : t
        let m = settings.string("message", default: "")
        self.scrollText = m.isEmpty ? "  WELCOME TO THE C64 ZONE  ★  " : m
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) { elapsed += dt }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize

        // Light-blue C64 background.
        ctx.setFillColor(CGColor(red: 0.55, green: 0.65, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Dark inner panel.
        let inner = CGRect(x: 30, y: borderHeight, width: targetSize.width - 60, height: targetSize.height - borderHeight * 2)
        ctx.setFillColor(CGColor(red: 0.25, green: 0.30, blue: 0.55, alpha: 1))
        ctx.fill(inner)

        // Top + bottom raster bars in the border zone.
        if showRasterBars {
            drawRasterBar(ctx: ctx, in: CGRect(x: 0, y: targetSize.height - borderHeight, width: targetSize.width, height: borderHeight))
            drawRasterBar(ctx: ctx, in: CGRect(x: 0, y: 0, width: targetSize.width, height: borderHeight))
        }

        // Title at top inside the dark panel.
        drawTitle(ctx: ctx, in: inner)

        // Sine scroll across the middle of the inner panel.
        drawSineScroll(ctx: ctx, in: inner)
    }

    private func drawRasterBar(ctx: CGContext, in rect: CGRect) {
        let barHeight: CGFloat = 6
        var y = rect.minY
        var idx = Int(elapsed * 30)
        while y < rect.maxY {
            let hue = CGFloat((idx % 32)) / 32.0
            ctx.setFillColor(NSColor(hue: hue, saturation: 0.95, brightness: 1.0, alpha: 1).cgColor)
            ctx.fill(CGRect(x: rect.minX, y: y, width: rect.width, height: barHeight))
            y += barHeight
            idx += 1
        }
    }

    private func drawTitle(ctx: CGContext, in rect: CGRect) {
        let font = NSFont(name: "Menlo-Bold", size: 36) ?? NSFont.boldSystemFont(ofSize: 36)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(hue: CGFloat(elapsed.truncatingRemainder(dividingBy: 1)),
                                       saturation: 0.85, brightness: 1.0, alpha: 1),
        ]
        let str = NSAttributedString(string: title, attributes: attrs)
        let s = str.size()
        let pos = CGPoint(x: rect.midX - s.width / 2, y: rect.maxY - s.height - 20)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(at: pos)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSineScroll(ctx: CGContext, in rect: CGRect) {
        let font = NSFont(name: "Menlo-Bold", size: 48) ?? NSFont.boldSystemFont(ofSize: 48)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let fullWidth = NSAttributedString(string: scrollText, attributes: textAttrs).size().width
        let scrollOffset = (elapsed * scrollSpeed).truncatingRemainder(dividingBy: Double(fullWidth))

        let yCenter = rect.midY
        let amp: CGFloat = 30

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        // Clip to inner panel so it doesn't bleed into borders.
        ctx.saveGState()
        ctx.clip(to: rect)

        var charX = rect.minX - CGFloat(scrollOffset)
        var i = 0
        while charX < rect.maxX {
            for ch in scrollText {
                let yOffset = sin((Double(charX) * 0.018) + elapsed * 2.5) * Double(amp)
                let charY = yCenter + CGFloat(yOffset) - 24
                let hue = CGFloat((i + Int(elapsed * 30)) % 32) / 32.0
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(hue: hue, saturation: 0.95, brightness: 1.0, alpha: 1),
                ]
                let s = String(ch)
                let str = NSAttributedString(string: s, attributes: attrs)
                str.draw(at: CGPoint(x: charX, y: charY))
                charX += str.size().width
                i += 1
                if charX > rect.maxX { break }
            }
        }
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
    }
}
