import Cocoa

/// Negative-afterimage illusion: stare at a strongly colored image for ~10
/// seconds, then it disappears (white screen with a black "stare here" dot)
/// — your retina's fatigued cones produce a complementary-color phantom.
/// We loop through several stare-target images, each followed by a reveal
/// phase. A countdown bar at the bottom tells the user how long to look.
final class AfterimageScene: DemoScene {
    static let identifier = "afterimage"
    static let displayName = "Afterimage Illusion"

    static let options: [SceneOption] = [
        .slider(key: "stareSeconds", label: "Stare Duration", min: 6, max: 20, defaultValue: 10, format: "%.0f s"),
        .slider(key: "revealSeconds", label: "Reveal Duration", min: 4, max: 14, defaultValue: 8, format: "%.0f s"),
        .toggle(key: "showInstructions", label: "Show instructions", defaultValue: true),
    ]

    private enum Phase { case staring, revealing, transitioning }

    /// Each "round" shows a colored image then its negative-color reveal.
    private struct Round {
        let title: String
        let draw: (CGContext, CGSize) -> Void
    }

    private var size: CGSize = .zero
    private let stareSeconds: Double
    private let revealSeconds: Double
    private let showInstructions: Bool

    private var rounds: [Round] = []
    private var roundIndex = 0
    private var phase: Phase = .staring
    private var phaseStartedAt: Double = 0
    private var elapsed: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.stareSeconds = settings.double("stareSeconds", default: 10)
        self.revealSeconds = settings.double("revealSeconds", default: 8)
        self.showInstructions = settings.bool("showInstructions", default: true)
        self.rounds = AfterimageScene.makeRounds()
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) {
        elapsed += dt
        let phaseDuration: Double
        switch phase {
        case .staring: phaseDuration = stareSeconds
        case .revealing: phaseDuration = revealSeconds
        case .transitioning: phaseDuration = 0.6
        }
        if elapsed - phaseStartedAt >= phaseDuration {
            advance()
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        let round = rounds[roundIndex]
        let phaseT = elapsed - phaseStartedAt

        switch phase {
        case .staring:
            // Show the colored stare image.
            round.draw(ctx, targetSize)
            drawStareDot(ctx: ctx, size: targetSize)
            if showInstructions {
                let secondsLeft = max(0, stareSeconds - phaseT)
                drawInstruction("Stare at the dot — \(Int(secondsLeft))s", at: .top, ctx: ctx, size: targetSize)
                drawCountdownBar(progress: phaseT / stareSeconds, ctx: ctx, size: targetSize, color: NSColor.white.withAlphaComponent(0.4))
            }

        case .revealing:
            // White (or very light) field — the user's afterimage takes over.
            ctx.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            drawStareDot(ctx: ctx, size: targetSize, dark: true)
            if showInstructions {
                drawInstruction("Keep looking — see the negative colors", at: .top, ctx: ctx, size: targetSize, dark: true)
                drawCountdownBar(progress: phaseT / revealSeconds, ctx: ctx, size: targetSize, color: NSColor.black.withAlphaComponent(0.3))
            }

        case .transitioning:
            // Quick fade from reveal-white to next round's image start.
            let progress = phaseT / 0.6
            ctx.setFillColor(CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            ctx.setAlpha(CGFloat(progress))
            round.draw(ctx, targetSize)
            ctx.setAlpha(1.0)
        }
    }

    private func advance() {
        switch phase {
        case .staring:
            phase = .revealing
        case .revealing:
            phase = .transitioning
            roundIndex = (roundIndex + 1) % rounds.count
        case .transitioning:
            phase = .staring
        }
        phaseStartedAt = elapsed
    }

    // MARK: - Drawing helpers

    private func drawStareDot(ctx: CGContext, size: CGSize, dark: Bool = false) {
        let cx = size.width / 2
        let cy = size.height / 2
        let r: CGFloat = 6
        ctx.setFillColor(dark
            ? CGColor(red: 0, green: 0, blue: 0, alpha: 0.9)
            : CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    private enum LabelPosition { case top, bottom }

    private func drawInstruction(_ text: String, at pos: LabelPosition, ctx: CGContext, size: CGSize, dark: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: dark ? NSColor.black.withAlphaComponent(0.7) : NSColor.white.withAlphaComponent(0.85),
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let pad: CGFloat = 12
        let yPos: CGFloat
        switch pos {
        case .top: yPos = size.height - textSize.height - 30
        case .bottom: yPos = 30
        }
        let bgRect = CGRect(
            x: (size.width - textSize.width - pad * 2) / 2,
            y: yPos,
            width: textSize.width + pad * 2,
            height: textSize.height + pad
        )
        ctx.setFillColor(dark
            ? CGColor(red: 1, green: 1, blue: 1, alpha: 0.55)
            : CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        let path = CGPath(roundedRect: bgRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(at: CGPoint(x: bgRect.minX + pad, y: bgRect.minY + pad / 2))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCountdownBar(progress: Double, ctx: CGContext, size: CGSize, color: NSColor) {
        let barWidth: CGFloat = 240
        let barHeight: CGFloat = 4
        let x = (size.width - barWidth) / 2
        let y: CGFloat = 18
        ctx.setFillColor(color.withAlphaComponent(color.alphaComponent * 0.3).cgColor)
        ctx.fill(CGRect(x: x, y: y, width: barWidth, height: barHeight))
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: x, y: y, width: barWidth * CGFloat(min(1, max(0, progress))), height: barHeight))
    }

    // MARK: - Stare images
    // Each colored image is something the brain easily registers — bold flat
    // shapes with strongly saturated colors so the bleached cones produce
    // a vivid afterimage in the complementary hue.

    private static func makeRounds() -> [Round] {
        return [
            // 1. Cyan-blue circle on red — afterimage = red circle on cyan.
            Round(title: "Cyan circle", draw: { ctx, size in
                ctx.setFillColor(CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1))
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.setFillColor(CGColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 1))
                let r = min(size.width, size.height) * 0.25
                ctx.fillEllipse(in: CGRect(x: size.width / 2 - r, y: size.height / 2 - r, width: r * 2, height: r * 2))
            }),
            // 2. Green stripes on magenta — afterimage = magenta stripes on green.
            Round(title: "Green stripes", draw: { ctx, size in
                ctx.setFillColor(CGColor(red: 1.0, green: 0.0, blue: 0.7, alpha: 1))
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.setFillColor(CGColor(red: 0.0, green: 0.95, blue: 0.2, alpha: 1))
                let count = 8
                let gap = size.width / CGFloat(count)
                for i in 0..<count where i % 2 == 0 {
                    ctx.fill(CGRect(x: CGFloat(i) * gap, y: 0, width: gap, height: size.height))
                }
            }),
            // 3. Yellow square on blue — afterimage = blue on yellow.
            Round(title: "Yellow square", draw: { ctx, size in
                ctx.setFillColor(CGColor(red: 0.05, green: 0.10, blue: 0.95, alpha: 1))
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.setFillColor(CGColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1))
                let s = min(size.width, size.height) * 0.45
                ctx.fill(CGRect(x: size.width / 2 - s / 2, y: size.height / 2 - s / 2, width: s, height: s))
            }),
            // 4. American-flag-ish (intentionally weird colors) — afterimage
            //    "ghost" reads correctly when reversed.
            Round(title: "Inverted flag", draw: { ctx, size in
                // Background = white (so unbleached areas stay neutral).
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(origin: .zero, size: size))
                // Stripes alternating cyan and black.
                let stripeH = size.height / 13
                for i in 0..<13 where i % 2 == 0 {
                    ctx.setFillColor(CGColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 1))
                    ctx.fill(CGRect(x: 0, y: CGFloat(i) * stripeH, width: size.width, height: stripeH))
                }
                // "Canton" = yellow rectangle.
                ctx.setFillColor(CGColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1))
                ctx.fill(CGRect(x: 0, y: size.height - stripeH * 7, width: size.width * 0.4, height: stripeH * 7))
            }),
        ]
    }
}
